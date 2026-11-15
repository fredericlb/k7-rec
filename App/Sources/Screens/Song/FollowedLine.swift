// A line of a text tab: highlighted while it is the one sung, and tappable when it carries a time.
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
            ScrollView(axes) { content.padding() }
                .onChange(of: active) { _, line in
                    if let line { withAnimation { proxy.scrollTo(line, anchor: .center) } }
                }
        }
    }
}
