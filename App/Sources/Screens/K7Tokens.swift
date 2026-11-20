// The K7 design system's tokens as Swift, copied unchanged from its "SwiftUI tokens" page (generated from
// tokens.json, 2026-11-19). Replace the file when the tokens change; never edit a value here (docs/app.md, "Look").
import SwiftUI

enum K7Theme {
    case daw, rec

    var ground: Color { self == .daw ? Color(.sRGB, red: 0.027, green: 0.016, blue: 0.059, opacity: 1) : Color(.sRGB, red: 0.059, green: 0.027, blue: 0.012, opacity: 1) }
    var surfaceSolid: Color { self == .daw ? Color(.sRGB, red: 0.086, green: 0.075, blue: 0.114, opacity: 1) : Color(.sRGB, red: 0.110, green: 0.078, blue: 0.059, opacity: 1) }
    var surfaceCard: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.06) }
    var hairlineCard: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.07) }
    var separator: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.1) }
    var fillControl: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.1) }
    var fillSelected: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.16) }
    var glassTop: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.14) }
    var glassBottom: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.06) }
    var glassBorder: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.16) }
    var well: Color { Color(.sRGB, red: 0.000, green: 0.000, blue: 0.000, opacity: 0.34) }
    var wellBorder: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.08) }
    var text: Color { self == .daw ? Color(.sRGB, red: 0.965, green: 0.953, blue: 0.984, opacity: 1) : Color(.sRGB, red: 0.984, green: 0.961, blue: 0.937, opacity: 1) }
    var textSecondary: Color { self == .daw ? Color(.sRGB, red: 0.725, green: 0.694, blue: 0.788, opacity: 1) : Color(.sRGB, red: 0.788, green: 0.733, blue: 0.682, opacity: 1) }
    var textTertiary: Color { self == .daw ? Color(.sRGB, red: 0.651, green: 0.616, blue: 0.722, opacity: 1) : Color(.sRGB, red: 0.722, green: 0.659, blue: 0.596, opacity: 1) }
    var textPlaceholder: Color { self == .daw ? Color(.sRGB, red: 0.604, green: 0.573, blue: 0.671, opacity: 1) : Color(.sRGB, red: 0.659, green: 0.604, blue: 0.549, opacity: 1) }
    var textInactive: Color { self == .daw ? Color(.sRGB, red: 0.894, green: 0.875, blue: 0.941, opacity: 1) : Color(.sRGB, red: 0.941, green: 0.902, blue: 0.863, opacity: 1) }
    var accent: Color { self == .daw ? Color(.sRGB, red: 0.435, green: 0.310, blue: 0.878, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.478, blue: 0.102, opacity: 1) }
    var onAccent: Color { self == .daw ? Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1) : Color(.sRGB, red: 0.122, green: 0.051, blue: 0.000, opacity: 1) }
    var accentSoft: Color { self == .daw ? Color(.sRGB, red: 0.839, green: 0.784, blue: 1.000, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.851, blue: 0.690, opacity: 1) }
    var accentIcon: Color { self == .daw ? Color(.sRGB, red: 0.788, green: 0.714, blue: 1.000, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.780, blue: 0.561, opacity: 1) }
    var accentLine: Color { self == .daw ? Color(.sRGB, red: 0.718, green: 0.612, blue: 1.000, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.690, blue: 0.400, opacity: 1) }
    var accentTile: Color { self == .daw ? Color(.sRGB, red: 0.718, green: 0.612, blue: 1.000, opacity: 0.18) : Color(.sRGB, red: 1.000, green: 0.690, blue: 0.400, opacity: 0.18) }
    var glow1: Color { self == .daw ? Color(.sRGB, red: 0.435, green: 0.310, blue: 0.878, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.478, blue: 0.102, opacity: 1) }
    var glow2: Color { self == .daw ? Color(.sRGB, red: 0.757, green: 0.310, blue: 0.816, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.239, blue: 0.180, opacity: 1) }
    var wave2: Color { self == .daw ? Color(.sRGB, red: 0.898, green: 0.612, blue: 1.000, opacity: 1) : Color(.sRGB, red: 1.000, green: 0.816, blue: 0.541, opacity: 1) }
    var highlight: Color { self == .daw ? Color(.sRGB, red: 0.961, green: 0.941, blue: 0.416, opacity: 1) : Color(.sRGB, red: 0.498, green: 0.831, blue: 1.000, opacity: 1) }
    var highlightFill: Color { self == .daw ? Color(.sRGB, red: 0.961, green: 0.941, blue: 0.416, opacity: 0.16) : Color(.sRGB, red: 0.498, green: 0.831, blue: 1.000, opacity: 0.16) }
    var highlightFillSelected: Color { self == .daw ? Color(.sRGB, red: 0.961, green: 0.941, blue: 0.416, opacity: 0.36) : Color(.sRGB, red: 0.498, green: 0.831, blue: 1.000, opacity: 0.36) }
    var playhead: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1) }
    var switchOff: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 0.24) }
    var knob: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1) }
    var sheetTop: Color { self == .daw ? Color(.sRGB, red: 0.173, green: 0.137, blue: 0.267, opacity: 0.88) : Color(.sRGB, red: 0.243, green: 0.157, blue: 0.094, opacity: 0.88) }
    var sheetBottom: Color { self == .daw ? Color(.sRGB, red: 0.078, green: 0.059, blue: 0.133, opacity: 0.92) : Color(.sRGB, red: 0.118, green: 0.071, blue: 0.039, opacity: 0.92) }
    var menu: Color { self == .daw ? Color(.sRGB, red: 0.157, green: 0.125, blue: 0.243, opacity: 0.97) : Color(.sRGB, red: 0.220, green: 0.141, blue: 0.086, opacity: 0.97) }
    var scrim: Color { self == .daw ? Color(.sRGB, red: 0.016, green: 0.008, blue: 0.039, opacity: 0.58) : Color(.sRGB, red: 0.031, green: 0.016, blue: 0.004, opacity: 0.58) }
    var record: Color { Color(.sRGB, red: 1.000, green: 0.353, blue: 0.322, opacity: 1) }
    var danger: Color { Color(.sRGB, red: 0.816, green: 0.204, blue: 0.227, opacity: 1) }
    var onDanger: Color { Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1) }
    var warningText: Color { Color(.sRGB, red: 1.000, green: 0.847, blue: 0.604, opacity: 1) }
    var warningFill: Color { Color(.sRGB, red: 1.000, green: 0.769, blue: 0.420, opacity: 0.1) }
    var warningBorder: Color { Color(.sRGB, red: 1.000, green: 0.769, blue: 0.420, opacity: 0.25) }
    var statusError: Color { Color(.sRGB, red: 1.000, green: 0.541, blue: 0.478, opacity: 1) }
    var clip: Color { Color(.sRGB, red: 0.741, green: 0.576, blue: 0.890, opacity: 1) }
    var clipInk: Color { Color(.sRGB, red: 0.165, green: 0.086, blue: 0.251, opacity: 1) }
    var clipNote: Color { Color(.sRGB, red: 0.957, green: 0.918, blue: 1.000, opacity: 1) }
}

enum K7Radius {
    static let clip: CGFloat = 9
    static let key: CGFloat = 10
    static let tile: CGFloat = 11
    static let panel: CGFloat = 18
    static let capsule: CGFloat = 22
    static let card: CGFloat = 24
    static let bar: CGFloat = 34
}

enum K7Space {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s40: CGFloat = 40
    static let s64: CGFloat = 64
}

enum K7Size {
    static let touch: CGFloat = 44
    static let bar: CGFloat = 68
    static let barPhone: CGFloat = 64
    static let tab: CGFloat = 112
    static let row: CGFloat = 54
    static let rowList: CGFloat = 72
    static let rowTrack: CGFloat = 52
    static let tile: CGFloat = 42
}
