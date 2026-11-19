// A sheet's kind, a score's parts, one part cut out, and a compressed .mxl opened to its score.
import Compression
import XCTest
@testable import Rehearsal

final class MusicXMLTests: XCTestCase {
    private let score = """
        <score-partwise><part-list>
        <part-group type="start" number="1"/>
        <score-part id="P1"><part-name>Piano &amp; Voice</part-name></score-part>
        <score-part id="P2"><part-name></part-name></score-part>
        <part-group type="stop" number="1"/>
        </part-list>
        <part id="P1"><measure number="1">one</measure></part>
        <part id="P2"><measure number="1">two</measure></part>
        </score-partwise>
        """

    func testTheKindIsToldByTheExtension() {
        XCTAssertEqual(SheetKind(url: URL(fileURLWithPath: "/a/b.PDF")), .pdf)
        XCTAssertEqual(SheetKind(url: URL(fileURLWithPath: "/a/b.mxl")), .score)
        XCTAssertEqual(SheetKind(url: URL(fileURLWithPath: "/a/b.musicxml")), .score)
        XCTAssertEqual(SheetKind(url: URL(fileURLWithPath: "/a/b.xml")), .score)
        XCTAssertEqual(SheetKind(url: URL(fileURLWithPath: "/a/b.jpg")), .image)
    }

    func testPartsAreNamedAndAnUnnamedOneIsNumbered() {
        XCTAssertEqual(MusicXML.parts(of: score), [.init(id: "P1", name: "Piano & Voice"), .init(id: "P2", name: "Part 2")])
    }

    func testKeepingAPartDropsTheOthersAndTheirBracket() {
        let kept = MusicXML.keepPart(score, index: 1)
        XCTAssertEqual(MusicXML.parts(of: kept).map(\.id), ["P2"])
        XCTAssertTrue(kept.contains("two"))
        XCTAssertFalse(kept.contains("one"))
        XCTAssertFalse(kept.contains("part-group"))
    }

    func testAnIndexOutOfRangeKeepsTheWholeFile() {
        XCTAssertEqual(MusicXML.keepPart(score, index: 5), score)
    }

    func testPlainTextIsReadAsIs() throws {
        XCTAssertEqual(try MusicXML.text(of: Data(score.utf8)), score)
    }

    func testAnMxlIsOpenedToTheScoreItsContainerNames() throws {
        let container = #"<container><rootfiles><rootfile full-path="music/song.musicxml"/></rootfiles></container>"#
        let zip = makeZip([("META-INF/container.xml", container, false), ("other.xml", "<no/>", true), ("music/song.musicxml", score, true)])
        XCTAssertEqual(try MusicXML.text(of: zip), score)
    }

    func testAnMxlWithoutAContainerIsReadByItsOneScore() throws {
        XCTAssertEqual(try MusicXML.text(of: makeZip([("song.xml", score, false)])), score)
    }

    func testAnMxlWithNoScoreSaysSo() {
        XCTAssertThrowsError(try MusicXML.text(of: makeZip([("readme.txt", "hi", false)])))
    }

    func testTheZoomWalksItsLadder() {
        XCTAssertEqual(ScoreSheet.step(0.5, by: 1), 0.75)
        XCTAssertEqual(ScoreSheet.step(0.6, by: -1), 0.5)
        XCTAssertEqual(ScoreSheet.step(2, by: 1), 2)
        XCTAssertEqual(ScoreSheet.openingScale(width: 390), 0.5)
        XCTAssertEqual(ScoreSheet.formatTranspose(-3), "♭3")
    }

    /// A zip of (name, text, deflated) entries, as a MusicXML editor writes an .mxl.
    private func makeZip(_ files: [(String, String, Bool)]) -> Data {
        var out = [UInt8](), directory = [UInt8]()
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        for (name, text, deflate) in files {
            let raw = Array(text.utf8), nameBytes = Array(name.utf8)
            var packed = raw
            if deflate {
                var buffer = [UInt8](repeating: 0, count: raw.count + 64)
                let n = compression_encode_buffer(&buffer, buffer.count, raw, raw.count, nil, COMPRESSION_ZLIB)
                packed = Array(buffer.prefix(n))
            }
            let method = deflate ? 8 : 0, offset = out.count
            out += le(0x0403_4B50, 4) + le(20, 2) + le(0, 2) + le(method, 2) + le(0, 4) + le(0, 4)
            out += le(packed.count, 4) + le(raw.count, 4) + le(nameBytes.count, 2) + le(0, 2) + nameBytes + packed
            directory += le(0x0201_4B50, 4) + le(20, 2) + le(20, 2) + le(0, 2) + le(method, 2) + le(0, 4) + le(0, 4)
            directory += le(packed.count, 4) + le(raw.count, 4) + le(nameBytes.count, 2) + le(0, 2) + le(0, 2)
            directory += le(0, 2) + le(0, 2) + le(0, 4) + le(offset, 4) + nameBytes
        }
        let start = out.count
        out += directory
        out += le(0x0605_4B50, 4) + le(0, 2) + le(0, 2) + le(files.count, 2) + le(files.count, 2)
        out += le(directory.count, 4) + le(start, 4) + le(0, 2)
        return Data(out)
    }
}
