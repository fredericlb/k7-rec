// The lyrics tab: the words without their timecodes, the sung line highlighted, a tap on a timed line seeks there.
import RehearsalText
import SwiftUI

struct LyricsTab: View {
    let text: String
    let active: Int?
    let onTap: (Int) -> Void

    @State private var memo = ParsedMemo()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let (lines, timed) = memo.get(text, 0) { t, _ in (ChordSheet.parse(t), Set(LyricsTiming.byLine(t).map(\.line))) }
        FollowedScroll(active: active) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    row(line).followed(index: i, active: active, timed: timed, onTap: onTap)
                }
            }
        }
    }

    @ViewBuilder private func row(_ line: ParsedLine) -> some View {
        switch line {
        case .empty: Text(" ")
        case .section(let label): Text(label).font(.subheadline.bold()).foregroundStyle(k7.textTertiary)
        case .chords: EmptyView()
        case .lyrics(let segments): Text(segments.map(\.text).joined())
            .font(Metrics(sizeClass).wide ? .system(size: 22, weight: .bold) : .system(size: 19, weight: .semibold))
            .lineSpacing(Metrics(sizeClass).wide ? 6 : 11)
        }
    }
}
