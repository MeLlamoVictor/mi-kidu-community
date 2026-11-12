import XCTest
import Foundation
@testable import MiKiduCore

@MainActor
final class KiduServiceTests: XCTestCase {
    func testTransportIdentityCannotBeReplacedByPayload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), device = UUID(), other = UUID()
        let document = try KiduDocument(profile: KiduProfile(personKey: owner, seedInput: "semilla", displayName: "Kidu", kind: .adult),
            originalWorld: Data("{\"version\":1,\"cuenta\":\"\(owner)\",\"puntos\":0}".utf8))
        let store = KiduStore(url: directory.appendingPathComponent("world.sqlite"))
        try await store.initialize(document, deviceID: device)
        let service = KiduService(store: store)
        let denied = await service.handle(KiduServiceRequest(operation: .snapshot), authenticatedDeviceID: other)
        XCTAssertEqual(denied.status, .unauthorizedDevice)
        XCTAssertNil(denied.document)
        let health = await service.handle(KiduServiceRequest(operation: .health), authenticatedDeviceID: device)
        XCTAssertEqual(health.status, .ready)
        XCTAssertNil(health.document)
        let forged = KiduCommand(personKey: owner, deviceID: other, sequence: 1, expectedRevision: 0, action: .jugar)
        let rejected = await service.handle(KiduServiceRequest(operation: .action, command: forged), authenticatedDeviceID: device)
        XCTAssertEqual(rejected.status, .unauthorizedDevice)
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot, document)
    }

    func testServiceVersionAndRetryAreExplicit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), device = UUID()
        let document = try KiduDocument(profile: KiduProfile(personKey: owner, seedInput: "semilla", displayName: "Kidu", kind: .child),
            originalWorld: Data("{\"version\":1,\"cuenta\":\"\(owner)\"}".utf8))
        let store = KiduStore(url: directory.appendingPathComponent("world.sqlite"))
        try await store.initialize(document, deviceID: device)
        let service = KiduService(store: store)
        let incompatible = await service.handle(KiduServiceRequest(protocolVersion: 2, operation: .health), authenticatedDeviceID: device)
        XCTAssertEqual(incompatible.status, .incompatibleVersion)
        let command = KiduCommand(personKey: owner, deviceID: device, sequence: 1, expectedRevision: 0, action: .beberAgua)
        let request = KiduServiceRequest(operation: .action, command: command)
        let first = await service.handle(request, authenticatedDeviceID: device)
        let replay = await service.handle(request, authenticatedDeviceID: device)
        XCTAssertEqual(first.status, .applied)
        XCTAssertEqual(replay.status, .duplicate)
        XCTAssertEqual(first.requestID, request.requestID)
        XCTAssertEqual(first.result?.receipt, replay.result?.receipt)
        XCTAssertEqual(replay.revision, 1)
        let roundTrip = try JSONDecoder().decode(KiduServiceReply.self, from: JSONEncoder().encode(replay))
        XCTAssertEqual(roundTrip.result, replay.result)
    }
}
