// The take panel's live well: the last 30 seconds of the running take, scrolled smoothly at display rate, with its
// highlight spans as buttons and the zoom onto the one heard. Why bins and a clock: docs/app.md, "Screens".
import RehearsalAudio
import SwiftUI

struct LiveWell: View {
    let samples: [Double]
    /// The take time of `samples[0]`; it moves one bucket at a time, as buckets arrive.
    let start: TimeInterval
    let paused: Bool
    let highlights: [Highlight]
    let heard: Highlight?
    let range: ClosedRange<TimeInterval>?
    let position: TimeInterval
    let listen: (Highlight) -> Void

    /// The newest bucket's end in take time, and when it arrived: the clock the scroll runs from between buckets.
    @State private var sync: (end: TimeInterval, at: Date) = (0, .now)
    private static let window = LiveTake.windowSeconds
    private static let interval = Double(defaultEnvelopeIntervalMs) / 1000

    var body: some View {
        TimelineView(.animation(paused: paused || heard != nil)) { context in
            GeometryReader { geo in
                let left = leftEdge(at: context.date)
                content(left: left, size: geo.size)
            }
        }
        .waveWell()
        .onChange(of: start, initial: true) { _, s in sync = (s + Self.window, .now) }
    }

    /// The take time at the well's left edge: the newest bucket's end, run on by the wall clock for at most one
    /// bucket, less the window and one bucket, so a new bucket slides in from the right instead of appearing.
    private func leftEdge(at now: Date) -> TimeInterval {
        let run = paused || heard != nil ? Self.interval : min(Self.interval, max(0, now.timeIntervalSince(sync.at)))
        return sync.end + run - Self.interval - Self.window
    }

    @ViewBuilder private func content(left: TimeInterval, size: CGSize) -> some View {
        let w = size.width
        let frac = { (t: TimeInterval) in (t - left) / Self.window }
        let zoom: Double = heard.map { 0.8 / max(0.02, frac($0.span.upperBound) - frac($0.span.lowerBound)) } ?? 1
        let shift: Double = heard.map { 0.1 * w - frac($0.span.lowerBound) * zoom * w } ?? 0
        ZStack(alignment: .topLeading) {
            LiveBars(samples: samples, start: start, left: left, width: w)
            WaveformMarks(duration: Self.window, start: left, saved: highlights.map(\.span)).equatable()
            ForEach(highlights) { h in
                let x = frac(h.span.lowerBound) * zoom * w, sw = max(12, (frac(h.span.upperBound) - frac(h.span.lowerBound)) * zoom * w)
                Button { listen(h) } label: { Rectangle().fill(heard?.id == h.id ? k7.highlightFillSelected : Color.clear) }
                    .buttonStyle(.plain)
                    .frame(width: sw, height: size.height).offset(x: x)
                    .accessibilityLabel(heard?.id == h.id ? "Stop highlight" : "Play highlight \(clock(h.span.lowerBound)), pauses the recording")
            }
            if let h = heard, let range, range.upperBound > range.lowerBound {
                let p = min(1, max(0, (position - range.lowerBound) / (range.upperBound - range.lowerBound)))
                let x = (frac(h.span.lowerBound) + p * (frac(h.span.upperBound) - frac(h.span.lowerBound))) * zoom * w
                Rectangle().fill(k7.playhead).frame(width: 2, height: size.height).offset(x: x).accessibilityHidden(true)
            }
        }
        .frame(width: w * zoom, height: size.height, alignment: .leading)
        .offset(x: shift)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: heard?.id)
    }
}

/// The envelope as bars pinned to fixed bins of take time: a bin always holds the same buckets, so a bar keeps
/// its height as it slides left instead of changing with each regrouping of the window.
private struct LiveBars: View {
    let samples: [Double]
    let start: TimeInterval
    let left: TimeInterval
    /// The well's width at zoom 1, which sets the bars' 5 pt pitch; a zoom stretches the pitch with the well.
    let width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard width > 0, !samples.isEmpty else { return }
            let interval = Double(defaultEnvelopeIntervalMs) / 1000, window = LiveTake.windowSeconds
            let perBin = max(1, Int((Double(samples.count) * 5 / Double(width)).rounded()))
            let first = Int((start / interval).rounded())
            let scale = Double(size.width) / window
            let pitch = Double(perBin) * interval * scale
            for (lo, level) in LiveBins.levels(samples, first: first, perBin: perBin) {
                let x = (Double(lo) * interval - left) * scale
                guard x + pitch >= 0, x <= Double(size.width) else { continue }
                let h = max(2, CGFloat(min(1, level)) * size.height)
                let bar = CGRect(x: x + (pitch - 3) / 2, y: (size.height - h) / 2, width: 3, height: h)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(k7.accentLine))
            }
        }
        .allowsHitTesting(false)
    }
}

enum LiveBins {
    /// The loudest bucket of each bin of `perBin` buckets, bins counted from the take's first bucket, so a bin's
    /// level depends only on its own buckets; `first` is the take bucket of `samples[0]`. Returns each bin's first bucket.
    static func levels(_ samples: [Double], first: Int, perBin: Int) -> [(bucket: Int, level: Double)] {
        guard perBin > 0, !samples.isEmpty else { return [] }
        let end = first + samples.count
        var lo = Int((Double(first) / Double(perBin)).rounded(.down)) * perBin
        var out: [(bucket: Int, level: Double)] = []
        while lo < end {
            let level = (max(lo, first)..<min(lo + perBin, end)).map { samples[$0 - first] }.max() ?? 0
            out.append((lo, level))
            lo += perBin
        }
        return out
    }
}
