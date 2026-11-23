// Writes to a song's folder and its rows: texts, sheets, title, artist and tags, the file first and the rows in one transaction.
// What a reader gets wrong: an emptied text removes its file and row, so the Info of a song can shrink to nothing.
import Foundation
import RehearsalStore

extension StoreSongLibrary {
    private func folderName(_ song: Song) -> String { song.folder.isEmpty ? SongImporter.safe(song.title) : song.folder }

    private func fileKind(_ kind: TextKind) -> SongFileKind {
        switch kind {
        case .lyrics: .lyrics
        case .chords: .chords
        case .tabs: .tabs
        }
    }

    func createSong(title: String, artist: String) async -> Result<String, SongError> {
        let uuid = UUID().uuidString.lowercased()
        let name = "\(SongImporter.safe(title)) \(uuid.prefix(8))"
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let row = RehearsalStore.Song(id: uuid, uuid: uuid, title: title, artist: artist, folder: name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SongFolder.sidecar(uuid: uuid, title: title, artist: artist).write(
                to: folder.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
            try await store.write { tx in try tx.put(row) }
            await refresh()
            return .success(uuid)
        } catch { return .failure(SongError(message: error.localizedDescription)) }
    }

    func saveText(_ kind: TextKind, _ text: String, for song: Song) async -> String? {
        let folder = folderName(song), fm = FileManager.default
        let file = root.appendingPathComponent(folder).appendingPathComponent(kind.file)
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let (songID, wanted, rel) = (song.id, fileKind(kind), "\(folder)/\(kind.file)")
        do {
            if empty { try? fm.removeItem(at: file) } else {
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
            try await store.write { tx in
                let rows = try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(songID))]))
                let position = rows.first { $0.kind == wanted }?.position ?? (rows.map(\.position).max() ?? -1) + 1
                for r in rows where r.kind == wanted { try tx.delete(SongFile.self, r.id) }
                if !empty {
                    try tx.put(SongFile(id: "\(songID):\(kind.file)", songId: songID, kind: wanted, path: rel, name: kind.file, position: position))
                }
            }
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    func addSheet(from url: URL, to song: Song) async -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = folderName(song), fm = FileManager.default
        let dir = root.appendingPathComponent(folder).appendingPathComponent("sheets", isDirectory: true)
        let name = uniqueName(url.lastPathComponent, in: dir)
        let songID = song.id
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dir.appendingPathComponent(name))
            try await store.write { tx in
                let rows = try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(songID))]))
                try tx.put(SongFile(id: "\(songID):sheets/\(name)", songId: songID, kind: .sheet, path: "\(folder)/sheets/\(name)",
                                    name: name, position: (rows.map(\.position).max() ?? -1) + 1))
            }
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    func removeSheet(_ sheet: SongSheet, from song: Song) async -> String? {
        let id = sheet.id
        try? FileManager.default.removeItem(at: sheet.url)
        do {
            try await store.delete(SongFile.self, id)
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    func setInfo(title: String, artist: String, tags: [String], for song: Song) async -> String? {
        let songID = song.id
        do {
            try await store.write { tx in
                guard var row = try tx.get(RehearsalStore.Song.self, songID) else { return }
                (row.title, row.artist, row.tags) = (title, artist, tags)
                try tx.put(row)
            }
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    func setFavorite(_ on: Bool, for song: Song) async -> String? {
        await change(song) { $0.favorite = on }
    }

    func setCapo(_ fret: Int, for song: Song) async -> String? {
        await change(song) { $0.capo = min(max(fret, 0), 12) }
    }

    /// Changes the song's row in one transaction, then reads the store again.
    private func change(_ song: Song, _ edit: @escaping @Sendable (inout RehearsalStore.Song) -> Void) async -> String? {
        let songID = song.id
        do {
            try await store.write { tx in
                guard var row = try tx.get(RehearsalStore.Song.self, songID) else { return }
                edit(&row)
                try tx.put(row)
            }
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    private func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = name, n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = base + " \(n)" + (ext.isEmpty ? "" : "." + ext)
            n += 1
        }
        return candidate
    }
}
