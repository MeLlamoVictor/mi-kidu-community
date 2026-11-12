import Foundation
import MiKiduCore

/// Solo resuelve contenedores del propio producto. Nunca lee el llavero ni la carpeta de SuperKidual.
struct KiduLocalEnvironment: Sendable {
    let container: URL
    var store: KiduStore { KiduStore(url: container.appendingPathComponent("kidu.sqlite")) }

    static func app() throws -> Self {
        if let shared = shared() { return shared }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(container: support.appendingPathComponent("MiKiduCommunity", isDirectory: true))
    }
    static func shared() -> Self? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MiKiduAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$("),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return Self(container: url.appendingPathComponent("MiKiduCommunity", isDirectory: true))
    }
    func deviceID(create: Bool = false) throws -> UUID {
        let file = container.appendingPathComponent("device-v1.json")
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file))
        }
        guard create else { throw KiduError.notInitialized }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let id = UUID()
        do {
            try JSONEncoder().encode(id).write(to: file, options: [.withoutOverwriting])
            return id
        } catch {
            // Otro proceso pudo completar el alta; leer solo un identificador íntegro.
            guard FileManager.default.fileExists(atPath: file.path) else { throw KiduError.storageUnavailable }
            return try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file))
        }
    }
}
