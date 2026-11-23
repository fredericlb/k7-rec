import Testing
@testable import RehearsalText

@Suite struct PianoChordTests {
    @Test func aTriadIsInRootPositionWithOneThreeFive() {
        #expect(PianoChord.voicing("C") == PianoVoicing(keys: [0, 4, 7], fingers: [1, 3, 5], bass: nil))
        #expect(PianoChord.voicing("Am")?.keys == [9, 12, 16])
        #expect(PianoChord.voicing("F#dim")?.keys == [6, 9, 12])
    }

    @Test func aSeventhTakesFourKeysAndFingers() {
        #expect(PianoChord.voicing("G7") == PianoVoicing(keys: [7, 11, 14, 17], fingers: [1, 2, 3, 5], bass: nil))
        #expect(PianoChord.voicing("BbΔ")?.keys == [10, 14, 17, 21])
    }

    @Test func aSlashChordGivesTheLeftHandItsBass() {
        let v = PianoChord.voicing("D/F#")
        #expect(v?.bass == 6)
        #expect(v?.keys == [14, 18, 21])
    }

    @Test func aThirteenthReachesAboveTheOctave() {
        #expect(PianoChord.voicing("A13")?.keys == [9, 13, 19, 23, 30])
    }

    @Test func anUnknownQualityFallsBackToItsTriadAndNoChordToNil() {
        #expect(PianoChord.voicing("Em7(11)")?.keys == [4, 7, 11])
        #expect(PianoChord.voicing("Hello") == nil)
        #expect(PianoChord.voicing("N.C.") == nil)
    }
}
