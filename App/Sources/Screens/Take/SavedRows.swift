// The moments and pins a take has kept: a moment plays looped, a pin seeks; both rename and delete from a menu.
import SwiftUI

struct SavedMomentRows: View {
    let moments: [SavedMoment]
    let playing: (ClosedRange<TimeInterval>) -> Bool
    let play: (SavedMoment) -> Void
    let rename: (SavedMoment) -> Void
    let delete: (SavedMoment) -> Void

    var body: some View {
        ForEach(moments) { m in
            HStack {
                Button { play(m) } label: {
                    Image(systemName: playing(m.span) ? "pause.fill" : "repeat").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(playing(m.span) ? "Pause moment" : "Play moment in a loop")
                VStack(alignment: .leading) {
                    Text(m.title)
                    Text("\(clock(m.start)) to \(clock(m.end))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Menu {
                    Button("Rename", systemImage: "pencil") { rename(m) }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(m) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Moment menu")
            }
        }
    }
}

struct PinRows: View {
    let pins: [Pin]
    let seek: (Pin) -> Void
    let rename: (Pin) -> Void
    let delete: (Pin) -> Void

    var body: some View {
        ForEach(pins) { p in
            HStack {
                Button { seek(p) } label: {
                    Label(p.note, systemImage: "mappin").frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(clock(p.at)).monospacedDigit().foregroundStyle(.secondary)
                Menu {
                    Button("Rename", systemImage: "pencil") { rename(p) }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(p) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Marker menu")
            }
        }
    }
}
