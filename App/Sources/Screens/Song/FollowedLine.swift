// A line of a text tab: highlighted while it is the one sung, and tappable when it carries a time.
import RehearsalText
import SwiftUI

extension View {
    func followed(index: Int, active: Int?, timed: Set<Int>, onTap: @escaping (Int) -> Void) -> some View {
        self
            .padding(.vertical, 2).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active == index ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { if timed.contains(index) { onTap(index) } }
            .id(index)
    }
}

/// A scrolling column of lines that keeps the sung one in view.
struct FollowedScroll<Content: View>: View {
    var axes: Axis.Set = .vertical
    var active: Int?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // A two-axis ScrollView centres short content, so the sideways scroll is nested.
                if axes.contains(.horizontal) { ScrollView(.horizontal) { content.padding() } } else { content.padding() }
            }
                .onChange(of: active) { _, line in
                    if let line { withAnimation { proxy.scrollTo(max(line - 3, 0), anchor: .topLeading) } }
                }
        }
    }
}

/// The parsed lines of one text and its timed line numbers, parsed again only when the text or the transposition changes.
final class ParsedMemo {
    typealias Value = (lines: [ParsedLine], timed: Set<Int>)
    private var key: (text: String, semitones: Int)?
    private var value: Value = ([], [])
    private(set) var parses = 0

    func get(_ text: String, _ semitones: Int, parse: (String, Int) -> Value) -> Value {
        if let key, key.text == text, key.semitones == semitones { return value }
        parses += 1
        value = parse(text, semitones)
        key = (text, semitones)
        return value
    }
}
