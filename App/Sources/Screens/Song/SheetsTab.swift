// The sheets tab: the song's sheets as chips in the sidecar's order, the picked one shown zoomable, add and remove.
import PDFKit
import SwiftUI

struct SheetsTab: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var pickedID: String?
    @State private var confirmRemove = false
    private var picked: SongSheet? { song.sheets.first { $0.id == pickedID } ?? song.sheets.first }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(song.sheets) { sheet in
                        Button(sheet.name) { pickedID = sheet.id }
                            .buttonStyle(.bordered).tint(sheet.id == picked?.id ? .accentColor : .secondary)
                    }
                    if picked != nil {
                        Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }.buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
            }
            Divider()
            if let sheet = picked {
                SheetViewer(url: sheet.url).id(sheet.id)
            } else {
                ContentUnavailableView("No sheets", systemImage: "doc", description: Text("Add one from the song menu."))
            }
        }
        .confirmationDialog("Remove this sheet?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let sheet = picked { Task { if let failure = await model.library.removeSheet(sheet, from: song) { model.notice = failure } } }
            }
        }
    }
}

/// A PDF through PDFKit, an image in a zooming scroll view; the kind is told by the file's extension.
struct SheetViewer: View {
    let url: URL

    var body: some View {
        if url.pathExtension.lowercased() == "pdf" {
            PDFSheet(url: url)
        } else {
            ZoomableImage(url: url)
        }
    }
}

private struct PDFSheet: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

private struct ZoomableImage: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.delegate = context.coordinator
        let image = UIImageView()
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(image)
        // The content is pinned to the scrolling guide and at least the frame's size, so a zoomed image pans to its edges.
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            image.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            image.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            image.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            image.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.image = image
        let file = url
        Task { image.image = await Task.detached { SheetImage.load(file) }.value }
        return scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var image: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    }
}
