// The tab tab: ASCII tablature drawn monospaced on one column grid, scrolled sideways, never wrapped.
import RehearsalText
import SwiftUI

struct TabTab: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) { ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Tablature.parse(text).enumerated()), id: \.offset) { _, node in
                    switch node {
                    case .empty: Text(" ")
                    case .section(let label): Text(label).bold().foregroundStyle(.secondary)
                    case .text(let t): Text(t).fixedSize().foregroundStyle(.secondary)
                    case .system(let system):
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(SongText.gridRows(system).enumerated()), id: \.offset) { _, row in Text(row).fixedSize() }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding()
        } }
    }
}
