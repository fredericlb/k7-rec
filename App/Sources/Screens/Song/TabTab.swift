// The tab tab: each tab system drawn as a staff (strings, bar lines, frets), scrolled sideways on its own.
// The header before the first system folds away; layout choices are in docs/app.md.
import RehearsalText
import SwiftUI
import UIKit

struct TabTab: View {
    let text: String

    @State private var headerOpen = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric private var size = 13.0

    var body: some View {
        let parts = SongText.tabParts(Tablature.parse(text))
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                if !parts.header.isEmpty {
                    Button { headerOpen.toggle() } label: {
                        Label(headerOpen ? "Hide header" : "Show header", systemImage: headerOpen ? "chevron.down" : "chevron.right")
                            .font(.footnote)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    if headerOpen { nodes(parts.header) }
                }
                VStack(alignment: .leading, spacing: 4) { nodes(parts.body) }
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(fill: k7.surfaceSolid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics(sizeClass).margin).padding(.vertical, 6)
        }
    }

    private func nodes(_ list: [TabNode]) -> some View {
        ForEach(Array(list.enumerated()), id: \.offset) { _, node in
            switch node {
            case .empty: Color.clear.frame(height: size * 0.7)
            case .section(let label):
                Text(label.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(k7.accentIcon).padding(.top, 10)
            case .text(let t):
                Text(t).font(.system(size: size, design: .monospaced)).foregroundStyle(k7.textSecondary).fixedSize(horizontal: false, vertical: true)
            case .system(let system):
                ScrollView(.horizontal) { TabStaff(system: system, size: size) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tablature")
                    .accessibilityValue(SongText.tabSpoken(system))
            }
        }
    }
}

/// One tab system: a line per string, the bar lines across, each fret or technique cut into its string.
private struct TabStaff: View {
    let system: TabSystem
    let size: Double

    var body: some View {
        let col = UIFont.monospacedSystemFont(ofSize: size, weight: .regular).monoAdvance
        let row = 18.0 * size / 13
        let pad = row * 0.7
        let gutter = col * Double(max(system.strings.map(\.label.count).max() ?? 0, 1)) + col * 1.5
        let width = gutter + Double(system.cols) * col + col
        let height = pad * 2 + Double(max(system.strings.count - 1, 0)) * row
        Canvas { context, _ in
            let y = { (r: Int) in pad + Double(r) * row }
            let start = gutter + col / 2
            let end = gutter + (Double(system.cols) - 0.5) * col
            for (r, string) in system.strings.enumerated() {
                var from = start
                for e in string.events {
                    let x = gutter + Double(e.col) * col
                    stroke(&context, from: CGPoint(x: from, y: y(r)), to: CGPoint(x: x - 1, y: y(r)), style: k7.text.opacity(0.3))
                    from = x + Double(e.text.utf16.count) * col + 1
                }
                stroke(&context, from: CGPoint(x: from, y: y(r)), to: CGPoint(x: end, y: y(r)), style: k7.text.opacity(0.3))
                context.draw(Text(string.label).font(.system(size: size, weight: .bold, design: .monospaced)).foregroundStyle(k7.accentIcon),
                             at: CGPoint(x: gutter - col * 0.6, y: y(r)), anchor: .trailing)
                for e in string.events {
                    let glyph = e.kind == .fret
                        ? Text(e.text).font(.system(size: size, weight: .bold, design: .monospaced)).foregroundStyle(k7.text)
                        : Text(e.text).font(.system(size: size, design: .monospaced)).foregroundStyle(k7.textSecondary)
                    context.draw(glyph, at: CGPoint(x: gutter + Double(e.col) * col, y: y(r)), anchor: .leading)
                }
            }
            for b in system.bars {
                let x = gutter + Double(b) * col + col / 2
                stroke(&context, from: CGPoint(x: x, y: y(0)), to: CGPoint(x: x, y: y(system.strings.count - 1)), style: k7.text.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
    }

    private func stroke(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, style: some ShapeStyle) {
        guard to.x >= from.x, to.y >= from.y else { return }
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .style(style), lineWidth: 1)
    }
}

private extension UIFont {
    /// The width of one monospaced column, so a character's index in the ASCII is its x.
    var monoAdvance: Double { Double(("0" as NSString).size(withAttributes: [.font: self]).width) }
}
