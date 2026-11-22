// A layout that lays its children out in rows at their own size, wrapping when a row is full: the tag chips,
// the tab systems written with no text between them.
import SwiftUI

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowRows: Layout {
    var spacing: CGFloat
    /// Children sit at the top of their row instead of its middle.
    var top = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: min(rows.map(\.width).max() ?? 0, proposal.width ?? .infinity), height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (top ? 0 : (row.height - size.height) / 2)), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if let last = rows.indices.last, rows[last].width + spacing + size.width <= width {
                rows[last].items.append(i)
                rows[last].width += spacing + size.width
                rows[last].height = max(rows[last].height, size.height)
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
    }
}
