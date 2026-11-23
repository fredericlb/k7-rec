// The chords tab: the sheet in monospace with its chords coloured, transposed, the sung line highlighted. On iPad
// and the Mac the diagrams stand in a column at its right; on iPhone a tap on a chord shows its diagram.
import RehearsalText
import SwiftUI

struct ChordsTab: View {
    let text: String
    let semitones: Int
    let active: Int?
    let onTap: (Int) -> Void
    /// Whether a chord opens its diagram when tapped: on iPhone, where no column shows them.
    var tappable = false

    @State private var memo = ParsedMemo()
    /// The chord whose diagram is open, by its line and its place in the line.
    @State private var shown: ChordSpot?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var model
    /// The chord sheet's mono size: 13 on iPhone, 17 on iPad and the Mac, with the line heights the design system sets.
    private var size: CGFloat { Metrics(sizeClass).wide ? 17 : 13 }

    var body: some View {
        let (lines, timed) = memo.get(text, semitones) { (SongText.displayLines($0, semitones: $1), Set(LyricsTiming.byLine($0).map(\.line))) }
        FollowedScroll(axes: [.vertical, .horizontal], active: active) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    row(line, i).fixedSize(horizontal: true, vertical: false).followed(index: i, active: active, timed: timed, onTap: onTap)
                }
            }
            .font(.system(size: size, design: .monospaced))
            .lineSpacing(size * 0.6)
            .foregroundStyle(k7.text)
        }
    }

    @ViewBuilder private func row(_ line: ParsedLine, _ i: Int) -> some View {
        switch line {
        case .empty: Text(" ")
        case .section(let label): Text(label).bold().foregroundStyle(k7.textTertiary)
        case .chords(let t) where tappable:
            HStack(spacing: 0) {
                ForEach(Array(SongText.chordRuns(t).enumerated()), id: \.offset) { k, run in
                    if run.chord { chord(run.text, ChordSpot(line: i, place: k)) } else { Text(run.text).bold().foregroundStyle(k7.accentIcon) }
                }
            }
        case .chords(let t): Text(t).bold().foregroundStyle(k7.accentIcon)
        case .lyrics(let segments) where tappable && segments.contains { $0.chord != nil }:
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { k, s in
                    if let c = s.chord { chord(c, ChordSpot(line: i, place: k), bracketed: true) }
                    if !s.text.isEmpty { Text(s.text) }
                }
            }
        case .lyrics(let segments): Text(Self.attributed(segments))
        }
    }

    /// A chord that shows its diagram in a popover pointing at it.
    private func chord(_ symbol: String, _ spot: ChordSpot, bracketed: Bool = false) -> some View {
        Button { shown = spot } label: {
            Text(bracketed ? "[\(symbol)]" : symbol).bold().foregroundStyle(k7.accentIcon)
                .background(shown == spot ? k7.accentTile : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chord \(symbol)")
        .accessibilityHint("Shows its diagram")
        .popover(isPresented: Binding(get: { shown == spot }, set: { if !$0 { shown = nil } })) {
            VStack(spacing: K7Space.s8) {
                InstrumentSwitch()
                DiagramCard(symbol: symbol, cell: 120)
            }
            .padding(.top, K7Space.s12).padding(.horizontal, K7Space.s12)
            .environment(model)
            .presentationCompactAdaptation(.popover)
                .presentationBackground(k7.menu)
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

private struct ChordSpot: Equatable {
    let line: Int
    let place: Int
}
