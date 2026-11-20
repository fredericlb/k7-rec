// The input level on a decibel scale, for the panel's bar and the rec button's tint: the recorder's level is
// linear (its RMS × 3), so a quiet room or a voice would stay near zero on a linear scale.
import Foundation

enum LevelMeter {
    /// The decibels the bar starts at: empty there and below, full at the level's ceiling.
    static let floorDB = -40.0

    /// Where a linear level falls on the bar, 0 at `floorDB` and below, 1 at full level.
    static func position(_ level: Double) -> Double {
        guard level.isFinite, level > 0 else { return 0 }
        return min(1, max(0, (20 * log10(level) - floorDB) / -floorDB))
    }

    /// The tint stops on the same scale, red, green, blue: green by -20 dB, orange at -6 dB, red at full level.
    static let stops: [(at: Double, rgb: (Double, Double, Double))] = [
        (0.5, (0.15, 0.85, 0.3)),
        (0.85, (1, 0.6, 0)),
        (1, (1, 0.12, 0.08)),
    ]

    /// The rec button's tint for a linear `level`: clear at silence, fading in to green, then orange, red at full level.
    static func tint(_ level: Double) -> (red: Double, green: Double, blue: Double, alpha: Double) { tint(at: position(level)) }

    /// The tint for a position on the scale, as `follow` smooths it.
    static func tint(at p: Double) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let p = min(1, max(0, p))
        let alpha = min(1, p / stops[0].at) * 0.8
        guard let upper = stops.firstIndex(where: { $0.at >= p }), upper > 0 else {
            let c = stops[0].rgb
            return (c.0, c.1, c.2, alpha)
        }
        let (a, b) = (stops[upper - 1], stops[upper])
        let t = (p - a.at) / (b.at - a.at)
        return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, a.rgb.1 + (b.rgb.1 - a.rgb.1) * t, a.rgb.2 + (b.rgb.2 - a.rgb.2) * t, alpha)
    }

    /// One 50 ms step of a meter's ballistics on the scale: it rises fast (half the way per step, so a peak
    /// shows within 150 ms) and falls slowly (15% per step, about half a second), so the tint does not flicker.
    static func follow(_ current: Double, toward target: Double) -> Double {
        current + (target - current) * (target > current ? 0.5 : 0.15)
    }
}
