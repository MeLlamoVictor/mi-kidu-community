import Foundation
import MiKiduCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct MiKiduServiceCLI {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 5, ["serve", "import"].contains(arguments[0]),
                  arguments[1] == "--database", arguments[3] == "--device",
                  arguments[2].hasPrefix("/"), let device = UUID(uuidString: arguments[4]) else {
                throw CLIError.arguments
            }
            let store = KiduStore(url: URL(fileURLWithPath: arguments[2]))
            // 'import' es una operación administrativa local. El comando SSH forzado solo permite 'serve'.
            let limit = arguments[0] == "import" ? 3_000_000 : 65_536
            let data = try readInput(limit: limit)
            if arguments[0] == "import" {
                let document = try JSONDecoder().decode(KiduDocument.self, from: data)
                try await store.initialize(document, deviceID: device)
                try FileHandle.standardOutput.write(contentsOf: Data("{\"protocolVersion\":1,\"status\":\"imported\"}\n".utf8))
            } else {
                let request = try JSONDecoder().decode(KiduServiceRequest.self, from: data)
                let reply = await KiduService(store: store).handle(request, authenticatedDeviceID: device)
                var output = try JSONEncoder().encode(reply)
                output.append(10)
                try FileHandle.standardOutput.write(contentsOf: output)
            }
        } catch {
            // No imprimir payload, rutas, credenciales ni mensajes internos de SQLite.
            let message = "{\"protocolVersion\":1,\"status\":\"invalidInputOrConfiguration\"}\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }
    private static func readInput(limit: Int) throws -> Data {
        var data = Data()
        while let chunk = try FileHandle.standardInput.read(upToCount: min(4_096, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            if data.count > limit { throw CLIError.tooLarge }
        }
        guard !data.isEmpty else { throw CLIError.empty }
        return data
    }
    private enum CLIError: Error { case arguments, tooLarge, empty }
}
