import Foundation

/// Snapshot de solo lectura para superficies fuera de la app. No contiene identidad canónica.
public struct MiKiduSnapshotV1: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case unlinked, ready, error }
    public enum SaveSync: String, Codable, Sendable { case saved, pending, syncing, offline, error }
    public enum Action: String, Codable, CaseIterable, Sendable {
        case feed, drink, pet, play, sleep, wake
    }

    public var state: State
    public var name: String?
    public var isSleeping: Bool
    public var availableActions: Set<Action>
    public var saveSync: SaveSync
    /// Texto localizado y seguro para mostrar; nunca transportar localizedDescription en bruto.
    public var message: String?
    public var updatedAt: Date

    public init(state: State, name: String? = nil, isSleeping: Bool = false,
                availableActions: Set<Action> = [], saveSync: SaveSync = .saved,
                message: String? = nil, updatedAt: Date = .now) {
        self.state = state
        self.name = name
        self.isSleeping = isSleeping
        self.availableActions = availableActions
        self.saveSync = saveSync
        self.message = message
        self.updatedAt = updatedAt
    }
}

/// Endpoint que el target registra con AppDependencyManager y adapta al KiduStore común.
public protocol MiKiduCareActionEndpointV1: Sendable {
    func snapshot() async throws -> MiKiduSnapshotV1
    /// Debe volver solo tras persistencia confirmada en SQLite y outbox.
    func performAndPersist(_ action: MiKiduSnapshotV1.Action) async throws
}
