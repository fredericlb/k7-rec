// Shared helpers of the app tests: temp folders, a generated wav and a scripted audio input.
import AVFoundation
import RehearsalAudio
import XCTest

func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rehearsal-app-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A mono 16-bit wav of `seconds` of a sine at `amp`.
func makeWav(at url: URL, seconds: Double, amp: Float, rate: Double = 8000) throws {
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
    ])
    let frames = AVAudioFrameCount(seconds * rate)
    let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buffer.frameLength = frames
    for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = amp * Float(sin(2 * Double.pi * 220 * Double(i) / rate)) }
    try file.write(from: buffer)
}

/// A FLAC of one second whose `comments` ("TITLE=…") are a Vorbis comment block after its STREAMINFO.
func makeTaggedFlac(at url: URL, comments: [String]) throws {
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8000, channels: 1, interleaved: false)!
    do {
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1])
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 8000)!
        buffer.frameLength = 8000
        for i in 0..<8000 { buffer.floatChannelData![0][i] = 0.3 * sin(Float(i) / 5) }
        try file.write(from: buffer)
    }
    var data = try Data(contentsOf: url)
    func le(_ n: Int) -> [UInt8] { (0..<4).map { UInt8(n >> (8 * $0) & 0xFF) } }
    var body = le(4) + Array("test".utf8) + le(comments.count)
    for c in comments { body += le(c.utf8.count) + Array(c.utf8) }
    // STREAMINFO is 4 + 34 bytes after "fLaC"; the new block takes over its last-block flag.
    let last = data[4] & 0x80
    data[4] &= 0x7F
    let header = [4 | last, UInt8(body.count >> 16 & 0xFF), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)]
    data.insert(contentsOf: header + body, at: 42)
    try data.write(to: url)
}

/// An input that makes no sound until a test pushes frames.
final class ScriptedInput: AudioInput, @unchecked Sendable {
    var sampleRate = 8000.0
    var onLost: (@Sendable () -> Void)?
    private var sink: (@Sendable (UnsafeBufferPointer<Float>) -> Void)?

    func start(_ onFrames: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws { sink = onFrames }
    func stop() { sink = nil }

    func push(seconds: Double, amp: Float) {
        let frames = (0..<Int(seconds * sampleRate)).map { amp * Float(sin(2 * Double.pi * 220 * Double($0) / sampleRate)) }
        frames.withUnsafeBufferPointer { sink?($0) }
    }
}

/// A session that records what it was asked and lets a test send interruptions.
final class ScriptedSession: SessionHost, @unchecked Sendable {
    var onInterruption: (@Sendable (InterruptionEvent) -> Void)?
    private(set) var headsetAsked: [Bool] = []
    var failing = false
    func observe() {}
    func unobserve() {}
    func activate(recording: Bool, headsetInput: Bool) throws {
        if failing { throw CocoaError(.fileWriteUnknown) }
        headsetAsked.append(headsetInput)
    }
    func send(_ e: InterruptionEvent) { onInterruption?(e) }
}

/// What a crash leaves: a 32-bit float CAF of `seconds` of sine, named like the recorder names its raw takes.
func makeRawTake(in folder: URL, seconds: Double, amp: Float, rate: Double = 8000) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("take-\(UUID().uuidString).raw.caf")
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
    let frames = AVAudioFrameCount(seconds * rate)
    let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buffer.frameLength = frames
    for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = amp * Float(sin(2 * Double.pi * 220 * Double(i) / rate)) }
    try file.write(from: buffer)
    return url
}

/// Hands the recorder a fresh input per take part, as the device does, and keeps the live one for the test to push into.
final class InputBox: @unchecked Sendable {
    var rate = 8000.0
    private(set) var current = ScriptedInput()
    func make() -> AudioInput {
        current = ScriptedInput()
        current.sampleRate = rate
        return current
    }
}

/// A switch a test flips between two calls of a closure the code under test keeps.
@MainActor
final class Flag {
    var value = false
}
