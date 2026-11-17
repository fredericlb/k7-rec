// The take as it runs: its envelope re-levelled as it grows, the stretch to draw, and the moments found so far.
// What a reader gets wrong: samples arrive raw and the level follows the loudest one, as the saved take's does.
import Foundation
import RehearsalAudio

/// A moment found in the running take, with the slice of the envelope that draws it.
struct Highlight: Identifiable, Equatable {
    let span: ClosedRange<TimeInterval>
    let samples: [Double]
    var id: Int { Int(span.lowerBound * 10) }
}

struct LiveTake {
    /// The earlier parts of a continued take, already levelled.
    private let base: [Double]
    private var raw: [Double] = []
    private var rawPeak = 0.0
    private(set) var highlights: [Highlight] = []
    var moments: Int { highlights.count }
    let intervalMs: Int
    /// Seconds of the earlier parts, which a raw file of this part does not hold.
    var baseSeconds: Double { Double(base.count * intervalMs) / 1000 }
    /// The detector runs once per this many buckets: it reads the whole take.
    private static let detectEvery = 5
    static let windowSeconds = 30.0

    init(base: [Double] = [], intervalMs: Int = defaultEnvelopeIntervalMs) { (self.base, self.intervalMs) = (base, intervalMs) }

    /// A bucket in order; a repeated or skipped index is ignored.
    mutating func append(index: Int, sample: Double) {
        guard index == raw.count else { return }
        raw.append(sample)
        rawPeak = max(rawPeak, sample)
        if raw.count % Self.detectEvery == 0 { highlights = detect() }
    }

    var levelled: [Double] {
        let gain = Gain.envelope(rawPeak: rawPeak)
        return base + raw.map { min(1, $0 * gain) }
    }

    /// The last `windowSeconds`, padded with silence on the left so a young take draws from the right edge.
    func window(intervalMs: Int = defaultEnvelopeIntervalMs) -> [Double] {
        let size = Int(Self.windowSeconds * 1000) / intervalMs
        let tail = Array(levelled.suffix(size))
        return [Double](repeating: 0, count: size - tail.count) + tail
    }

    /// The take time at the left edge of `window()`; negative while a young take is padded.
    var windowStart: TimeInterval {
        let size = Int(Self.windowSeconds * 1000) / intervalMs
        return Double(base.count + raw.count - size) * Double(intervalMs) / 1000
    }

    private func detect() -> [Highlight] {
        let all = levelled
        let found = MomentDetector.detect(envelope: Envelope(samples: all)).moments
        return found.map { m in
            let lo = min(all.count, max(0, Int(m.startSec * 1000) / intervalMs)), hi = min(all.count, max(lo, Int(m.endSec * 1000) / intervalMs))
            return Highlight(span: m.startSec...m.endSec, samples: Array(all[lo..<hi]))
        }
    }
}
