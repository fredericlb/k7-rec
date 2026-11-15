// The system media picker, multi-select; `cloud` also shows tracks that are only streamed.
// What a reader gets wrong: it needs the library permission first, and it returns items, never files.
import MediaPlayer
import SwiftUI

struct MediaPicker: UIViewControllerRepresentable {
    let cloud: Bool
    let onPick: @MainActor ([any MediaItemInfo]) -> Void
    let onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let p = MPMediaPickerController(mediaTypes: .music)
        p.allowsPickingMultipleItems = true
        p.showsCloudItems = cloud
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: @MainActor ([any MediaItemInfo]) -> Void
        let onCancel: @MainActor () -> Void
        init(onPick: @escaping @MainActor ([any MediaItemInfo]) -> Void, onCancel: @escaping @MainActor () -> Void) {
            (self.onPick, self.onCancel) = (onPick, onCancel)
        }

        func mediaPicker(_ picker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            let items = collection.items.map { LibraryItem(item: $0) }
            let pick = onPick
            MainActor.assumeIsolated { pick(items) }
        }

        func mediaPickerDidCancel(_ picker: MPMediaPickerController) {
            let cancel = onCancel
            MainActor.assumeIsolated { cancel() }
        }
    }
}
