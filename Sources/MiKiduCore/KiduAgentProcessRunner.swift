#if os(macOS)
import Darwin
import Foundation

public struct KiduAgentProcessRunner: Sendable {
    public static let maximumPromptBytes = 16_384
    private let maximumOutputBytes: Int
    private let waitLimit: TimeInterval

    public init() {
        self.init(maximumOutputBytes: 65_536, waitLimit: 70)
    }

    init(maximumOutputBytes: Int, waitLimit: TimeInterval) {
        self.maximumOutputBytes = maximumOutputBytes
        self.waitLimit = waitLimit
    }

    public static func canRun(_ executable: URL) -> Bool {
        guard executable.isFileURL else { return false }
        var isDirectory = ObjCBool(false)
        let files = FileManager.default
        return files.fileExists(atPath: executable.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && files.isExecutableFile(atPath: executable.path)
    }

    public func send(_ reviewed: String, executable: URL, provider: KiduAgentProvider,
                     sessionID: UUID, openClawAgent: String = "") async throws -> String {
        guard !reviewed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reviewed.utf8.count <= Self.maximumPromptBytes else { throw Failure.promptSize }
        let arguments = try Self.arguments(for: provider, sessionID: sessionID, openClawAgent: openClawAgent)
        return try await Task.detached(priority: .userInitiated) {
            try execute(Data(reviewed.utf8), executable: executable, provider: provider, arguments: arguments)
        }.value
    }

    public static func validOpenClawAgent(_ agent: String) -> Bool {
        func digitOrLetter(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard let first = agent.utf8.first, digitOrLetter(first), agent.utf8.count <= 64 else { return false }
        return agent.utf8.allSatisfy { digitOrLetter($0) || $0 == 45 || $0 == 95 }
    }

    private static func arguments(for provider: KiduAgentProvider, sessionID: UUID, openClawAgent: String) throws -> [String] {
        switch provider {
        case .openClaw:
            guard validOpenClawAgent(openClawAgent) else { throw Failure.agent }
            return ["agent", "--agent", openClawAgent, "--session-id", sessionID.uuidString.lowercased(),
                    "--message-file", "-", "--timeout", "60", "--json"]
        case .codex:
            return ["--ask-for-approval", "never", "--disable", "shell_tool", "-c", "web_search=\"disabled\"",
                    "exec", "--ignore-user-config", "--sandbox", "read-only", "--skip-git-repo-check",
                    "--ephemeral", "--color", "never", "-"]
        case .claude:
            return ["--print", "--restricted", "--tools", "", "--disallowedTools", "*", "--no-chrome",
                    "--disable-slash-commands", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                    "--no-session-persistence", "--max-turns", "1", "--output-format", "json"]
        case .localAdapter:
            return []
        }
    }

    private func execute(_ input: Data, executable: URL, provider: KiduAgentProvider,
                         arguments: [String]) throws -> String {
        guard Self.canRun(executable) else { throw Failure.executable }
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let path = directory.appendingPathComponent("stdin")
        guard files.createFile(atPath: path.path, contents: input, attributes: [.posixPermissions: 0o600]) else {
            throw Failure.launch
        }
        let stdin = try FileHandle(forReadingFrom: path)
        defer { try? stdin.close() }
        try files.removeItem(at: path) // El proceso solo recibe el descriptor abierto.

        let process = Process()
        let stdout = Pipe()
        let descriptor = stdout.fileHandleForReading.fileDescriptor
        let mode = fcntl(descriptor, F_GETFL)
        guard mode >= 0, fcntl(descriptor, F_SETFL, mode | O_NONBLOCK) >= 0 else { throw Failure.launch }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let inheritedKeys: Set<String> = ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR"]
        var environment = ProcessInfo.processInfo.environment.filter { inheritedKeys.contains($0.key) }
        environment["PATH"] = [
            executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
        ].joined(separator: ":")
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw Failure.launch }
        try? stdout.fileHandleForWriting.close()
        defer {
            stop(process)
            try? stdout.fileHandleForReading.close()
        }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            guard ProcessInfo.processInfo.systemUptime - start < waitLimit else { throw Failure.timeout }
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                guard count <= maximumOutputBytes - output.count else { throw Failure.outputSize }
                output.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { throw Failure.response }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        guard process.terminationStatus == 0 else { throw Failure.exit(process.terminationStatus) }

        return try Self.decode(output, provider: provider)
    }

    private static func decode(_ output: Data, provider: KiduAgentProvider) throws -> String {
        let message: String?
        switch provider {
        case .openClaw:
            guard let envelope = try? JSONDecoder().decode(Response.self, from: output),
                  envelope.ok != false, envelope.status != "in_flight" else { throw Failure.response }
            let messages = envelope.payloads ?? envelope.result?.payloads ?? []
            message = messages.compactMap(\.text).joined(separator: "\n\n")
        case .claude:
            guard let envelope = try? JSONDecoder().decode(ClaudeResponse.self, from: output),
                  envelope.is_error == false else { throw Failure.response }
            message = envelope.result
        case .codex, .localAdapter:
            message = String(data: output, encoding: .utf8)
        }
        guard let response = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else { throw Failure.response }
        return response
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let start = ProcessInfo.processInfo.systemUptime
        while process.isRunning && ProcessInfo.processInfo.systemUptime - start < 0.5 {
            Thread.sleep(forTimeInterval: 0.025)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private struct Response: Decodable {
        struct Payload: Decodable { let text: String? }
        struct ResultBody: Decodable { let payloads: [Payload]? }
        let ok: Bool?
        let status: String?
        let payloads: [Payload]?
        let result: ResultBody?
    }

    private struct ClaudeResponse: Decodable { let is_error: Bool; let result: String? }

    public enum Failure: Error, LocalizedError, Equatable, Sendable {
        case promptSize, executable, launch, timeout, outputSize, response, busy, agent
        case exit(Int32)

        public var errorDescription: String? {
            switch self {
            case .promptSize: "Escribe un encargo de hasta 16 KiB."
            case .executable: "El archivo elegido ya no es un ejecutable. Selecciónalo de nuevo."
            case .launch: "No se pudo iniciar el ejecutable. Comprueba tu instalación."
            case .timeout: "El proveedor tardó demasiado. Revisa su sesión antes de volver a enviar."
            case .outputSize: "La respuesta superó el límite de 64 KiB."
            case .response: "El proveedor no devolvió una respuesta de texto válida."
            case .busy: "Ya hay un turno en curso."
            case .agent: "Indica el identificador de tu agente de OpenClaw para conversación."
            case .exit(let status): "El proceso terminó con el código \(status). Revisa su sesión o prueba el comando en su terminal."
            }
        }
    }
}
#endif
