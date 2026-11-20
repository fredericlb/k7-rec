// The design system's list: rows in one card, a separator inset to the text, and the two-line row that opens something.
import SwiftUI

/// Rows in one rounded card, a hairline between two rows, inset to where the text starts.
struct CardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var separatorInset: CGFloat = K7Space.s20
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(k7.separator).frame(height: 1).padding(.leading, separatorInset) }
                row(item)
            }
        }
        .card()
    }
}

/// A two-line row: something leading (a tile, a play button), the title over the line that tells rows apart,
/// an optional value, and a chevron in the accent.
struct RowLabel<Leading: View>: View {
    let title: String
    let second: String
    var value: String?
    var chevron = true
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: K7Space.s12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if !second.isEmpty { Text(second).font(.system(size: 14)).foregroundStyle(k7.textSecondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).foregroundStyle(k7.textSecondary).monospacedDigit() }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(k7.accentIcon).accessibilityHidden(true)
            }
        }
        .frame(minHeight: K7Size.rowList)
        .contentShape(Rectangle())
    }
}
