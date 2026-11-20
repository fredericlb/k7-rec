// The highlights and markers a take has kept, each list one card: a highlight plays looped, a marker seeks;
// both rename and delete from a menu.
import SwiftUI

struct SavedMomentRows: View {
    let moments: [SavedMoment]
    let playing: (ClosedRange<TimeInterval>) -> Bool
    let play: (SavedMoment) -> Void
    let rename: (SavedMoment) -> Void
    let delete: (SavedMoment) -> Void

    var body: some View {
        CardRows(items: moments) { m in
            HStack(spacing: 4) {
            Button { play(m) } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 4).fill(k7.highlight).frame(width: 8, height: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.headline)
                        Text("\(clock(m.start)) – \(clock(m.end))").font(.system(size: 14)).foregroundStyle(k7.textSecondary).monospacedDigit()
                    }
                    Spacer()
                    Text(clock(m.end - m.start)).foregroundStyle(k7.textSecondary).monospacedDigit()
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(m.title), \(clock(m.start)) to \(clock(m.end))")
            .accessibilityHint(playing(m.span) ? "Pauses the highlight" : "Plays the highlight in a loop")
            RowMenu(name: "Highlight menu", rename: { rename(m) }, delete: { delete(m) })
            }
            .padding(.leading, K7Space.s20).padding(.trailing, 6)
            .background(playing(m.span) ? k7.highlightFill : .clear)
        }
    }
}

struct PinRows: View {
    let pins: [Pin]
    let seek: (Pin) -> Void
    let rename: (Pin) -> Void
    let delete: (Pin) -> Void

    var body: some View {
        CardRows(items: pins) { p in
            HStack(spacing: 4) {
            Button { seek(p) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "mappin").foregroundStyle(k7.accentSoft).frame(width: 8)
                    Text(p.note).font(.body.weight(.semibold))
                    Spacer()
                    Text(clock(p.at)).monospacedDigit().foregroundStyle(k7.textSecondary)
                }
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowMenu(name: "Marker menu", rename: { rename(p) }, delete: { delete(p) })
            }
            .padding(.leading, K7Space.s20).padding(.trailing, 6)
        }
    }
}

private struct RowMenu: View {
    let name: String
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Menu {
            Button("Rename", systemImage: "pencil", action: rename)
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        } label: { Image(systemName: "ellipsis").foregroundStyle(k7.textSecondary).target() }
            .accessibilityLabel(name)
    }
}
