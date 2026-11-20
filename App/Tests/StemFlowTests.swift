// The whole flow with the real model: compile a dropped package, separate a file, find the stems, open them; skipped without STEM_MODEL.
import AVFoundation
import RehearsalStems
import XCTest
@testable import K7Rec

@MainActor
final class StemFlowTests: XCTestCase {
    func testADroppedPackageSeparatesAFileAndTheStemsOpen() async throws {
        guard let path = ProcessInfo.processInfo.environment["STEM_MODEL"] else { throw XCTSkip("STEM_MODEL is not set") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stemflow-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Songs/Jam abcd1234", isDirectory: true)
        let models = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: models.appendingPathComponent("StemSeparator.mlpackage"))
        let source = folder.appendingPathComponent("original.wav")
        try writeSine(seconds: 12, to: source)
        var song = Song(id: "1", title: "Jam", artist: "")
        (song.folder, song.audioURL) = ("Jam abcd1234", source)
        let maker = LiveStemMaker(songs: root.appendingPathComponent("Songs"), models: models, bundle: Bundle(for: StemFlowTests.self))
        XCTAssertTrue(maker.hasModel)
        let failure = await maker.separate(song) { _ in }
        XCTAssertNil(failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: models.appendingPathComponent("StemSeparator.mlmodelc").path), "the package is kept compiled")
        let urls = try XCTUnwrap(maker.existing(for: song))
        let session = try StemSession(urls: urls)
        XCTAssertEqual(session.duration, 12, accuracy: 0.2)
    }

    private func writeSine(seconds: Double, to url: URL) throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
        let n = AVAudioFrameCount(seconds * 44_100)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        buf.frameLength = n
        for c in 0..<2 { for i in 0..<Int(n) { buf.floatChannelData![c][i] = 0.3 * Float(sin(2 * Double.pi * 220 * Double(i) / 44_100)) } }
        try file.write(from: buf)
    }
}
