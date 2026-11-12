import XCTest
import Foundation
import CSQLite
@testable import MiKiduCore

@MainActor
final class KiduStoreTests: XCTestCase {
    private var folder: URL!
    private var database: URL { folder.appendingPathComponent("kidu.sqlite") }
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("kidu-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private func fixture() throws -> KiduDocument {
        let owner = UUID()
        let world = "{\"version\":1,\"cuenta\":\"\(owner)\",\"puntos\":37,\"desconocido\":[1,2,3]}"
        return try KiduDocument(profile: KiduProfile(personKey: owner, seedInput: "seed-inmutable", displayName: "Kidu Luna", kind: .adult), originalWorld: Data(world.utf8))
    }
    private func sql(_ command: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, command, nil, nil, nil), SQLITE_OK)
    }
    func testReplayAfterRestartKeepsIdentityWorldAndBalance() async throws {
        let initial = try fixture(), device = UUID(), store = KiduStore(url: database)
        try await store.initialize(initial, deviceID: device)
        let command = KiduCommand(personKey: initial.profile.personKey, deviceID: device, sequence: 1, expectedRevision: 0, action: .alimentar)
        let first = try await store.apply(command)
        let restarted = KiduStore(url: database)
        let replay = try await restarted.apply(command)
        XCTAssertTrue(replay.duplicate)
        XCTAssertEqual(first.receipt, replay.receipt)
        XCTAssertEqual(replay.document.revision, 1)
        XCTAssertEqual(replay.document.profile, initial.profile)
        XCTAssertEqual(replay.document.originalWorld, initial.originalWorld)
        XCTAssertEqual(replay.receipt.awardedPoints, 0)
        let pending = try await restarted.pendingReceipts()
        XCTAssertEqual(pending.count, 1)
        try await restarted.acknowledge(first.receipt)
        let afterAcknowledgement = try await store.pendingReceipts()
        XCTAssertTrue(afterAcknowledgement.isEmpty)
    }
    func testDifferentPayloadCannotReuseCommandIdentifier() async throws {
        let initial = try fixture(), device = UUID(), store = KiduStore(url: database), id = UUID()
        try await store.initialize(initial, deviceID: device)
        _ = try await store.apply(KiduCommand(id: id, personKey: initial.profile.personKey, deviceID: device, sequence: 1, expectedRevision: 0, action: .alimentar))
        do {
            _ = try await store.apply(KiduCommand(id: id, personKey: initial.profile.personKey, deviceID: device, sequence: 1, expectedRevision: 0, action: .beberAgua))
            XCTFail("Reutilizó UUID con otros datos")
        } catch { XCTAssertEqual(error as? KiduError, .commandIDReused) }
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(snapshot.care.water, 70)
    }
    func testConcurrentConnectionsAllocateSequenceAtomically() async throws {
        let initial = try fixture(), device = UUID(), first = KiduStore(url: database), second = KiduStore(url: database)
        try await first.initialize(initial, deviceID: device)
        async let a = first.perform(.alimentar, deviceID: device)
        async let b = second.perform(.beberAgua, deviceID: device)
        let result = try await [a, b]
        XCTAssertEqual(Set(result.map { $0.receipt.command.sequence }), [1, 2])
        let snapshot = try await first.snapshot()
        XCTAssertEqual(snapshot.revision, 2)
        XCTAssertEqual(snapshot.care.food, 90)
        XCTAssertEqual(snapshot.care.water, 95)
    }
    func testFailedReceiptWriteRollsBackWorldAndDeviceSequence() async throws {
        let initial = try fixture(), device = UUID(), store = KiduStore(url: database)
        try await store.initialize(initial, deviceID: device)
        try sql("CREATE TRIGGER fail_receipt BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT,'injected disk failure'); END")
        do { _ = try await store.perform(.jugar, deviceID: device); XCTFail("Debía fallar") }
        catch { XCTAssertEqual(error as? KiduError, .storageUnavailable) }
        let unchanged = try await store.snapshot(), pending = try await store.pendingReceipts()
        XCTAssertEqual(unchanged, initial)
        XCTAssertTrue(pending.isEmpty)
        try sql("DROP TRIGGER fail_receipt")
        let recovered = try await KiduStore(url: database).perform(.jugar, deviceID: device)
        XCTAssertEqual(recovered.receipt.command.sequence, 1)
        XCTAssertEqual(recovered.document.revision, 1)
    }
    func testOwnerDeviceRevisionAndSequenceAreEnforced() async throws {
        let initial = try fixture(), device = UUID(), store = KiduStore(url: database)
        try await store.initialize(initial, deviceID: device)
        let cases: [(KiduCommand, KiduError)] = [
            (KiduCommand(personKey: UUID(), deviceID: device, sequence: 1, expectedRevision: 0, action: .alimentar), .wrongOwner),
            (KiduCommand(personKey: initial.profile.personKey, deviceID: UUID(), sequence: 1, expectedRevision: 0, action: .alimentar), .unauthorizedDevice),
            (KiduCommand(personKey: initial.profile.personKey, deviceID: device, sequence: 2, expectedRevision: 0, action: .alimentar), .sequenceGap(expected: 1)),
            (KiduCommand(personKey: initial.profile.personKey, deviceID: device, sequence: 1, expectedRevision: 8, action: .alimentar), .revisionConflict(current: 0))
        ]
        for (command, expected) in cases {
            do { _ = try await store.apply(command); XCTFail("Aceptó acción inválida") }
            catch { XCTAssertEqual(error as? KiduError, expected) }
        }
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot, initial)
    }
    func testSleepBlocksPlayWithoutAdvancingRevisionAndWakesExplicitly() async throws {
        let initial = try fixture(), device = UUID(), store = KiduStore(url: database)
        try await store.initialize(initial, deviceID: device)
        _ = try await store.perform(.dormir, deviceID: device)
        do { _ = try await store.perform(.jugar, deviceID: device); XCTFail("Jugó dormido") }
        catch { XCTAssertEqual(error as? KiduError, .resting) }
        let sleeping = try await store.snapshot()
        XCTAssertTrue(sleeping.care.resting)
        XCTAssertEqual(sleeping.revision, 1)
        let awake = try await store.perform(.despertar, deviceID: device)
        XCTAssertFalse(awake.document.care.resting)
        XCTAssertEqual(awake.receipt.command.sequence, 2)
    }
    func testMissingCorruptAndExistingStoresNeverCreateReplacementWorld() async throws {
        let store = KiduStore(url: database), initial = try fixture(), device = UUID()
        do { _ = try await store.snapshot(); XCTFail("Creó estado sin enlace") }
        catch { XCTAssertEqual(error as? KiduError, .notInitialized) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
        try await store.initialize(initial, deviceID: device)
        do { try await store.initialize(fixture(), deviceID: UUID()); XCTFail("Sobrescribió dueño") }
        catch { XCTAssertEqual(error as? KiduError, .alreadyInitialized) }
        try sql("UPDATE document SET data=x'00'")
        do { _ = try await store.snapshot(); XCTFail("Ocultó corrupción") }
        catch { XCTAssertEqual(error as? KiduError, .storageCorrupt) }
        do { try await store.initialize(initial, deviceID: device); XCTFail("Reemplazó datos corruptos") }
        catch { XCTAssertEqual(error as? KiduError, .storageCorrupt) }
    }
}
