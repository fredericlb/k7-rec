// The tab tab: each tab system drawn as a staff (strings, bar lines, frets). Systems with no text between them stand
// side by side while they fit; a wider one scrolls sideways on its own. The header before the first system folds
// away; layout choices are in docs/app.md.
import RehearsalText
import SwiftUI
import UIKit

struct TabTab: View {
    let text: String

    @State private var headerOpen = false
    /// The card's inner width, which a row of systems fills.
    @State private var width: CGFloat = 0
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
        // The scroll view's width, not the card's: the card grows with what it holds, the screen does not.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 - 2 * Metrics(sizeClass).margin - 24 }
    }

    private func nodes(_ list: [TabNode]) -> some View {
        ForEach(Array(SongText.tabBlocks(list).enumerated()), id: \.offset) { _, block in
            switch block {
            case .node(.empty): Color.clear.frame(height: size * 0.7)
            case .node(.section(let label)):
                Text(label.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(k7.accentIcon).padding(.top, 10)
            case .node(.text(let t)):
                Text(t).font(.system(size: size, design: .monospaced)).foregroundStyle(k7.textSecondary).fixedSize(horizontal: false, vertical: true)
            case .node(.system(let system)): staff(system)
            case .systems(let group):
                FlowRows(spacing: size * 2, top: true) { ForEach(Array(group.enumerated()), id: \.offset) { _, system in staff(system) } }
            }
        }
    }

    /// A staff at its own size, or the card's width scrolled sideways when it is wider.
    private func staff(_ system: TabSystem) -> some View {
        let full = TabStaff.size(of: system, size: size)
        return ScrollView(.horizontal) { TabStaff(system: system, size: size) }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(width: width > 0 ? min(full.width, width) : full.width, height: full.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tablature")
            .accessibilityValue(SongText.tabSpoken(system))
    }
}

/// One tab system: a line per string, the bar lines across, each fret or technique cut into its string, and the
/// words written after a string in a column at the staff's right, on that string's line.
struct TabStaff: View {
    let system: TabSystem
    let size: Double

    /// The grid a staff is drawn on: a column's width, a string's height, the label gutter, where the comments start.
    private struct Grid {
        let col, row, pad, gutter, staffEnd, width, height: Double
        init(_ system: TabSystem, _ size: Double) {
            col = UIFont.monospacedSystemFont(ofSize: size, weight: .regular).monoAdvance
            row = 18.0 * size / 13
            pad = row * 0.7
            gutter = col * Double(max(system.strings.map(\.label.count).max() ?? 0, 1)) + col * 1.5
            let note = UIFont.italicSystemFont(ofSize: size)
            let notes = system.comments.map { $0.isEmpty ? 0 : Double(($0 as NSString).size(withAttributes: [.font: note]).width) }.max() ?? 0
            staffEnd = gutter + Double(system.cols) * col + col
            width = staffEnd + (notes > 0 ? col * 2 + notes : 0)
            height = pad * 2 + Double(max(system.strings.count - 1, 0)) * row
        }
    }

    static func size(of system: TabSystem, size: Double) -> CGSize {
        let g = Grid(system, size)
        return CGSize(width: g.width, height: g.height)
    }

    var body: some View {
        let g = Grid(system, size)
        let (col, row, pad, gutter, staffEnd, width, height) = (g.col, g.row, g.pad, g.gutter, g.staffEnd, g.width, g.height)
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
            for (r, comment) in system.comments.enumerated() where !comment.isEmpty {
                context.draw(Text(comment).font(.system(size: size).italic()).foregroundStyle(k7.textSecondary),
                             at: CGPoint(x: staffEnd + col * 2, y: y(r)), anchor: .leading)
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
