// Ported from packages/lyrics/src/lrc.test.ts; every case there is a case here.

import Testing

@testable import RehearsalText

let lrcSample = """
    [ar:Nina Simone]
    [ti:Sinnerman]
    [00:12.50]Oh sinnerman, where you gonna run to?
    [00:18.00]Where you gonna run to?
    [00:24.25]All on that day

    """

@Suite struct ParseLrcTests {
    @Test func readsTimedLinesInOrderIgnoringHeaderTags() {
        #expect(
            LRC.parse(lrcSample) == [
                LrcLine(t: 12.5, text: "Oh sinnerman, where you gonna run to?"),
                LrcLine(t: 18, text: "Where you gonna run to?"),
                LrcLine(t: 24.25, text: "All on that day"),
            ])
    }

    @Test func repeatsMultiStampLinesAndDropsWordStamps() {
        #expect(
            LRC.parse("[00:30.00][01:10.00]Chorus <00:30.50>line") == [
                LrcLine(t: 30, text: "Chorus line"), LrcLine(t: 70, text: "Chorus line"),
            ])
    }

    @Test func positiveOffsetIsSooner() {
        #expect(abs(LRC.parse("[offset:+500]\n[00:10.00]Hi")[0].t - 9.5) < 1e-9)
    }
}

@Suite struct NormalizeTests {
    @Test func withoutAccentsCaseOrPunctuation() {
        #expect(LRC.normalizeLine("  Où, sont-ils ?! ") == "ou sont ils")
    }

    @Test func keepsOnlySungLines() {
        let sheet = "[Verse]\nC      G\n[C]Oh sinner[G]man\n\nAll on that day"
        #expect(
            LRC.lyricLines(sheet) == [
                SungLine(line: 2, text: "oh sinnerman"), SungLine(line: 4, text: "all on that day"),
            ])
    }
}

@Suite struct AlignLinesTests {
    @Test func keepsOrderSoARepeatedChorusPairsWithItsOwn() {
        let a = ["verse one", "chorus", "verse two", "chorus"]
        let pairs = LineAlign.alignLines(a, a, threshold: 0.7)
        #expect(pairs.map(\.0) == [0, 1, 2, 3] && pairs.map(\.1) == [0, 1, 2, 3])
    }

    @Test func pairsTyposAndSkipsOneSidedLines() {
        let a = ["where you gonna run to", "an extra ad lib", "all on that day"]
        let b = ["where you gona run to", "all on that day"]
        let pairs = LineAlign.alignLines(a, b, threshold: 0.7)
        #expect(pairs.map(\.0) == [0, 2] && pairs.map(\.1) == [0, 1])
    }
}

@Suite struct TimeLyricsTests {
    func timed(_ lyrics: String, _ lrc: String = lrcSample) -> (lyrics: String, placed: Int, total: Int) {
        guard case .ok(let l, let p, let t) = LRC.merge(lyrics: lyrics, lrc: lrc) else {
            Issue.record("no timing")
            return ("", 0, 0)
        }
        return (l, p, t)
    }

    @Test func putsCodesInFrontAndChangesNothingElse() {
        let sheet = [
            "[Verse]", "      C              G", "Oh sinnerman where you gonna run to",
            "Where you gona run to", "", "All on that day",
        ].joined(separator: "\n")
        let r = timed(sheet)
        #expect(
            r.lyrics.jsLines == [
                "[Verse]", "      C              G",
                "{{00:12.50}} Oh sinnerman where you gonna run to",
                "{{00:18.00}} Where you gona run to", "", "{{00:24.25}} All on that day",
            ])
        #expect(LyricsTiming.withoutTimecodes(r.lyrics) == sheet)
        #expect(r.placed == 3 && r.total == 3)
    }

    @Test func neverTimesChordTabOrSection() {
        let sheet = ["[Oh sinnerman]", "C**", "e|---0---2---|", "Oh sinnerman where you gonna run to"]
            .joined(separator: "\n")
        let out = timed(sheet).lyrics.jsLines
        #expect(Array(out[0..<3]) == ["[Oh sinnerman]", "C**", "e|---0---2---|"])
        #expect(out[3] == "{{00:12.50}} Oh sinnerman where you gonna run to")
    }

    @Test func keepsOrder() {
        let sheet = "All on that day\nOh sinnerman where you gonna run to\nWhere you gonna run to"
        let out = timed(sheet).lyrics.jsLines
        #expect(out[0] == "All on that day")
        #expect(out[1].hasPrefix("{{00:12.50}} "))
        #expect(out[2].hasPrefix("{{00:18.00}} "))
    }

    @Test func oneSheetLineSungAsTwoGetsTheFirstTime() {
        let lrc = "[00:12.00]But I've got an angry heart\n[00:14.00]Filled with cancers and poppy tarts"
        let r = timed("But I've got an angry heart, filled with cancers and poppy tarts.", lrc)
        #expect(r.lyrics == "{{00:12.00}} But I've got an angry heart, filled with cancers and poppy tarts.")
        #expect(r.placed == 2)
    }

    @Test func twoSheetLinesSungAsOneGiveItToTheFirst() {
        let lrc = "[01:10.00]If we could just get the braves to get out of bed in the morning"
        let sheet = "If we could just get the braves to get out of\n              C**\nbed in the morning."
        #expect(
            timed(sheet, lrc).lyrics.jsLines == [
                "{{01:10.00}} If we could just get the braves to get out of", "              C**",
                "bed in the morning.",
            ])
    }

    @Test func leavesUnresembledLinesUntimed() {
        let out = timed("Oh sinnerman where you gonna run to\nsome ad lib nobody wrote down").lyrics.jsLines
        #expect(out[1] == "some ad lib nobody wrote down")
    }

    @Test func replacesExistingCodes() {
        let once = timed("Oh sinnerman where you gonna run to").lyrics
        #expect(timed(once).lyrics == once)
        #expect(timed("{{03:33}} Oh sinnerman where you gonna run to").lyrics == once)
    }

    @Test func writesFetchedLinesWhenNoLyrics() {
        #expect(
            timed("").lyrics
                == "{{00:12.50}} Oh sinnerman, where you gonna run to?\n{{00:18.00}} Where you gonna run to?\n{{00:24.25}} All on that day"
        )
    }

    @Test func refusesLrcWithNoTimedLine() {
        #expect(LRC.merge(lyrics: "la", lrc: "no stamps here") == .empty)
    }
}

@Suite struct WithoutTimecodesTests {
    @Test func takesCodesOffLeavesTheRest() {
        let sheet = "[Verse]\n      C     G   \n{{00:12.50}} Oh sinnerman\nWhere {{01:05}}"
        #expect(LyricsTiming.withoutTimecodes(sheet) == "[Verse]\n      C     G   \nOh sinnerman\nWhere")
    }
}

@Suite struct TimecodesByLineTests {
    @Test func readsEachLinesCodeByIndex() {
        let text = "[Verse]\nC\n{{00:12.50}} Oh sinnerman\nWhere you gonna run to {{01:05}}"
        #expect(LyricsTiming.byLine(text) == [LineTime(line: 2, t: 12.5), LineTime(line: 3, t: 65)])
        #expect(LyricsTiming.hasTimecodes(text))
        #expect(!LyricsTiming.hasTimecodes("Oh sinnerman"))
    }

    @Test func aCodeDoesNotMakeALineSomethingElse() {
        #expect(LRC.lyricLines("{{00:12.50}} Oh sinnerman") == [SungLine(line: 0, text: "oh sinnerman")])
    }
}

@Suite struct StoredTimingTests {
    @Test func keepsUnchangedLinesAfterAnEditAndFollowsThePlayhead() {
        let parsed = LRC.parse(lrcSample)
        let lyrics = parsed.map(\.text).joined(separator: "\n")
        let timings = parsed.enumerated().map { StoredTiming(line: $0, text: LRC.normalizeLine($1.text), t: $1.t) }
        let edited = "Intro line\n\(lyrics)".replacingOccurrences(of: "All on that day", with: "All on this day")
        let byLine = LyricsTiming.fromStored(edited, timings)
        #expect(byLine == [LineTime(line: 1, t: 12.5), LineTime(line: 2, t: 18)])
        #expect(LyricsTiming.lineAt(byLine, seconds: 5) == nil)
        #expect(LyricsTiming.lineAt(byLine, seconds: 15) == 1)
        #expect(LyricsTiming.lineAt(byLine, seconds: 60) == 2)
    }
}

@Suite struct TimeFromSheetTests {
    static let lyrics = [
        "{{00:12.50}} Oh sinnerman, where you gonna run to?", "{{00:18.00}} Where you gonna run to?",
        "{{00:24.00}} All on that day",
    ].joined(separator: "\n")

    @Test func givesChordsTheTimesTheLyricsCarry() {
        let chords = [
            "Am            G", "Oh sinnerman, where you gonna run to?", "Am", "Where you gonna run to",
            "[Am]All on [G]that day",
        ].joined(separator: "\n")
        guard case .ok(let out, let placed, _) = LRC.mergeTimedSheet(target: chords, timedSheet: Self.lyrics) else {
            Issue.record("no timing")
            return
        }
        #expect(placed == 3)
        #expect(
            out.jsLines == [
                "Am            G", "{{00:12.50}} Oh sinnerman, where you gonna run to?", "Am",
                "{{00:18.00}} Where you gonna run to", "{{00:24.00}} [Am]All on [G]that day",
            ])
    }

    @Test func timingAgainChangesNothing() {
        guard case .ok(let first, _, _) = LRC.mergeTimedSheet(target: "All on that day", timedSheet: Self.lyrics),
            case .ok(let again, _, _) = LRC.mergeTimedSheet(target: first, timedSheet: Self.lyrics)
        else {
            Issue.record("no timing")
            return
        }
        #expect(again == "{{00:24.00}} All on that day")
    }

    @Test func lyricsWithNoCodeTimeNothing() {
        #expect(LRC.mergeTimedSheet(target: "All on that day", timedSheet: "All on that day") == .empty)
    }
}
