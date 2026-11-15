// Query.swift — a listing as a value: filters (IN-lists per field), the fields to read, an order, a limit.
// What a reader gets wrong: a field name is checked against the schema, then spelt into the SQL, never bound.

import Foundation

/// A value a filter matches a field against.
public enum Scalar: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByFloatLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case text(String), number(Double), flag(Bool)
    public init(stringLiteral v: String) { self = .text(v) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(booleanLiteral v: Bool) { self = .flag(v) }
}

public struct Filter: Sendable {
    public var field: String
    public var values: [Scalar]
    public init(_ field: String, in values: [Scalar]) { (self.field, self.values) = (field, values) }
    public init(_ field: String, equals value: Scalar) { self.init(field, in: [value]) }
}

public struct Query<D: Document>: Sendable {
    public var filters: [Filter] = []
    public var fields: [String]?
    public var orderBy: String?
    public var descending = false
    public var limit: Int?

    public init(where filters: [Filter] = [], fields: [String]? = nil, orderBy: String? = nil,
                descending: Bool = false, limit: Int? = nil) {
        (self.filters, self.fields, self.orderBy, self.descending, self.limit) =
            (filters, fields, orderBy, descending, limit)
    }
}

public enum StoreError: Error, Equatable {
    case unknownField(collection: String, field: String)
}

extension Query {
    /// The SQL of the listing and its arguments, once every field name is known to the schema.
    func sql() throws -> (String, [Scalar]) {
        let known = Set(D.collection.fields)
        func check(_ f: String) throws -> String {
            guard known.contains(f) else { throw StoreError.unknownField(collection: D.collection.rawValue, field: f) }
            return f
        }
        var args: [Scalar] = [.text(D.collection.rawValue)]
        var select = "id, fields"
        if let fields {
            let parts = try fields.map { "'\(try check($0))', fields -> '$.\($0)'" }
            select = "id, json_object('id', id" + parts.map { ", " + $0 }.joined() + ") AS fields"
        }
        var sql = "SELECT \(select) FROM docs WHERE coll = ?"
        for f in filters {
            let field = try check(f.field)
            if f.values.isEmpty { sql += " AND 0"; continue }
            sql += " AND json_extract(fields, '$.\(field)') IN (" + f.values.map { _ in "?" }.joined(separator: ",") + ")"
            args += f.values
        }
        sql += " ORDER BY " + (try orderBy.map { "json_extract(fields, '$.\(try check($0))')" } ?? "rowid")
        sql += descending ? " DESC" : ""
        if let limit { sql += " LIMIT \(max(0, limit))" }
        return (sql, args)
    }
}
