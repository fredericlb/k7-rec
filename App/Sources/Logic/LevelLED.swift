// The rec button's LED: the input level as one colour, black when silent, then green, orange, red at the top.
import Foundation

enum LevelLED {
    /// The colour stops, level then red, green, blue; a level between two stops blends them.
    static let stops: [(level: Double, rgb: (Double, Double, Double))] = [
        (0, (0, 0, 0)),
        (0.35, (0.15, 0.85, 0.3)),
        (0.7, (1, 0.6, 0)),
        (1, (1, 0.12, 0.08)),
    ]

    /// The LED's red, green and blue for `level`, clamped to 0...1.
    static func rgb(_ level: Double) -> (red: Double, green: Double, blue: Double) {
        let l = min(1, max(0, level.isFinite ? level : 0))
        guard let upper = stops.firstIndex(where: { $0.level >= l }), upper > 0 else { return stops[0].rgb }
        let (a, b) = (stops[upper - 1], stops[upper])
        let t = (l - a.level) / (b.level - a.level)
        return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, a.rgb.1 + (b.rgb.1 - a.rgb.1) * t, a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
    }
}
