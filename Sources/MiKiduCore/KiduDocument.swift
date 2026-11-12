import Foundation

/// Identidad recibida mediante un enlace de confianza. Este tipo no autentica al emisor.
public enum KiduAvatarKind: String, Codable, Sendable { case child, adult }

public struct KiduProfile: Codable, Equatable, Sendable {
    public let personKey: UUID
    public let seedInput: String
    public let seedVersion: Int
    public let kind: KiduAvatarKind
    public let displayName: String
    public let color: String?

    public init(personKey: UUID, seedInput: String, seedVersion: Int = 1,
                displayName: String, kind: KiduAvatarKind, color: String? = nil) {
        self.personKey = personKey
        self.seedInput = seedInput
        self.seedVersion = seedVersion
        self.kind = kind
        self.displayName = displayName
        self.color = color
    }
}

public enum KiduCareAction: String, Codable, CaseIterable, Sendable {
    case alimentar, beberAgua, acariciar, jugar, dormir, despertar
}

/// Extensión de cuidados; no reemplaza ni modifica la instantánea del mundo existente.
public struct KiduCareState: Codable, Equatable, Sendable {
    public private(set) var food = 70
    public private(set) var water = 70
    public private(set) var energy = 80
    public private(set) var joy = 70
    public private(set) var resting = false

    public init(resting: Bool = false) { self.resting = resting }

    mutating func apply(_ action: KiduCareAction) {
        switch action {
        case .alimentar: food = min(100, food + 20)
        case .beberAgua: water = min(100, water + 25)
        case .acariciar: joy = min(100, joy + 10)
        case .jugar: joy = min(100, joy + 15); energy = max(0, energy - 5)
        case .dormir: resting = true
        case .despertar:
            if resting { energy = min(100, energy + 10) }
            resting = false
        }
    }

    var valid: Bool { [food, water, energy, joy].allSatisfy { (0...100).contains($0) } }
}

public struct KiduDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let profile: KiduProfile
    /// Bytes originales, con dueño y versión comprobados. No se reserializan ni se suman puntos importados.
    public let originalWorld: Data
    public private(set) var care: KiduCareState
    public private(set) var revision: Int64

    public init(profile: KiduProfile, originalWorld: Data) throws {
        schemaVersion = 1
        self.profile = profile
        self.originalWorld = originalWorld
        let world = try Self.readWorld(originalWorld)
        care = KiduCareState(resting: world.descansando ?? false)
        revision = 0
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == 1, profile.seedVersion == 1,
              !profile.seedInput.isEmpty, profile.seedInput.utf8.count <= 1_024,
              !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.displayName.count <= 40, care.valid, revision >= 0 else { throw KiduError.invalidDocument }
        let world = try Self.readWorld(originalWorld)
        guard world.version == 1 else { throw KiduError.invalidDocument }
        guard world.cuenta == profile.personKey else { throw KiduError.wrongOwner }
        if let color = profile.color {
            guard ["a1", "a2", "a3", "a4"].contains(color) || color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                throw KiduError.invalidDocument
            }
        }
    }

    mutating func apply(_ action: KiduCareAction) throws {
        guard revision < Int64.max else { throw KiduError.invalidDocument }
        if care.resting && [.alimentar, .beberAgua, .jugar].contains(action) { throw KiduError.resting }
        care.apply(action)
        revision += 1
    }

    private struct WorldHeader: Decodable {
        let version: Int
        let cuenta: UUID
        let descansando: Bool?
    }
    private static func readWorld(_ data: Data) throws -> WorldHeader {
        guard !data.isEmpty, data.count <= 2_000_000 else { throw KiduError.invalidDocument }
        do { return try JSONDecoder().decode(WorldHeader.self, from: data) }
        catch { throw KiduError.invalidDocument }
    }
}

public struct KiduCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let personKey: UUID
    public let deviceID: UUID
    public let sequence: Int64
    public let expectedRevision: Int64
    public let rulesVersion: Int
    public let action: KiduCareAction

    public init(id: UUID = UUID(), personKey: UUID, deviceID: UUID, sequence: Int64,
                expectedRevision: Int64, action: KiduCareAction, rulesVersion: Int = 1) {
        self.id = id; self.personKey = personKey; self.deviceID = deviceID
        self.sequence = sequence; self.expectedRevision = expectedRevision
        self.action = action; self.rulesVersion = rulesVersion
    }
}

public struct KiduReceipt: Codable, Equatable, Sendable {
    public let command: KiduCommand
    public let committedRevision: Int64
    public let acceptedAt: Date
    /// Los cuidados no acuñan puntos del mundo ni premios de competición.
    public let awardedPoints: Int
}

public struct KiduApplyResult: Codable, Equatable, Sendable {
    public let receipt: KiduReceipt
    public let document: KiduDocument
    public let duplicate: Bool
}

public enum KiduError: Error, Equatable, Sendable, LocalizedError {
    case invalidDocument, wrongOwner, notInitialized, alreadyInitialized
    case unauthorizedDevice, invalidCommand, commandIDReused
    case sequenceGap(expected: Int64), revisionConflict(current: Int64)
    case storageUnavailable, storageCorrupt, busy, resting

    public var errorDescription: String? {
        switch self {
        case .invalidDocument: "El estado de Kidu no es válido."
        case .wrongOwner: "Este estado pertenece a otro Kidu."
        case .notInitialized: "Enlaza tu Kidu para continuar."
        case .alreadyInitialized: "Ya existe un Kidu en este almacén."
        case .unauthorizedDevice: "Este dispositivo aún no está enlazado."
        case .invalidCommand: "No se pudo interpretar esta acción."
        case .commandIDReused: "La acción ya existe con otros datos."
        case .sequenceGap: "Faltan acciones por sincronizar."
        case .revisionConflict: "El estado ha cambiado; actualízalo y vuelve a intentarlo."
        case .storageUnavailable: "No se pudo guardar; vuelve a intentarlo."
        case .storageCorrupt: "No se pudo abrir el estado guardado."
        case .busy: "Hay otra acción en curso; vuelve a intentarlo."
        case .resting: "Despierta a Kidu para continuar."
        }
    }
}
