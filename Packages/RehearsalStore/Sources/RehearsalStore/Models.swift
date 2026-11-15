// Models.swift — the rows: Codable structs whose missing fields decode as their type's zero value.
// What a reader gets wrong: every `init(from:)` goes through `zero`, so a field added later needs no migration.

import Foundation

extension KeyedDecodingContainer {
    /// The field, or `fallback` when the row never set it (or holds null).
    func zero<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

/// What a row of the store is: a collection and an id.
public protocol Document: Codable, Sendable, Identifiable, Equatable where ID == String {
    static var collection: DocCollection { get }
    var id: String { get }
}

/// A song of the repertoire; `uuid` is the song folder's sidecar uuid, empty for a song made here.
public struct Song: Document {
    public static let collection = DocCollection.songs
    public var id: String
    public var uuid: String
    public var title: String
    public var artist: String
    public var tags: [String]
    public var createdAt: Double

    public init(id: String = newID(), uuid: String = "", title: String = "", artist: String = "",
                tags: [String] = [], createdAt: Double = Date().timeIntervalSince1970) {
        (self.id, self.uuid, self.title, self.artist, self.tags, self.createdAt) =
            (id, uuid, title, artist, tags, createdAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.zero(.id, ""), uuid: try c.zero(.uuid, ""), title: try c.zero(.title, ""),
                  artist: try c.zero(.artist, ""), tags: try c.zero(.tags, []), createdAt: try c.zero(.createdAt, 0))
    }
}

/// What a song file holds; a row that never set it reads as `lyrics`.
public enum SongFileKind: String, Codable, Sendable, CaseIterable {
    case lyrics, chords, tabs, sheet, audio
}

/// One file of a song; `path` is relative to the app's songs folder.
public struct SongFile: Document {
    public static let collection = DocCollection.songFiles
    public var id: String
    public var songId: String
    public var kind: SongFileKind
    public var path: String
    public var name: String
    public var mime: String
    public var position: Int

    public init(id: String = newID(), songId: String = "", kind: SongFileKind = .lyrics, path: String = "",
                name: String = "", mime: String = "", position: Int = 0) {
        (self.id, self.songId, self.kind, self.path, self.name, self.mime, self.position) =
            (id, songId, kind, path, name, mime, position)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.zero(.id, ""), songId: try c.zero(.songId, ""),
                  kind: (try? c.decodeIfPresent(SongFileKind.self, forKey: .kind)) ?? .lyrics,
                  path: try c.zero(.path, ""), name: try c.zero(.name, ""), mime: try c.zero(.mime, ""),
                  position: try c.zero(.position, 0))
    }
}

/// A recording made in the app (the web's "session"); `audioPath` names the file under the recordings folder.
public struct Take: Document {
    public static let collection = DocCollection.takes
    public var id: String
    public var songId: String
    public var title: String
    public var createdAt: Double
    public var duration: Double
    public var envelope: [Float]
    public var gain: Double
    public var audioPath: String

    public init(id: String = newID(), songId: String = "", title: String = "",
                createdAt: Double = Date().timeIntervalSince1970, duration: Double = 0,
                envelope: [Float] = [], gain: Double = 0, audioPath: String = "") {
        (self.id, self.songId, self.title, self.createdAt) = (id, songId, title, createdAt)
        (self.duration, self.envelope, self.gain, self.audioPath) = (duration, envelope, gain, audioPath)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.zero(.id, ""), songId: try c.zero(.songId, ""), title: try c.zero(.title, ""),
                  createdAt: try c.zero(.createdAt, 0), duration: try c.zero(.duration, 0),
                  envelope: try c.zero(.envelope, []), gain: try c.zero(.gain, 0), audioPath: try c.zero(.audioPath, ""))
    }
}

/// A span of a recording, named by the recording's path (`moments.md` of the web store).
public struct Moment: Document {
    public static let collection = DocCollection.moments
    public var id: String
    public var recordingPath: String
    public var recordedAt: Double
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public var tags: [String]
    public var createdAt: Double
    public var validated: Bool
    public var clipPath: String
    public var envelope: [Float]

    public init(id: String = newID(), recordingPath: String = "", recordedAt: Double = 0, startSec: Double = 0,
                endSec: Double = 0, text: String = "", tags: [String] = [],
                createdAt: Double = Date().timeIntervalSince1970, validated: Bool = false,
                clipPath: String = "", envelope: [Float] = []) {
        (self.id, self.recordingPath, self.recordedAt) = (id, recordingPath, recordedAt)
        (self.startSec, self.endSec, self.text, self.tags) = (startSec, endSec, text, tags)
        (self.createdAt, self.validated, self.clipPath, self.envelope) = (createdAt, validated, clipPath, envelope)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.zero(.id, ""), recordingPath: try c.zero(.recordingPath, ""),
                  recordedAt: try c.zero(.recordedAt, 0), startSec: try c.zero(.startSec, 0),
                  endSec: try c.zero(.endSec, 0), text: try c.zero(.text, ""), tags: try c.zero(.tags, []),
                  createdAt: try c.zero(.createdAt, 0), validated: try c.zero(.validated, false),
                  clipPath: try c.zero(.clipPath, ""), envelope: try c.zero(.envelope, []))
    }
}

/// A pin on a recording's timeline; `momentId` is set when the moment owns it, empty for a recording's own.
public struct Marker: Document {
    public static let collection = DocCollection.markers
    public var id: String
    public var recordingPath: String
    public var momentId: String
    public var atSec: Double
    public var comment: String
    public var createdAt: Double

    public init(id: String = newID(), recordingPath: String = "", momentId: String = "", atSec: Double = 0,
                comment: String = "", createdAt: Double = Date().timeIntervalSince1970) {
        (self.id, self.recordingPath, self.momentId) = (id, recordingPath, momentId)
        (self.atSec, self.comment, self.createdAt) = (atSec, comment, createdAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.zero(.id, ""), recordingPath: try c.zero(.recordingPath, ""),
                  momentId: try c.zero(.momentId, ""), atSec: try c.zero(.atSec, 0),
                  comment: try c.zero(.comment, ""), createdAt: try c.zero(.createdAt, 0))
    }
}

/// A random 15-character id.
public func newID() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<15).map { _ in alphabet.randomElement()! })
}
