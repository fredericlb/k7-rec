// The song folder's names, per packages/mediatek/docs/songbook.md.

import Testing

@testable import RehearsalText

@Suite struct SongFolderLayoutTests {
    @Test func namesMatchTheSongbook() {
        #expect(SongFolderLayout.textFiles == ["lyrics.txt", "tabs.txt", "chords.txt"])
        #expect(SongFolderLayout.sidecar == "song.yaml")
        #expect(SongFolderLayout.sheetPath("score.pdf") == "sheets/score.pdf")
    }

    @Test func masterIsOriginalWithAnyExtension() {
        #expect(SongFolderLayout.isMaster("original.flac"))
        #expect(SongFolderLayout.isMaster("original.m4a"))
        #expect(!SongFolderLayout.isMaster("original."))
        #expect(!SongFolderLayout.isMaster("lyrics.txt"))
    }

    @Test func aSongIsInTheSongbookWhenItCarriesATextOrASheet() {
        #expect(SongFolderLayout.carriesSongbook(entries: ["original.flac", "tabs.txt"]))
        #expect(SongFolderLayout.carriesSongbook(entries: ["sheets/score.pdf"]))
        #expect(!SongFolderLayout.carriesSongbook(entries: ["original.flac", "song.yaml"]))
    }
}
