// The strip over the Songs list while Apple Music items are exported; Cancel keeps what is already filed.
import SwiftUI

struct ImportProgress: View {
    @Environment(AppModel.self) private var model
    let progress: AppleMusicProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Importing \(progress.index + 1) of \(progress.total)").font(.caption).foregroundStyle(.secondary)
            Text(progress.title).font(.subheadline).lineLimit(1)
            HStack {
                ProgressView(value: progress.fraction).accessibilityIdentifier("musicProgress")
                Button("Cancel") { model.appleMusic.cancel() }
            }
        }
        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
    }
}
