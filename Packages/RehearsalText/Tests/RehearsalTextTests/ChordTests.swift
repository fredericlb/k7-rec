// Ported from packages/lyrics/src/chords.test.ts; every case there is a case here.

import Testing

@testable import RehearsalText

@Suite struct IsChordTests {
    @Test func acceptsCommonSpellings() {
        for c in ["C", "Am", "C#m7", "Bb", "G/B", "Cmaj7", "Dsus4", "F#m7b5", "N.C."] {
            #expect(Chord.isChord(c), "\(c)")
        }
    }

    @Test func acceptsAQualityAfterANumber() {
        for c in ["A7sus4", "C9sus4", "D7add11", "E7sus2/B"] {
            #expect(Chord.isChord(c), "\(c)")
        }
        #expect(ChordSheet.parse("Em7   G    Dsus4   A7sus4")[0] == .chords(text: "Em7   G    Dsus4   A7sus4"))
    }

    @Test func rejectsOrdinaryWords() {
        for w in ["Hello", "Verse", "Bad", "Cage", "Fed", "the", "Chorus", "Dad", "Add", "Ada", "Base", "Gasp"] {
            #expect(!Chord.isChord(w), "\(w)")
        }
    }
}

@Suite struct ParseChordSheetTests {
    @Test func classifiesSectionHeaders() {
        #expect(ChordSheet.parse("[Verse 1]")[0] == .section(label: "Verse 1"))
        #expect(ChordSheet.parse("(Chorus)")[0] == .section(label: "Chorus"))
        #expect(ChordSheet.parse("Bridge:")[0] == .section(label: "Bridge"))
    }

    @Test func detectsChordsAboveLyrics() {
        #expect(ChordSheet.parse("C       G   Am")[0] == .chords(text: "C       G   Am"))
    }

    @Test func tokenizesInlineChords() {
        let line = ChordSheet.parse("[C]Hello darkness [G]my old friend")[0]
        #expect(
            line
                == .lyrics(segments: [
                    Segment(chord: "C", text: "Hello darkness "),
                    Segment(chord: "G", text: "my old friend"),
                ]))
    }

    @Test func leavesPlainLyricsUntouched() {
        #expect(ChordSheet.parse("just some words")[0] == .lyrics(segments: [Segment(chord: nil, text: "just some words")]))
    }

    @Test func blankIsEmpty() {
        #expect(ChordSheet.parse("")[0] == .empty)
    }

    @Test func honorsOverrideMarkers() {
        #expect(ChordSheet.parse("A %t")[0] == .lyrics(segments: [Segment(chord: nil, text: "A")]))
        #expect(ChordSheet.parse("do re mi %c")[0] == .chords(text: "do re mi"))
    }

    @Test func nonChordBracketsStayLiteral() {
        #expect(ChordSheet.parse("go [x2] on")[0] == .lyrics(segments: [Segment(chord: nil, text: "go [x2] on")]))
    }

    @Test func crlfSplitsLines() {
        #expect(ChordSheet.parse("a\r\nb").count == 2)
    }
}

@Suite struct TransposeTests {
    @Test func shiftsRootKeepsQuality() {
        #expect(Chord.transpose("C", semitones: 2) == "D")
        #expect(Chord.transpose("Am7", semitones: 2) == "Bm7")
        #expect(Chord.transpose("A", semitones: -1) == "G#")
    }

    @Test func prefersFlatsWhenOriginalUsedOne() {
        #expect(Chord.transpose("Bb", semitones: 2) == "C")
        #expect(Chord.transpose("Ab", semitones: -1) == "G")
        #expect(Chord.transpose("Bb", semitones: 1) == "B")
        #expect(Chord.transpose("Bb", semitones: 3) == "Db")
    }

    @Test func movesSlashBassToo() {
        #expect(Chord.transpose("G/B", semitones: 2) == "A/C#")
    }

    @Test func wrapsAroundTheOctave() {
        #expect(Chord.transpose("B", semitones: 1) == "C")
        #expect(Chord.transpose("C", semitones: -1) == "B")
        #expect(Chord.transpose("C", semitones: 13) == "C#")
    }

    @Test func leavesNonChordsAndZeroUnchanged() {
        #expect(Chord.transpose("Hello", semitones: 2) == "Hello")
        #expect(Chord.transpose("C", semitones: 0) == "C")
        #expect(Chord.transpose("N.C.", semitones: 2) == "N.C.")
    }

    @Test func lineKeepsSpacing() {
        #expect(transposeLine("C   G   Am", semitones: 2) == "D   A   Bm")
        #expect(transposeLine("  C  G/B ", semitones: 2) == "  D  A/C# ")
        #expect(transposeLine("C", semitones: 0) == "C")
    }
}

@Suite struct SplitChordTests {
    @Test func splitsRootSuffixBass() {
        #expect(Chord("C#m7") == Chord("C#m7"))
        let a = Chord("C#m7")
        #expect(a?.root == "C#" && a?.suffix == "m7" && a?.bass == nil)
        let b = Chord("G/B")
        #expect(b?.root == "G" && b?.suffix == "" && b?.bass == "B")
        #expect(Chord("Hello") == nil)
        #expect(b?.description == "G/B")
    }
}

@Suite struct CollectChordsTests {
    @Test func uniqueInFirstSeenOrderAcrossBothFormats() {
        let text = ["C       G   Am", "[C]hello [G]world [Am]again", "C"].joined(separator: "\n")
        #expect(ChordSheet.collectChords(text) == ["C", "G", "Am"])
    }

    @Test func ignoresSectionsAndPlainLyrics() {
        #expect(ChordSheet.collectChords("[Chorus]\njust words here").isEmpty)
    }
}

@Suite struct TimecodeTextTests {
    @Test func readWrittenTakenOff() {
        #expect(LyricsTiming.timecode(of: "Oh sinnerman {{01:05}}") == 65)
        #expect(LyricsTiming.timecode(of: "Oh sinnerman") == nil)
        #expect(abs((LyricsTiming.timecode(of: "{{01:05.63}} Oh sinnerman") ?? 0) - 65.63) < 1e-9)
        #expect(LyricsTiming.format(65.63) == "{{01:05.63}}")
        #expect(LyricsTiming.format(6005) == "{{100:05.00}}")
        #expect(LyricsTiming.strip("Oh sinnerman {{01:05}}") == "Oh sinnerman")
        #expect(LyricsTiming.strip("{{01:05.63}} Oh sinnerman") == "Oh sinnerman")
        #expect(LyricsTiming.strip("  {{01:05.63}} Oh sinnerman") == "  Oh sinnerman")
    }

    @Test func neverShowOnTheSheetNorMakeAChordLine() {
        let line = ChordSheet.parse("{{00:12.50}} Am I blue")[0]
        #expect(line == .lyrics(segments: [Segment(chord: nil, text: "Am I blue")]))
    }
}

@Suite struct HandTypedTests {
    @Test func tabFromLyric() {
        #expect(ChordSheet.isTabLine("e|-----0-----|"))
        #expect(ChordSheet.isTabLine("|--3--5--|"))
        #expect(!ChordSheet.isTabLine("I could go - off - the | end"))
    }

    @Test func readsEmphasisedChords() {
        #expect(ChordSheet.looseChordLine("C**"))
        #expect(ChordSheet.looseChordLine("C   G.  Am"))
        #expect(!ChordSheet.looseChordLine("Can I go"))
        #expect(!ChordSheet.looseChordLine(""))
    }
}
