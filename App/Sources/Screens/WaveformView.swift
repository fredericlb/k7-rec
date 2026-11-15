// A waveform from an envelope, with the playhead as its own layer so it never redraws the bars.
// What a reader gets wrong: the Canvas is Equatable and sees only the samples; only the overlay ticks.
import SwiftUI

struct WaveformView: View {
    let samples: [Double]
    let duration: TimeInterval
    let playing: Bool
    let position: () -> TimeInterval
    let onSeek: (TimeInterval) -> Void
    var marks: WaveformMarks?
    @State private var seeks = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                WaveformBars(samples: samples).equatable()
                if let marks { marks.equatable() }
                PlayheadLayer(playing: playing, duration: duration, width: geo.size.width, seeks: seeks, position: position)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard duration > 0, geo.size.width > 0 else { return }
                onSeek(min(max(drag.location.x / geo.size.width, 0), 1) * duration)
                seeks += 1
            })
        }
        .frame(height: 80)
    }
}

struct WaveformBars: View, Equatable {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            let bars = max(1, Int(size.width / step))
            guard !samples.isEmpty else { return }
            for i in 0..<bars {
                let lo = i * samples.count / bars
                let hi = max(lo + 1, (i + 1) * samples.count / bars)
                let level = samples[lo..<min(hi, samples.count)].max() ?? 0
                let h = max(2, CGFloat(min(1, level)) * size.height)
                let bar = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: 2, height: h)
                context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(.accentColor.opacity(0.6)))
            }
        }
    }
}

private struct PlayheadLayer: View {
    let playing: Bool
    let duration: TimeInterval
    let width: CGFloat
    let seeks: Int
    let position: () -> TimeInterval

    var body: some View {
        TimelineView(.animation(paused: !playing)) { _ in
            let fraction = duration > 0 ? min(1, max(0, position() / duration)) : 0
            Rectangle().fill(.red).frame(width: 2).offset(x: fraction * width)
        }
        .allowsHitTesting(false)
    }
}
