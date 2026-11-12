import Foundation

public enum KiduServiceOperation: String, Codable, Sendable { case health, snapshot, action }
public struct KiduServiceRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let operation: KiduServiceOperation
    public let command: KiduCommand?
    public init(protocolVersion: Int = 1, requestID: UUID = UUID(), operation: KiduServiceOperation, command: KiduCommand? = nil) {
        self.protocolVersion = protocolVersion; self.requestID = requestID
        self.operation = operation; self.command = command
    }
}
public enum KiduServiceStatus: String, Codable, Sendable {
    case ready, applied, duplicate, incompatibleVersion, invalidRequest, unauthorizedDevice
    case notLinked, wrongOwner, conflict, sequenceGap, commandIDReused, resting
    case busy, storageUnavailable, storageCorrupt
}
public struct KiduServiceReply: Codable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let status: KiduServiceStatus
    public let revision: Int64?
    public let expectedSequence: Int64?
    public let document: KiduDocument?
    public let result: KiduApplyResult?
}

/// El transporte debe proporcionar un deviceID obtenido de credenciales verificadas,
/// nunca del mensaje recibido. Este servicio no autentica una conexión de red.
public struct KiduService: Sendable {
    public let store: KiduStore
    public init(store: KiduStore) { self.store = store }

    public func handle(_ request: KiduServiceRequest, authenticatedDeviceID: UUID) async -> KiduServiceReply {
        func reply(_ status: KiduServiceStatus, revision: Int64? = nil, sequence: Int64? = nil,
                   document: KiduDocument? = nil, result: KiduApplyResult? = nil) -> KiduServiceReply {
            KiduServiceReply(protocolVersion: 1, requestID: request.requestID, status: status,
                             revision: revision, expectedSequence: sequence, document: document, result: result)
        }
        guard request.protocolVersion == 1 else { return reply(.incompatibleVersion) }
        guard (request.operation == .action) == (request.command != nil) else { return reply(.invalidRequest) }
        do {
            try await store.checkDevice(authenticatedDeviceID)
            switch request.operation {
            case .health:
                let document = try await store.snapshot()
                return reply(.ready, revision: document.revision)
            case .snapshot:
                let document = try await store.snapshot()
                return reply(.ready, revision: document.revision, document: document)
            case .action:
                guard let command = request.command, command.deviceID == authenticatedDeviceID else {
                    return reply(.unauthorizedDevice)
                }
                let result = try await store.apply(command)
                return reply(result.duplicate ? .duplicate : .applied, revision: result.document.revision, result: result)
            }
        } catch let error as KiduError {
            switch error {
            case .unauthorizedDevice: return reply(.unauthorizedDevice)
            case .notInitialized: return reply(.notLinked)
            case .wrongOwner: return reply(.wrongOwner)
            case .revisionConflict(let current): return reply(.conflict, revision: current)
            case .sequenceGap(let expected): return reply(.sequenceGap, sequence: expected)
            case .commandIDReused: return reply(.commandIDReused)
            case .resting: return reply(.resting)
            case .busy: return reply(.busy)
            case .storageCorrupt, .invalidDocument: return reply(.storageCorrupt)
            case .invalidCommand, .alreadyInitialized: return reply(.invalidRequest)
            case .storageUnavailable: return reply(.storageUnavailable)
            }
        } catch { return reply(.storageUnavailable) }
    }
}
