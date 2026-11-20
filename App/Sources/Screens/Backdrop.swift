// The ground behind every screen: two blurred glows at the bottom and two wave lines that are always moving.
// Silent, they drift apart slowly; with sound they follow its level and speed up (docs/app.md, "Look").
import SwiftUI

struct Backdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                k7.ground
                Ellipse().fill(k7.glow1).opacity(0.55)
                    .frame(width: max(300, w * 0.44), height: 280).blur(radius: 70)
                    .position(x: w * 0.33, y: h + 10)
                Ellipse().fill(k7.glow2).opacity(0.4)
                    .frame(width: max(260, w * 0.37), height: 270).blur(radius: 75)
                    .position(x: w * 0.68, y: h + 30)
                Waves().frame(height: 115).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct Waves: View {
    @Environment(AppModel.self) private var model: AppModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = WaveClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let state = reduceMotion ? WaveClock.State() : clock.step(at: context.date, level: model?.soundLevel)
            Canvas { ctx, size in
                ctx.stroke(WaveShape.first.path(in: size, phase: state.phase1, scale: state.scale), with: .color(k7.accentLine.opacity(0.5)), lineWidth: 2)
                ctx.stroke(WaveShape.second.path(in: size, phase: state.phase2, scale: state.scale), with: .color(k7.wave2.opacity(0.35)), lineWidth: 2)
            }
        }
    }
}

/// One wave line of the design system, one period across the width, as its mean and two harmonics (viewBox 115 tall).
struct WaveShape {
    let mean: Double
    let harmonics: [(k: Double, cos: Double, sin: Double)]

    static let first = WaveShape(mean: 62, harmonics: [(1, 8.57, 20.26), (2, 9.64, 2.68)])
    static let second = WaveShape(mean: 84, harmonics: [(1, 12.08, -7.06), (3, 1.59, 7.83)])

    /// The height at `u` (periods from the left), its swing about the mean multiplied by `scale`.
    func y(_ u: Double, scale: Double) -> Double {
        mean + scale * harmonics.reduce(0) { $0 + $1.cos * cos(2 * .pi * $1.k * u) + $1.sin * sin(2 * .pi * $1.k * u) }
    }

    func path(in size: CGSize, phase: Double, scale: Double) -> Path {
        var p = Path()
        let sy = size.height / 115
        for x in stride(from: 0.0, through: Double(size.width) + 4, by: 4) {
            let pt = CGPoint(x: x, y: y(x / Double(size.width) + phase, scale: scale) * sy)
            if x == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The waves' motion, advanced frame by frame so a change of speed never jumps: the two phases, the height the
/// level gives them (1× silent, 2× at full level), and how busy they are (0 silent, 1 with sound).
final class WaveClock {
    struct State {
        var phase1 = 0.0, phase2 = 0.0, scale = 1.0
    }

    /// Seconds for one full pass: silent, then with sound.
    static let periods = (silent: (60.0, 90.0), sound: (9.0, 13.0))
    private var last: Date?
    private var state = State()
    private(set) var height = 0.0
    private(set) var busy = 0.0

    /// Moves on to `now`; `level` is the linear level heard or recorded, nil when nothing plays or records.
    func step(at now: Date, level: Double?) -> State {
        let dt = last.map { min(0.1, max(0, now.timeIntervalSince($0))) } ?? 0
        last = now
        busy += ((level == nil ? 0 : 1) - busy) * min(1, dt / 0.8)
        let target = level.map(LevelMeter.position) ?? 0
        // The height rises in about a tenth of a second and settles in about half a second: it breathes.
        height += (target - height) * min(1, dt / (target > height ? 0.12 : 0.45))
        let p1 = Self.periods.silent.0 + (Self.periods.sound.0 - Self.periods.silent.0) * busy
        let p2 = Self.periods.silent.1 + (Self.periods.sound.1 - Self.periods.silent.1) * busy
        state.phase1 = (state.phase1 + dt / p1).truncatingRemainder(dividingBy: 1)
        state.phase2 = (state.phase2 - dt / p2).truncatingRemainder(dividingBy: 1)
        state.scale = 1 + height
        return state
    }
}
