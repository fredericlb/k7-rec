// Store.swift — the rehearsal store: an actor over one GRDB queue (one writer), WAL, synchronous NORMAL.
// What a reader gets wrong: `write` is one transaction, so a closure inside it never awaits (docs/store.md).

import Foundation
import GRDB

/// What a `write` closure sees: the rows of the transaction it runs in.
public struct Tx {
    let db: Database
    public func put<D: Document>(_ d: D) throws { try Rows.put(db, d) }
    public func get<D: Document>(_ type: D.Type, _ id: String) throws -> D? { try Rows.get(db, type, id) }
    public func list<D: Document>(_ q: Query<D>) throws -> [D] { try Rows.list(db, q) }
    public func delete<D: Document>(_ type: D.Type, _ id: String) throws { try Rows.delete(db, type, id) }
    /// Applies `change` to every row the query lists, whole rows, and stores them again.
    public func update<D: Document>(_ q: Query<D>, _ change: (inout D) -> Void) throws {
        var whole = q
        whole.fields = nil
        for var d in try list(whole) { change(&d); try put(d) }
    }
}

public actor Store {
    private let queue: DatabaseQueue

    /// Opens (creating) the database file at `url`.
    public init(url: URL) throws {
        queue = try DatabaseQueue(path: url.path, configuration: Self.configuration())
        try queue.write(Rows.createSchema)
    }

    /// A store that lives in memory, for tests and previews.
    public init() throws {
        queue = try DatabaseQueue(configuration: Self.configuration())
        try queue.write(Rows.createSchema)
    }

    private static func configuration() -> Configuration {
        var c = Configuration()
        c.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        return c
    }

    public func get<D: Document>(_ type: D.Type, _ id: String) async throws -> D? {
        try await queue.read { try Rows.get($0, type, id) }
    }

    public func list<D: Document>(_ q: Query<D> = Query()) async throws -> [D] {
        try await queue.read { try Rows.list($0, q) }
    }

    public func put<D: Document>(_ d: D) async throws {
        try await queue.write { try Rows.put($0, d) }
    }

    public func put<D: Document>(_ many: [D]) async throws {
        try await queue.write { db in for d in many { try Rows.put(db, d) } }
    }

    public func delete<D: Document>(_ type: D.Type, _ id: String) async throws {
        try await queue.write { try Rows.delete($0, type, id) }
    }

    /// Runs `body` as one transaction: it lands whole or not at all.
    public func write<T: Sendable>(_ body: @Sendable @escaping (Tx) throws -> T) async throws -> T {
        try await queue.write { try body(Tx(db: $0)) }
    }

    /// The listing again each time it changes, first at once; ends with the error that stopped it.
    public nonisolated func observe<D: Document>(_ q: Query<D> = Query()) -> AsyncThrowingStream<[D], Error> {
        let values = ValueObservation.tracking { try Rows.list($0, q) }.removeDuplicates().values(in: queue)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do { for try await v in values { continuation.yield(v) }; continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
