#if os(macOS)
import Foundation
import Testing
@testable import MiKiduCore

struct KiduAgentProcessRunnerTests {
    let prompt = "Ejemplo $(no-ejecutar) --deliver"

    @Test func openClawUsesSelectedAgentAndSeparateSession() async throws {
        let session = UUID()
        let script = """
        test "$#" -eq 10 || exit 9
        test "$1" = agent && test "$2" = --agent && test "$3" = charla-demo || exit 10
        test "$4" = --session-id && test "$5" = '\(session.uuidString.lowercased())' || exit 11
        test "$6" = --message-file && test "$7" = - && test "$8" = --timeout && test "$9" = 60 && test "${10}" = --json || exit 12
        test "$(/bin/cat)" = '\(prompt)' || exit 13
        /usr/bin/printf '%s' '{"ok":true,"result":{"payloads":[{"text":"Respuesta de OpenClaw ficticio"}]}}'
        """
        let response = try await withFakeCLI(script) { url in
            try await KiduAgentProcessRunner().send(prompt, executable: url, provider: .openClaw,
                                                    sessionID: session, openClawAgent: "charla-demo")
        }
        #expect(response == "Respuesta de OpenClaw ficticio")
    }

    @Test func codexUsesReadOnlyEphemeralModeAndLiteralStdin() async throws {
        let script = """
        test "$#" -eq 15 || exit 8
        test "$1" = --ask-for-approval && test "$2" = never && test "$3" = --disable && test "$4" = shell_tool || exit 9
        test "$5" = -c && test "$6" = 'web_search="disabled"' && test "$7" = exec && test "$8" = --ignore-user-config || exit 10
        test "$9" = --sandbox && test "${10}" = read-only && test "${11}" = --skip-git-repo-check && test "${12}" = --ephemeral || exit 11
        test "${13}" = --color && test "${14}" = never && test "${15}" = - || exit 12
        test "$(/bin/cat)" = '\(prompt)' || exit 13
        /usr/bin/printf '%s' 'Respuesta de Codex ficticio'
        """
        let response = try await withFakeCLI(script) { url in
            try await KiduAgentProcessRunner().send(prompt, executable: url, provider: .codex, sessionID: UUID())
        }
        #expect(response == "Respuesta de Codex ficticio")
    }

    @Test func claudeDisablesToolsAndDoesNotResumeAnExistingSession() async throws {
        let script = """
        test "$#" -eq 16 || exit 8
        test "$1" = --print && test "$2" = --restricted && test "$3" = --tools && test -z "$4" || exit 9
        test "$5" = --disallowedTools && test "$6" = '*' && test "$7" = --no-chrome && test "$8" = --disable-slash-commands || exit 10
        test "$9" = --strict-mcp-config && test "${10}" = --mcp-config && test "${11}" = '{"mcpServers":{}}' || exit 11
        test "${12}" = --no-session-persistence && test "${13}" = --max-turns && test "${14}" = 1 || exit 12
        test "${15}" = --output-format && test "${16}" = json || exit 13
        test "$(/bin/cat)" = '\(prompt)' || exit 14
        /usr/bin/printf '%s' '{"is_error":false,"result":"Respuesta de Claude ficticio"}'
        """
        let response = try await withFakeCLI(script) { url in
            try await KiduAgentProcessRunner().send(prompt, executable: url, provider: .claude, sessionID: UUID())
        }
        #expect(response == "Respuesta de Claude ficticio")
    }

    @Test func localAdapterUsesZeroArgumentsAndReturnsPlainText() async throws {
        let script = """
        test "$#" -eq 0 || exit 9
        test "$(/bin/cat)" = '\(prompt)' || exit 10
        /usr/bin/printf '%s' 'Respuesta del adaptador ficticio'
        """
        let result = try await withFakeCLI(script) { url in
            try await KiduAgentProcessRunner().send(prompt, executable: url, provider: .localAdapter, sessionID: UUID())
        }
        #expect(result == "Respuesta del adaptador ficticio")
    }

    @Test func noReplyAndNonzeroExitAreVisibleErrors() async throws {
        try await withFakeCLI("exit 17") { url in
            await #expect(throws: KiduAgentProcessRunner.Failure.exit(17)) {
                try await KiduAgentProcessRunner().send("Hola", executable: url, provider: .localAdapter, sessionID: UUID())
            }
        }
        try await withFakeCLI("exit 0") { url in
            await #expect(throws: KiduAgentProcessRunner.Failure.response) {
                try await KiduAgentProcessRunner().send("Hola", executable: url, provider: .localAdapter, sessionID: UUID())
            }
        }
    }

    @Test func timeoutAndOversizedOutputAreBounded() async throws {
        try await withFakeCLI("exec /bin/sleep 5") { url in
            let runner = KiduAgentProcessRunner(maximumOutputBytes: 1_024, waitLimit: 0.15)
            let start = ProcessInfo.processInfo.systemUptime
            await #expect(throws: KiduAgentProcessRunner.Failure.timeout) {
                try await runner.send("Hola", executable: url, provider: .localAdapter, sessionID: UUID())
            }
            #expect(ProcessInfo.processInfo.systemUptime - start < 2)
        }
        try await withFakeCLI("exec /usr/bin/yes") { url in
            let runner = KiduAgentProcessRunner(maximumOutputBytes: 1_024, waitLimit: 2)
            await #expect(throws: KiduAgentProcessRunner.Failure.outputSize) {
                try await runner.send("Hola", executable: url, provider: .localAdapter, sessionID: UUID())
            }
        }
    }

    @Test func invalidInputDoesNotLaunch() async throws {
        let neverLaunched = URL(fileURLWithPath: "/example-not-installed")
        for input in ["   ", String(repeating: "x", count: KiduAgentProcessRunner.maximumPromptBytes + 1)] {
            await #expect(throws: KiduAgentProcessRunner.Failure.promptSize) {
                try await KiduAgentProcessRunner().send(input, executable: neverLaunched,
                                                        provider: .localAdapter, sessionID: UUID())
            }
        }
        for agent in ["", "--deliver", "no\n", "agent; other"] {
            await #expect(throws: KiduAgentProcessRunner.Failure.agent) {
                try await KiduAgentProcessRunner().send("Hola", executable: neverLaunched,
                                                        provider: .openClaw, sessionID: UUID(), openClawAgent: agent)
            }
        }
        await #expect(throws: KiduAgentProcessRunner.Failure.executable) {
            try await KiduAgentProcessRunner().send("Hola", executable: neverLaunched,
                                                    provider: .localAdapter, sessionID: UUID())
        }
    }

    private func withFakeCLI<T>(_ body: String, _ perform: (URL) async throws -> T) async throws -> T {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("agente-ficticio")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: executable)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return try await perform(executable)
    }
}
#endif
