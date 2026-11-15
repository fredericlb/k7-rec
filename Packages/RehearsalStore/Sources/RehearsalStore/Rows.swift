// Rows.swift — the one table of JSON documents and the statements over it, run inside a GRDB database access.
// What a reader gets wrong: index expressions are spelt exactly as the queries spell them, or SQLite skips them.

import Foundation
import GRDB

extension Scalar: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        switch self {
        case .text(let s): s.databaseValue
        case .number(let n): n.databaseValue
        case .flag(let b): (b ? 1 : 0).databaseValue
        }
    }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Scalar? { nil }
}

enum Rows {
    static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS docs (
              coll TEXT NOT NULL, id TEXT NOT NULL, fields TEXT NOT NULL, PRIMARY KEY (coll, id))
            """)
        for field in indexedFields {
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS docs_\(field) ON docs (coll, json_extract(fields, '$.\(field)'))")
        }
    }

    static func encode<D: Document>(_ d: D) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(d), as: UTF8.self)
    }

    static func put<D: Document>(_ db: Database, _ d: D) throws {
        try db.execute(
            sql: "INSERT INTO docs (coll, id, fields) VALUES (?, ?, ?) ON CONFLICT (coll, id) DO UPDATE SET fields = excluded.fields",
            arguments: [D.collection.rawValue, d.id, try encode(d)])
    }

    static func get<D: Document>(_ db: Database, _ type: D.Type, _ id: String) throws -> D? {
        guard let text = try String.fetchOne(
            db, sql: "SELECT fields FROM docs WHERE coll = ? AND id = ?", arguments: [D.collection.rawValue, id])
        else { return nil }
        return try JSONDecoder().decode(D.self, from: Data(text.utf8))
    }

    static func list<D: Document>(_ db: Database, _ q: Query<D>) throws -> [D] {
        let (sql, args) = try q.sql()
        let dec = JSONDecoder()
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let text: String = row["fields"]
            return try dec.decode(D.self, from: Data(text.utf8))
        }
    }

    static func delete<D: Document>(_ db: Database, _ type: D.Type, _ id: String) throws {
        try db.execute(sql: "DELETE FROM docs WHERE coll = ? AND id = ?", arguments: [D.collection.rawValue, id])
    }
}
