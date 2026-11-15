// Store+Rules.swift — the writes that span rows, each one transaction: what leaves with what (docs/store.md).
// What a reader gets wrong: moments outlive their take and their recording; only markers go with them.

import Foundation

extension Store {
    /// Saves a song with exactly these files: the song's previous files go.
    public func saveSong(_ song: Song, files: [SongFile]) async throws {
        try await write { tx in
            for old in try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(song.id))])) {
                try tx.delete(SongFile.self, old.id)
            }
            try tx.put(song)
            for var f in files { f.songId = song.id; try tx.put(f) }
        }
    }

    /// Deletes a song and its files; its takes stay, no longer attached to a song.
    public func deleteSong(_ id: String) async throws {
        try await write { tx in
            let mine = Filter("songId", equals: .text(id))
            for f in try tx.list(Query<SongFile>(where: [mine])) { try tx.delete(SongFile.self, f.id) }
            try tx.update(Query<Take>(where: [mine])) { $0.songId = "" }
            try tx.delete(Song.self, id)
        }
    }

    /// Deletes a take with the pins of its recording; its moments stay on their clips.
    public func deleteTake(_ id: String) async throws {
        try await write { tx in
            guard let take = try tx.get(Take.self, id) else { return }
            try tx.delete(Take.self, id)
            if !take.audioPath.isEmpty { try Self.deleteRecordingPins(tx, take.audioPath) }
        }
    }

    /// Deletes a recording: every take that saved it, with its pins. Moments stay.
    public func deleteRecording(_ path: String) async throws {
        try await write { tx in
            for t in try tx.list(Query<Take>(where: [Filter("audioPath", equals: .text(path))])) {
                try tx.delete(Take.self, t.id)
            }
            try Self.deleteRecordingPins(tx, path)
        }
    }

    /// Deletes a moment with the markers it owns.
    public func deleteMoment(_ id: String) async throws {
        try await write { tx in
            for m in try tx.list(Query<Marker>(where: [Filter("momentId", equals: .text(id))])) {
                try tx.delete(Marker.self, m.id)
            }
            try tx.delete(Moment.self, id)
        }
    }

    /// A take's file was re-filed: its takes, moments and markers follow `old` to `new` together.
    public func moveRecording(from old: String, to new: String) async throws {
        try await write { tx in
            try tx.update(Query<Take>(where: [Filter("audioPath", equals: .text(old))])) { $0.audioPath = new }
            let named = Filter("recordingPath", equals: .text(old))
            try tx.update(Query<Moment>(where: [named])) { $0.recordingPath = new }
            try tx.update(Query<Marker>(where: [named])) { $0.recordingPath = new }
        }
    }

    /// The moments cut from a recording, by where they start.
    public func moments(of recordingPath: String) async throws -> [Moment] {
        try await list(Query(where: [Filter("recordingPath", equals: .text(recordingPath))], orderBy: "startSec"))
    }

    private static func deleteRecordingPins(_ tx: Tx, _ path: String) throws {
        let pins = Query<Marker>(where: [Filter("recordingPath", equals: .text(path)), Filter("momentId", equals: "")])
        for m in try tx.list(pins) { try tx.delete(Marker.self, m.id) }
    }
}
