// The system media picker, multi-select; `cloud` also shows tracks that are only streamed.
// What a reader gets wrong: it needs the library permission first, and it returns items, never files.
import MediaPlayer
import SwiftUI

struct MediaPicker: UIViewControllerRepresentable {
    let cloud: Bool
    let onPick: ([any MediaItemInfo]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let p = MPMediaPickerController(mediaTypes: .music)
        p.allowsPickingMultipleItems = true
        p.showsCloudItems = cloud
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }

        func mediaPicker(_ picker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            parent.onPick(collection.items.map { LibraryItem(item: $0) })
        }

        func mediaPickerDidCancel(_ picker: MPMediaPickerController) { parent.onCancel() }
    }
}
