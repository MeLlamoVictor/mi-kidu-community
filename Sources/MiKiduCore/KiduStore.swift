import Foundation
import CSQLite

/// Almacén local. La autenticación del enlace pertenece al host, nunca al correo ni al hash del mundo.
/// Cada escritura bloquea la base, confirma documento + recibo + secuencia juntos y conserva un outbox.
public actor KiduStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func initialize(_ document: KiduDocument, deviceID: UUID) throws {
        try document.validate()
        guard url.isFileURL else { throw KiduError.storageUnavailable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try Database(url: url, create: true)
        try transaction(db) {
            if try db.integer("SELECT count(*) FROM sqlite_master WHERE type='table'") != 0 {
                _ = try read(db)
                throw KiduError.alreadyInitialized
            }
            try db.exec("CREATE TABLE IF NOT EXISTS document (id INTEGER PRIMARY KEY CHECK(id=1), data BLOB NOT NULL)")
            try db.exec("CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, sequence INTEGER NOT NULL CHECK(sequence>=0))")
            try db.exec("CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, device TEXT NOT NULL, sequence INTEGER NOT NULL, data BLOB NOT NULL, pending INTEGER NOT NULL DEFAULT 1, UNIQUE(device,sequence))")
            guard try db.blob("SELECT data FROM document WHERE id=1") == nil else { throw KiduError.alreadyInitialized }
            try db.exec("INSERT INTO document (id,data) VALUES (1,?)", [.blob(try encode(document))])
            try db.exec("INSERT INTO devices (id,sequence) VALUES (?,0)", [.text(deviceID.uuidString)])
            try db.exec("PRAGMA user_version=1")
        }
    }

    public func checkDevice(_ deviceID: UUID) throws {
        let db = try Database(url: url)
        _ = try read(db)
        _ = try nextSequence(db, deviceID: deviceID)
    }

    public func snapshot() throws -> KiduDocument { try read(Database(url: url)) }

    /// Solo el receptor de un emparejamiento autenticado debe invocar este método.
    public func authorizeDevice(_ deviceID: UUID) throws {
        let db = try Database(url: url)
        try transaction(db) {
            _ = try read(db)
            try db.exec("INSERT OR IGNORE INTO devices (id,sequence) VALUES (?,0)", [.text(deviceID.uuidString)])
        }
    }

    /// Para app/widget que comparten base: asigna revisión y secuencia dentro de la misma transacción.
    public func perform(_ action: KiduCareAction, deviceID: UUID) throws -> KiduApplyResult {
        let db = try Database(url: url)
        return try transaction(db) {
            let document = try read(db)
            let sequence = try nextSequence(db, deviceID: deviceID)
            let command = KiduCommand(personKey: document.profile.personKey, deviceID: deviceID,
                                      sequence: sequence, expectedRevision: document.revision, action: action)
            return try commit(command, db: db)
        }
    }

    public func apply(_ command: KiduCommand) throws -> KiduApplyResult {
        let db = try Database(url: url)
        return try transaction(db) { try commit(command, db: db) }
    }

    /// Recibos duraderos para un transporte posterior. No se consideran sincronizados al enviarlos.
    public func pendingReceipts() throws -> [KiduReceipt] {
        let db = try Database(url: url)
        _ = try read(db)
        return try db.blobs("SELECT data FROM receipts WHERE pending=1 ORDER BY rowid").map {
            try decode(KiduReceipt.self, from: $0)
        }
    }

    /// Invocar solo tras recibir la confirmación exacta del destino autenticado.
    public func acknowledge(_ receipt: KiduReceipt) throws {
        let db = try Database(url: url)
        try transaction(db) {
            guard let data = try db.blob("SELECT data FROM receipts WHERE id=?", [.text(receipt.command.id.uuidString)]),
                  try decode(KiduReceipt.self, from: data) == receipt else { throw KiduError.invalidCommand }
            try db.exec("UPDATE receipts SET pending=0 WHERE id=?", [.text(receipt.command.id.uuidString)])
        }
    }

    private func commit(_ command: KiduCommand, db: Database) throws -> KiduApplyResult {
        var document = try read(db)
        guard command.personKey == document.profile.personKey else { throw KiduError.wrongOwner }
        guard command.rulesVersion == 1, command.sequence > 0, command.expectedRevision >= 0 else { throw KiduError.invalidCommand }
        if let data = try db.blob("SELECT data FROM receipts WHERE id=?", [.text(command.id.uuidString)]) {
            let receipt = try decode(KiduReceipt.self, from: data)
            guard receipt.command == command else { throw KiduError.commandIDReused }
            return KiduApplyResult(receipt: receipt, document: document, duplicate: true)
        }
        let expected = try nextSequence(db, deviceID: command.deviceID)
        guard command.sequence == expected else { throw KiduError.sequenceGap(expected: expected) }
        guard command.expectedRevision == document.revision else { throw KiduError.revisionConflict(current: document.revision) }
        try document.apply(command.action)
        let receipt = KiduReceipt(command: command, committedRevision: document.revision, acceptedAt: Date(), awardedPoints: 0)
        try db.exec("UPDATE document SET data=? WHERE id=1", [.blob(try encode(document))])
        try db.exec("UPDATE devices SET sequence=? WHERE id=?", [.integer(command.sequence), .text(command.deviceID.uuidString)])
        try db.exec("INSERT INTO receipts (id,device,sequence,data) VALUES (?,?,?,?)", [
            .text(command.id.uuidString), .text(command.deviceID.uuidString), .integer(command.sequence), .blob(try encode(receipt))
        ])
        return KiduApplyResult(receipt: receipt, document: document, duplicate: false)
    }

    private func nextSequence(_ db: Database, deviceID: UUID) throws -> Int64 {
        guard let current = try db.integer("SELECT sequence FROM devices WHERE id=?", [.text(deviceID.uuidString)]) else {
            throw KiduError.unauthorizedDevice
        }
        guard current < Int64.max else { throw KiduError.invalidCommand }
        return current + 1
    }

    private func read(_ db: Database) throws -> KiduDocument {
        guard try db.integer("PRAGMA user_version") == 1 else { throw KiduError.storageCorrupt }
        guard let data = try db.blob("SELECT data FROM document WHERE id=1") else { throw KiduError.notInitialized }
        let document = try decode(KiduDocument.self, from: data)
        try document.validate()
        return document
    }

    private func transaction<T>(_ db: Database, _ body: () throws -> T) throws -> T {
        try db.exec("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try db.exec("COMMIT")
            return value
        } catch {
            // La conexión se cierra después: SQLite revierte incluso si ROLLBACK falla.
            db.rollback()
            throw error
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw KiduError.storageCorrupt }
    }
}

private enum SQLValue { case text(String), blob(Data), integer(Int64) }

// SQLite abre con FULLMUTEX. La conexión no escapa de una operación síncrona
// del actor; ninguna transacción suspende ni comparte su handle con otro actor.
private final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, create: Bool = false) throws {
        guard url.isFileURL else { throw KiduError.storageUnavailable }
        if !create && !FileManager.default.fileExists(atPath: url.path) { throw KiduError.notInitialized }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            sqlite3_close(handle); handle = nil
            throw KiduError.storageUnavailable
        }
        sqlite3_busy_timeout(handle, 2_000)
        do {
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA synchronous=FULL")
        } catch {
            sqlite3_close(handle); handle = nil
            throw error
        }
    }
    deinit { sqlite3_close(handle) }


    func rollback() { _ = sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) }

    func exec(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { status = sqlite3_step(statement) }
        try check(status, accepting: SQLITE_DONE)
    }

    func blob(_ sql: String, _ values: [SQLValue] = []) throws -> Data? { try blobs(sql, values).first }
    func blobs(_ sql: String, _ values: [SQLValue] = []) throws -> [Data] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [Data] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            if let bytes = sqlite3_column_blob(statement, 0) { result.append(Data(bytes: bytes, count: count)) }
            else { result.append(Data()) }
            status = sqlite3_step(statement)
        }
        try check(status, accepting: SQLITE_DONE)
        return result
    }

    func integer(_ sql: String, _ values: [SQLValue] = []) throws -> Int64? {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_ROW { return sqlite3_column_int64(statement, 0) }
        try check(status, accepting: SQLITE_DONE)
        return nil
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        guard let statement else { throw KiduError.storageUnavailable }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case .integer(let n): status = sqlite3_bind_int64(statement, index, n)
                case .text(let text): status = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
                case .blob(let data): status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
                }
                try check(status)
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }

    private func check(_ status: Int32, accepting: Int32 = SQLITE_OK) throws {
        guard status != accepting else { return }
        switch status {
        case SQLITE_BUSY, SQLITE_LOCKED: throw KiduError.busy
        case SQLITE_CORRUPT, SQLITE_NOTADB: throw KiduError.storageCorrupt
        default: throw KiduError.storageUnavailable
        }
    }
}
