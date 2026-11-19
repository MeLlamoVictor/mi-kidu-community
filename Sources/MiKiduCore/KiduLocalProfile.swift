import Foundation

public enum KiduLocalProfile {
    /// El nombre da forma al avatar. El dueño recibe un UUID independiente del nombre.
    public static func create(named input: String, personKey: UUID = UUID()) throws -> KiduDocument {
        let name = input.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (1...40).contains(name.count), name.utf8.count <= 256,
              name.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control }) else {
            throw NameError.invalid
        }

        let normalized = name.lowercased().precomposedStringWithCanonicalMapping
        // FNV-1a de 64 bits, estable entre procesos y plataformas. Se usa solo para el dibujo.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let seed = "community-name-v1-" + String(hash, radix: 16)
        let profile = KiduProfile(personKey: personKey, seedInput: seed, displayName: name, kind: .adult)
        let world = try JSONEncoder().encode(InitialWorld(cuenta: personKey))
        return try KiduDocument(profile: profile, originalWorld: world)
    }

    public enum NameError: Error, Equatable, LocalizedError, Sendable {
        case invalid

        public var errorDescription: String? { "Escribe un nombre de entre 1 y 40 caracteres." }
    }

    private struct InitialWorld: Encodable {
        let version = 1
        let cuenta: UUID
    }
}

/// Acceso web al proveedor. La edición actual no dispone de un registro de cliente.
public enum KiduAccountAccess {
    public static let website = URL(string: "https://www.kidual.com/")!
    public static let availabilityMessage = "La vinculación con Kidual aún no está disponible en esta edición."
}
