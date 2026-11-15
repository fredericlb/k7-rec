// The chords tab: the sheet in monospace with its chords coloured, transposed, the sung line highlighted.
import RehearsalText
import SwiftUI

struct ChordsTab: View {
    let text: String
    let semitones: Int
    let active: Int?
    let onTap: (Int) -> Void

    @State private var memo = ParsedMemo()

    var body: some View {
        let (lines, timed) = memo.get(text, semitones) { (SongText.displayLines($0, semitones: $1), Set(LyricsTiming.byLine($0).map(\.line))) }
        FollowedScroll(axes: [.vertical, .horizontal], active: active) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    row(line).fixedSize(horizontal: true, vertical: false).followed(index: i, active: active, timed: timed, onTap: onTap)
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder private func row(_ line: ParsedLine) -> some View {
        switch line {
        case .empty: Text(" ")
        case .section(let label): Text(label).bold().foregroundStyle(.secondary)
        case .chords(let t): Text(t).bold().foregroundStyle(Color.accentColor)
        case .lyrics(let segments): Text(Self.attributed(segments))
        }
    }

    static func attributed(_ segments: [Segment]) -> AttributedString {
        var out = AttributedString()
        for s in segments {
            if let chord = s.chord {
                var c = AttributedString("[\(chord)]")
                c.foregroundColor = .accentColor
                c.font = .system(.body, design: .monospaced).bold()
                out += c
            }
            out += AttributedString(s.text)
        }
        return out
    }
}
