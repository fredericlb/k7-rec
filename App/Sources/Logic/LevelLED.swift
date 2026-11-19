// The rec button's LED: the input level as one colour, black when silent, then green, orange, red at the top.
// The level is linear (the recorder's RMS × 3), so the colour follows its decibels, as a meter does.
import Foundation

enum LevelLED {
    /// The decibels of the level the scale starts at (black) and ends at (red, the level's ceiling).
    static let floorDB = -40.0
    /// The colour stops, position on the decibel scale then red, green, blue; between two stops they blend.
    static let stops: [(at: Double, rgb: (Double, Double, Double))] = [
        (0, (0, 0, 0)),
        (0.5, (0.15, 0.85, 0.3)),
        (0.85, (1, 0.6, 0)),
        (1, (1, 0.12, 0.08)),
    ]

    /// Where a linear level falls on the scale, 0 at `floorDB` and below, 1 at full level.
    static func position(_ level: Double) -> Double {
        guard level.isFinite, level > 0 else { return 0 }
        return min(1, max(0, (20 * log10(level) - floorDB) / -floorDB))
    }

    /// The LED's red, green and blue for a linear `level`.
    static func rgb(_ level: Double) -> (red: Double, green: Double, blue: Double) {
        let p = position(level)
        guard let upper = stops.firstIndex(where: { $0.at >= p }), upper > 0 else { return stops[0].rgb }
        let (a, b) = (stops[upper - 1], stops[upper])
        let t = (p - a.at) / (b.at - a.at)
        return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, a.rgb.1 + (b.rgb.1 - a.rgb.1) * t, a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
    }
}
