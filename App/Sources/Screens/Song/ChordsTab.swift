// The chords tab: the sheet in monospace with its chords coloured, transposed, the sung line highlighted.
import RehearsalText
import SwiftUI

struct ChordsTab: View {
    let text: String
    let semitones: Int
    let active: Int?
    let onTap: (Int) -> Void

    @State private var memo = ParsedMemo()
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The chord sheet's mono size: 13 on iPhone, 17 on iPad and the Mac, with the line heights the design system sets.
    private var size: CGFloat { Metrics(sizeClass).wide ? 17 : 13 }

    var body: some View {
        let (lines, timed) = memo.get(text, semitones) { (SongText.displayLines($0, semitones: $1), Set(LyricsTiming.byLine($0).map(\.line))) }
        FollowedScroll(axes: [.vertical, .horizontal], active: active) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    row(line).fixedSize(horizontal: true, vertical: false).followed(index: i, active: active, timed: timed, onTap: onTap)
                }
            }
            .font(.system(size: size, design: .monospaced))
            .lineSpacing(size * 0.6)
            .foregroundStyle(k7.text)
        }
    }

    @ViewBuilder private func row(_ line: ParsedLine) -> some View {
        switch line {
        case .empty: Text(" ")
        case .section(let label): Text(label).bold().foregroundStyle(k7.textTertiary)
        case .chords(let t): Text(t).bold().foregroundStyle(k7.accentIcon)
        case .lyrics(let segments): Text(Self.attributed(segments))
        }
    }

    static func attributed(_ segments: [Segment]) -> AttributedString {
        var out = AttributedString()
        for s in segments {
            if let chord = s.chord {
                var c = AttributedString("[\(chord)]")
                c.foregroundColor = k7.accentIcon
                c.inlinePresentationIntent = .stronglyEmphasized
                out += c
            }
            out += AttributedString(s.text)
        }
        return out
    }
}
