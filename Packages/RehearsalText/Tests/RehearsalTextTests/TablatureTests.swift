// Ported from packages/tablature/src/tab.test.ts; every case there is a case here.

import Testing

@testable import RehearsalText

func firstSystem(_ nodes: [TabNode]) -> TabSystem? {
    for n in nodes { if case .system(let s) = n { return s } }
    return nil
}

func systems(_ nodes: [TabNode]) -> [TabSystem] {
    nodes.compactMap { if case .system(let s) = $0 { return s } else { return nil } }
}

@Suite struct LooksLikeTabLineTests {
    @Test func acceptsRealTabLines() {
        for l in [
            "e|--0--2--3--|", "G|-0-2-0-h2-|", "|---5---7---|", "D|--12--10--|",
            "--4-----------4-----------4-----------4L----4-------|",
            "-----2-----------4----------|--2s-4g-5-------|",
        ] {
            #expect(Tablature.looksLikeTabLine(l), "\(l)")
        }
    }

    @Test func rejectsProseChordsAndSections() {
        for l in ["Hello darkness my old friend", "C   G   Am   F", "[Verse 1]", "Chorus:"] {
            #expect(!Tablature.looksLikeTabLine(l), "\(l)")
        }
    }
}

@Suite struct ParseTablatureTests {
    static let tab = [
        "[Intro]", "e|--0--2--3--|", "B|--1--1--0--|", "G|--0--2--0--|", "D|--2--2--0--|",
        "A|--3-----2--|", "E|--------3--|", "", "let ring",
    ].joined(separator: "\n")

    @Test func groupsSixStringLinesIntoOneSystem() {
        let s = firstSystem(Tablature.parse(Self.tab))
        #expect(s?.strings.count == 6)
        #expect(s?.strings[0].label == "e")
    }

    @Test func classifiesSectionEmptyAndTextAroundTheSystem() {
        let nodes = Tablature.parse(Self.tab)
        #expect(nodes[0] == .section(label: "Intro"))
        #expect(nodes.contains(.empty))
        #expect(nodes.last == .text("let ring"))
    }

    @Test func placesMultiDigitFretsAndCollectsBars() {
        let s = firstSystem(Tablature.parse("D|--12--10--|"))
        let frets = s?.strings[0].events.filter { $0.kind == .fret }
        #expect(frets?.map(\.text) == ["12", "10"])
        #expect(frets?[0].col == 3)
        #expect((s?.bars.count ?? 0) > 0)
    }

    @Test func keepsStandardTuningWholeDespiteDuplicateELabels() {
        let text = [
            "E |--------------------|", "B |--------3-----2-----|", "G |--------4-----4-----|",
            "D |-----4--------5-----|", "A |--2--------2--------|", "E |--------2-----------|",
        ].joined(separator: "\n")
        let all = systems(Tablature.parse(text))
        #expect(all.count == 1)
        #expect(all.first?.strings.count == 6)
    }

    @Test func labelLessStringsWithLAndGAreOneSystem() {
        let text = [
            "--3-----------------------0-----------3L----3--2----|",
            "--4-----------4-----------4-----------4L----4-------|",
            "--------4-------------------------------------------|",
            "--2-----------------------------2-------------------|",
            "--------------------------2-------------------------|",
            "--0-----------2-------------------------------------|",
        ].joined(separator: "\n")
        let all = systems(Tablature.parse(text))
        #expect(all.count == 1)
        #expect(all.first?.strings.count == 6)
    }

    @Test func parsesTheRealWorldExampleIntoFiveSystemsNoText() {
        let text = [
            "E |----------------------------|----------------------------|",
            "B |--------3-----------2-------|--------0-----------2-------|",
            "G |--------4-----------4-------|--------0-----------2-------|",
            "D |-----4--------------5-------|--------2-----------2-------|",
            "A |--2--------------2----------|-----2-----------4----------|",
            "E |--------------2-------------|--0-----------2-------------|",
            "",
            "----------------------------------------------------|",
            "--3-----------------------0-----------3L----3--2----|",
            "--4-----------4-----------4-----------4L----4-------|",
            "--------4-------------------------------------------|",
            "--2-----------------------------2-------------------|",
            "--------------------------2-------------------------|",
            "",
            "--0-----------2-------------|----------------|",
            "-----------3----------------|--3--5--7--5----|",
            "--------------------2-------|--4--6--7--6----|",
            "--------4-----------2-------|--------5-------|",
            "-----2-----------4----------|--2s-4g-5-------|",
            "--0-----------2-------------|----------------|",
            "",
            "-----------------------0--------------0g------------|",
            "--5-----------3L----3--2--2-----------2g------------|",
            "--6-----------4L----4-----3-------------------------|",
            "--------------------------------4g------------------|",
            "--------------------------1-------------------------|",
            "--0-----------2L----2-------------------------------|",
            "",
            "--------------------3-----------------2-----3-------|",
            "--3-----------------3-----3-------------------------|",
            "--4-----------4--------6--6g------------------------|",
            "--------4-----------------------4-------------------|",
            "--2-------------------------------------------------|",
            "--------------------------3-------------------------|",
        ].joined(separator: "\n")
        let nodes = Tablature.parse(text)
        let all = systems(nodes)
        #expect(all.count == 5)
        #expect(all.allSatisfy { $0.strings.count == 6 })
        #expect(!nodes.contains { if case .text = $0 { return true } else { return false } })
    }

    @Test func capturesTechniquesAsNonFretEvents() {
        let s = firstSystem(Tablature.parse("G|-0-2-0h2-|"))
        #expect(s?.strings[0].events.contains { $0.kind == .technique && $0.text == "h" } == true)
    }

    static let sideBySide = [
        "e -------------------------------       e ----------------------------|",
        "b -------------------------------       b ---------0------------------|",
        "f#----------------3-----------3--       f#---------0---0--------------|",
        "d --------0--(0)--------0--(0)---       d -------4---4----------4-----|",
        "a ----4h5---5-------4h5---5-----0       a -2---2----------0h2-2---0---|",
        "D -0-----------------------------  x2   D --------------------------4-|  let ring",
        "Then the verse",
        "e ------------------------------|",
        "b ------------------------------|",
    ].joined(separator: "\n")

    @Test func splitsSystemsWrittenSideBySideIntoOneAfterTheOther() {
        let all = systems(Tablature.parse(Self.sideBySide))
        #expect(all.count == 3)
        let labels = ["e", "b", "f#", "d", "a", "D"]
        #expect(all[0].strings.map(\.label) == labels)
        #expect(all[1].strings.map(\.label) == labels)
        let firstFret = all[1].strings[1].events.first
        #expect(firstFret?.col == 9, "the second system's columns start at its own label")
    }

    @Test func wordsAfterAPieceStayOnItsStringEvenBetweenTwoSystems() {
        let all = systems(Tablature.parse(Self.sideBySide))
        #expect(all[0].comments == ["", "", "", "", "", "x2"])
        #expect(all[1].comments == ["", "", "", "", "", "let ring"])
        #expect(all[2].comments == ["", ""])
    }

    @Test func textBetweenTwoSystemsIsKept() {
        let nodes = Tablature.parse(Self.sideBySide)
        #expect(nodes.contains(.text("Then the verse")))
    }

    @Test func aChordLineIsNotTab() {
        #expect(Tablature.row("C   G   Am   F") == nil)
        #expect(Tablature.row("Bridge") == nil)
    }

    @Test func repeatSignsAreTabNotWords() {
        let all = systems(Tablature.parse([
            "e ------------------------------::----------------::",
            "D -7---------------7------------::-7--------------:: (bits within the dots x2)",
        ].joined(separator: "\n")))
        #expect(all.count == 1)
        #expect(all[0].comments == ["", "(bits within the dots x2)"])
        #expect(all[0].cols == 50, "the repeat signs are inside the system, not its comment")
    }
}
