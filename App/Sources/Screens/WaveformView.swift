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
            .onTapGesture { location in seek(toX: location.x, in: geo.size.width) }
            .gesture(DragGesture(minimumDistance: 8).onChanged { drag in
                // A mostly vertical drag is the page scrolling, not a scrub.
                if abs(drag.translation.width) > abs(drag.translation.height) { seek(toX: drag.location.x, in: geo.size.width) }
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(Text(clock(position())))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 5.0 : -5.0
            onSeek(min(max(position() + step, 0), duration))
            seeks += 1
        }
    }

    private func seek(toX x: CGFloat, in width: CGFloat) {
        guard duration > 0, width > 0 else { return }
        onSeek(min(max(x / width, 0), 1) * duration)
        seeks += 1
    }
}

struct WaveformBars: View, Equatable {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            let bars = max(1, Int(size.width / step))
            guard !samples.isEmpty else { return }
            for i in 0..<bars {
                let lo = i * samples.count / bars
                let hi = max(lo + 1, (i + 1) * samples.count / bars)
                let level = samples[lo..<min(hi, samples.count)].max() ?? 0
                let h = max(2, CGFloat(min(1, level)) * size.height)
                let bar = CGRect(x: CGFloat(i) * step + 1, y: (size.height - h) / 2, width: 3, height: h)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(k7.accentLine))
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
            Rectangle().fill(.white).frame(width: 2).offset(x: fraction * width)
        }
        .allowsHitTesting(false)
    }
}
