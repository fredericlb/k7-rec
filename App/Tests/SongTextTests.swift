// The song screen's pure logic: the sung line, transposition kept per song, tab grids, LRC, diagrams.
import RehearsalText
import XCTest
@testable import K7Rec

@MainActor
final class SongTextTests: XCTestCase {
    private let timed = "{{00:04}} First\nchorus:\n{{00:09.50}} Second\n\nno time"

    func testTheSungLineIsTheLastOneWhoseTimeHasCome() {
        XCTAssertNil(SongText.activeLine(timed, at: 3))
        XCTAssertEqual(SongText.activeLine(timed, at: 4), 0)
        XCTAssertEqual(SongText.activeLine(timed, at: 9.4), 0)
        XCTAssertEqual(SongText.activeLine(timed, at: 12), 2)
    }

    func testATapSeeksALeadBeforeTheLineAndNeverBeforeZero() {
        XCTAssertEqual(SongText.seekTime(line: 2, in: timed, lead: 1), 8.5)
        XCTAssertEqual(SongText.seekTime(line: 0, in: timed, lead: 6), 0)
        XCTAssertNil(SongText.seekTime(line: 4, in: timed, lead: 1))
    }

    func testChordLinesAndInlineChordsMoveButWordsDoNot() {
        let lines = SongText.displayLines("Am   F\nHello [G]world", semitones: 2)
        XCTAssertEqual(lines[0], .chords(text: "Bm   G"))
        XCTAssertEqual(lines[1], .lyrics(segments: [Segment(chord: nil, text: "Hello "), Segment(chord: "A", text: "world")]))
    }

    func testDiagramChordsAreTransposedAndListedOnce() {
        let chords = SongText.diagramChords(chords: "C G\nC G", lyrics: "la [Am]la [C]", semitones: 2)
        XCTAssertEqual(chords, ["D", "A", "Bm"])
    }

    func testTabHeaderFoldsOnlyWordsBeforeTheFirstSystem() {
        let parts = SongText.tabParts(Tablature.parse("Tuning: EADGBE\n\ne|--0--2--|\nB|--1-----|\n\nOutro"))
        XCTAssertEqual(parts.header.first, .text("Tuning: EADGBE"))
        guard case .system = parts.body.first else { return XCTFail("the body starts at the system") }
        XCTAssertTrue(SongText.tabParts(Tablature.parse("\ne|--0--|\nB|--1--|")).header.isEmpty)
    }

    func testTabSystemIsSpokenStringByString() {
        guard case .system(let system) = Tablature.parse("e|--0--2h3--|\nB|--1-------|").first else { return XCTFail("no system") }
        XCTAssertEqual(SongText.tabSpoken(system), "e 0 2 h 3, B 1")
    }

    func testLRCTimesTheLyricsAndAnEmptyOneFails() throws {
        let result = SongText.timedLyrics("First line\nSecond line", lrc: "[00:04.00]First line\n[00:09.00]Second line")
        let timed = try result.get()
        XCTAssertEqual(timed.placed, 2)
        XCTAssertTrue(timed.text.hasPrefix("{{00:04.00}} First line"))
        guard case .failure(let e) = SongText.timedLyrics("a", lrc: "nothing here") else { return XCTFail("expected a failure") }
        XCTAssertEqual(e, .noTimedLines)
    }

    func testChordsTakeTheTimesOfTheLyricsLineTheyMatch() {
        let lyrics = "{{00:05.00}} Hello world"
        XCTAssertEqual(SongText.timedChords(chords: "Am\nHello world", lyrics: lyrics), "Am\n{{00:05.00}} Hello world")
        XCTAssertEqual(SongText.timedChords(chords: "Am\n{{00:01.00}} Hello world", lyrics: lyrics), "Am\n{{00:05.00}} Hello world")
    }

    func testChordsStayAsTypedWhenTheLyricsHaveNoTimeOrNothingMatches() {
        XCTAssertNil(SongText.timedChords(chords: "Am\nHello world", lyrics: "Hello world"))
        XCTAssertNil(SongText.timedChords(chords: "Am\nSomething else", lyrics: "{{00:05.00}} Hello world"))
        XCTAssertNil(SongText.timedChords(chords: "  \n", lyrics: "{{00:05.00}} Hello world"))
    }

    func testThePianoReadsTheChordsInTheSoundingKeyAndTheGuitarUnderTheCapo() {
        let suite = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
        let prefs = SongPrefs(defaults: suite)
        let song = Song(id: "a", title: "A", artist: "", capo: 2)
        prefs.setTranspose(1, of: "a")
        XCTAssertEqual(prefs.instrument, .guitar)
        XCTAssertEqual(prefs.shownSemitones(of: song), 1)
        prefs.instrument = .piano
        XCTAssertEqual(prefs.shownSemitones(of: song), 3)
        XCTAssertEqual(SongText.diagramChords(chords: "Em7 G D", lyrics: "", semitones: prefs.shownSemitones(of: Song(id: "b", title: "B", artist: "", capo: 2))), ["F#m7", "A", "E"])
        XCTAssertEqual(SongPrefs(defaults: suite).instrument, .piano, "the instrument is kept")
    }

    func testTranspositionIsKeptPerSongAndWrapsInsideAnOctave() {
        let suite = UserDefaults(suiteName: "prefs-\(UUID().uuidString)")!
        let prefs = SongPrefs(defaults: suite)
        prefs.setTranspose(3, of: "a")
        prefs.setTranspose(-2, of: "b")
        XCTAssertEqual(prefs.transpose(of: "c"), 0)
        let again = SongPrefs(defaults: suite)
        XCTAssertEqual(again.transpose(of: "a"), 3)
        XCTAssertEqual(again.transpose(of: "b"), -2)
        again.setTranspose(7, of: "a")
        XCTAssertEqual(again.transpose(of: "a"), -5)
        again.setTranspose(12, of: "a")
        XCTAssertEqual(again.transpose(of: "a"), 0)
    }

    func testTheLyricsLeadDefaultsToOneSecondAndIsKept() {
        let suite = UserDefaults(suiteName: "lead-\(UUID().uuidString)")!
        XCTAssertEqual(SongPrefs(defaults: suite).lyricsLead, 1)
        SongPrefs(defaults: suite).lyricsLead = 2.5
        XCTAssertEqual(SongPrefs(defaults: suite).lyricsLead, 2.5)
    }

    func testDiagramLookupFindsKnownChordsAndAnswersNilForUnknownOnes() throws {
        let db = ChordDiagrams.shared
        XCTAssertEqual(db.fingering(for: "C")?.frets, [-1, 3, 2, 0, 1, 0])
        XCTAssertNotNil(db.fingering(for: "Db"), "an enharmonic root folds onto its key")
        XCTAssertNotNil(db.fingering(for: "C#m7"))
        XCTAssertNotNil(db.fingering(for: "G/B"))
        XCTAssertNil(db.fingering(for: "Bad"))
        XCTAssertNil(db.fingering(for: "N.C."))
        XCTAssertNil(ChordDiagrams(data: Data()).fingering(for: "C"))
    }

    func testTheParsedLinesAreKeptUntilTheTextOrTheTranspositionChanges() {
        let memo = ParsedMemo()
        let parse: (String, Int) -> ParsedMemo.Value = { (SongText.displayLines($0, semitones: $1), []) }
        _ = memo.get("Am F", 0, parse: parse)
        _ = memo.get("Am F", 0, parse: parse)
        XCTAssertEqual(memo.parses, 1)
        _ = memo.get("Am F", 2, parse: parse)
        _ = memo.get("Am G", 2, parse: parse)
        XCTAssertEqual(memo.parses, 3)
    }

    func testAChordLineIsCutIntoChordsAndWhatLiesBetweenWithNothingLost() {
        let line = "Am   F/C  (x2) G"
        let runs = SongText.chordRuns(line)
        XCTAssertEqual(runs.map(\.text).joined(), line)
        XCTAssertEqual(runs.filter(\.chord).map(\.text), ["Am", "F/C", "G"])
        XCTAssertEqual(runs.first { !$0.chord }?.text, "   ")
        XCTAssertEqual(runs[3].text, "  (x2) ", "a word that is no chord joins the gap around it")
    }

    func testTabsWithContentComeFirstThenTheEmptyOnes() {
        let song = Song(id: "s", title: "S", artist: "", hasChords: false, hasLyrics: true, hasTab: true, hasSheets: false)
        XCTAssertEqual(SongTabs.ordered(song), [.lyrics, .tab, .chords, .sheets])
        XCTAssertEqual(SongTabs.opening(song), .lyrics)
    }

    func testSystemsWithOnlyBlankLinesBetweenAreGroupedAndTextKeepsThemApart() {
        let tab = [
            "e|--0--|", "B|--1--|", "", "e|--2--|", "B|--3--|", "", "Then the verse", "e|--4--|", "B|--5--|", "",
        ].joined(separator: "\n")
        let blocks = SongText.tabBlocks(Tablature.parse(tab))
        let shape = blocks.map { b -> String in
            switch b {
            case .systems(let g): "systems \(g.count)"
            case .node(.text(let t)): t
            case .node(.empty): "blank"
            case .node: "other"
            }
        }
        XCTAssertEqual(shape, ["systems 2", "blank", "Then the verse", "systems 1", "blank"])
    }
}
