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

    @Test func aSidecarMadeInTheAppReadsBackAsASongWithNoFile() throws {
        let yaml = try SongFolder.sidecar(uuid: "ab12", title: "Yes: 1969", artist: "#1 Band")
        let dir = try folder(yaml, files: [])

        let (song, files) = try SongFolder.read(dir)

        #expect((song.id, song.title, song.artist) == ("ab12", "Yes: 1969", "#1 Band"))
        #expect(files.isEmpty)
    }

    @Test func theSidecarsCapoIsReadAndKeptOnTheNeck() throws {
        #expect(try SongFolder.read(folder("title: A\ncapo: 3\n", files: [])).song.capo == 3)
        #expect(try SongFolder.read(folder("title: A\ncapo: 40\n", files: [])).song.capo == 12)
        #expect(try SongFolder.read(folder("title: A\ncapo: two\n", files: [])).song.capo == 0)
    }

    @Test func folderWithoutSidecarFallsBackToItsName() throws {
        let dir = try folder(nil, files: ["chords.txt"])
        let (song, files) = try SongFolder.read(dir)
        #expect(song.title == "My Song" && song.artist == "" && song.uuid == "" && song.id == SongFolder.derivedID(source: dir))
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
            let (song, files) = try SongFolder.read(dir, destination: SongFolder.destinationName(for: dir))
            try await s.saveSong(song, files: files)
        }
        #expect(try await s.list(Query<Song>()).count == 1)
    }

    @Test func twoUuidLessFoldersWithTheSameNameAreTwoSongs() async throws {
        let a = try folder(nil, files: ["lyrics.txt"]), b = try folder(nil, files: ["lyrics.txt"])
        #expect(a.lastPathComponent == b.lastPathComponent)
        let da = SongFolder.destinationName(for: a), db = SongFolder.destinationName(for: b)
        #expect(da != db)
        let s = try Store()
        for (dir, dest) in [(a, da), (b, db)] {
            let (song, files) = try SongFolder.read(dir, destination: dest)
            try await s.saveSong(song, files: files)
        }
        let songs = try await s.list(Query<Song>()).count, filesCount = try await s.list(Query<SongFile>()).count
        #expect(songs == 2 && filesCount == 2)
    }
}
