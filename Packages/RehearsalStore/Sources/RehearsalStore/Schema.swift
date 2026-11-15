// Schema.swift — the collections the store holds, the fields of each, and the ones rows are looked up by.
// What a reader gets wrong: a field is added here AND to its model; a test fails when the two differ.

/// A collection of the store: its name is the `coll` column.
public enum DocCollection: String, CaseIterable, Sendable {
    case songs = "Songs"
    case songFiles = "SongFiles"
    case takes = "Takes"
    case moments = "Moments"
    case markers = "Markers"

    /// The fields of a row, which a filter or a partial listing may name.
    public var fields: [String] {
        switch self {
        case .songs: ["id", "uuid", "title", "artist", "tags", "createdAt", "source", "storeId"]
        case .songFiles: ["id", "songId", "kind", "path", "name", "mime", "position"]
        case .takes: ["id", "songId", "title", "createdAt", "duration", "envelope", "gain", "audioPath"]
        case .moments:
            ["id", "recordingPath", "recordedAt", "startSec", "endSec", "text", "tags", "createdAt",
             "validated", "clipPath", "envelope"]
        case .markers: ["id", "recordingPath", "momentId", "atSec", "comment", "createdAt"]
        }
    }
}

/// The fields rows are looked up by, each with an expression index on `(coll, json_extract(...))`.
let indexedFields: [String] = ["songId", "recordingPath", "audioPath", "momentId", "uuid"]
