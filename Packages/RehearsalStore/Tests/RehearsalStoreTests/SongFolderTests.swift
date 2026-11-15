import Foundation
import Testing
@testable import RehearsalStore

@Suite struct SongFolderTests {
    private func folder(_ yaml: String?, files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("song-\(newID())/My Song")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sheets"), withIntermediateDirectories: true)
        for f in files { try Data("x".utf8).write(to: dir.appendingPathComponent(f)) }
        if let yaml { try yaml.write(to: dir.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8) }
        return dir
    }

    @Test func readsSidecarAndFiles() throws {
        let yaml = """
        uuid: 1234-abcd
        title: Blackbird
        artist: The Beatles
        tags: [folk, "60s"]
        source: somewhere
        songbook:
          sheets:
            - {id: b, file: sheets/b.pdf, name: Second, mime: application/pdf}
            - {id: a, file: sheets/a.png, name: First, mime: image/png}
            - {id: gone, file: sheets/gone.pdf, name: Gone}
        """
        let dir = try folder(yaml, files: ["original.flac", "lyrics.txt", "tabs.txt", "sheets/a.png", "sheets/b.pdf", "sheets/c.pdf"])
        let (song, files) = try SongFolder.read(dir, destination: "Blackbird")
        #expect(song.id == "1234-abcd" && song.uuid == "1234-abcd")
        #expect(song.title == "Blackbird" && song.artist == "The Beatles" && song.tags == ["folk", "60s"])
        #expect(files.map(\.kind) == [.audio, .lyrics, .tabs, .sheet, .sheet, .sheet])
        #expect(files.filter { $0.kind == .sheet }.map(\.name) == ["Second", "First", "c.pdf"])
        #expect(files[1].path == "Blackbird/lyrics.txt" && files.map(\.position) == Array(0..<6))
        #expect(files.allSatisfy { $0.songId == song.id })
    }

    @Test func folderWithoutSidecarFallsBackToItsName() throws {
        let (song, files) = try SongFolder.read(try folder(nil, files: ["chords.txt"]))
        #expect(song.title == "My Song" && song.artist == "" && song.uuid == "" && song.id == SongFolder.derivedID("My Song"))
        #expect(files.map(\.kind) == [.chords] && files[0].path == "My Song/chords.txt")
    }

    @Test func importedSongRoundTripsThroughTheStore() async throws {
        let (song, files) = try SongFolder.read(try folder("uuid: u1\ntitle: T", files: ["lyrics.txt"]))
        let s = try Store()
        try await s.saveSong(song, files: files)
        try await s.saveSong(song, files: files)
        #expect(try await s.list(Query<SongFile>()).count == 1)
        #expect(try await s.list(Query<Song>(where: [Filter("uuid", equals: "u1")])).count == 1)
    }

    @Test func uuidLessFolderImportedTwiceIsOneSong() async throws {
        let dir = try folder(nil, files: ["lyrics.txt"])
        let s = try Store()
        for _ in 0..<2 {
            let (song, files) = try SongFolder.read(dir, destination: "Songs/A")
            try await s.saveSong(song, files: files)
        }
        #expect(try await s.list(Query<Song>()).count == 1)
        #expect(SongFolder.derivedID("Songs/A") != SongFolder.derivedID("Songs/B"))
    }
}
