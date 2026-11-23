// The sheets tab: the song's sheets as chips in the sidecar's order, the picked one shown zoomable, add and remove;
// the expand button shows the picked sheet full screen.
// What a reader gets wrong: a lone sheet has no chips; its buttons float over it and another is added from the song menu.
import PDFKit
import SwiftUI

struct SheetsTab: View {
    @Environment(AppModel.self) private var model
    let song: Song
    /// Asks for another sheet, through the song screen's one file importer.
    let add: () -> Void
    @State private var pickedID: String?
    @State private var confirmRemove = false
    @State private var fullScreen = false
    private var picked: SongSheet? { song.sheets.first { $0.id == pickedID } ?? song.sheets.first }

    var body: some View {
        VStack(spacing: 0) {
            if !lone {
                HStack(spacing: 0) {
                    chips
                    if picked != nil { expandButton.buttonStyle(.borderless).padding(.trailing) }
                }
                Divider()
            }
            if let sheet = picked {
                SheetViewer(url: sheet.url).id(sheet.id)
                    .overlay(alignment: .topTrailing) {
                        if lone {
                            HStack {
                                Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash").target() }
                                    .accessibilityLabel("Remove the sheet")
                                expandButton
                            }
                            .buttonStyle(.glass).padding()
                        }
                    }
            } else {
                ContentUnavailableView("No sheets", systemImage: "doc", description: Text("Add one with the + button."))
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            if let sheet = picked { FullScreenSheet(sheet: sheet) { fullScreen = false }.environment(model) }
        }
        .confirmationDialog("Remove this sheet?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let sheet = picked { Task { if let failure = await model.library.removeSheet(sheet, from: song) { model.notice = failure } } }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(song.sheets) { sheet in
                    Button(sheet.name) { pickedID = sheet.id }
                        .buttonStyle(.bordered).tint(sheet.id == picked?.id ? .accentColor : .secondary)
                }
                Button(action: add) { Image(systemName: "plus").frame(minWidth: 30, minHeight: 30) }
                    .buttonStyle(.bordered).tint(.secondary)
                    .accessibilityLabel("Add a sheet")
                if picked != nil {
                    Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
    }

    /// One sheet alone needs no chips to pick it.
    private var lone: Bool { song.sheets.count == 1 }

    private var expandButton: some View {
        Button { fullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").target() }
            .accessibilityLabel("Full screen").accessibilityIdentifier("sheetFullScreen")
    }
}

/// One sheet over the whole screen, with a button that shrinks it back.
private struct FullScreenSheet: View {
    let sheet: SongSheet
    let close: () -> Void

    var body: some View {
        SheetViewer(url: sheet.url).id(sheet.id).ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .topTrailing) {
                Button(action: close) { Image(systemName: "arrow.down.right.and.arrow.up.left").target() }
                    .buttonStyle(.glass).padding()
                    .accessibilityLabel("Exit full screen").accessibilityIdentifier("sheetExitFullScreen")
            }
    }
}

/// A PDF through PDFKit, a MusicXML score through Verovio, an image in a zooming scroll view; the kind is told by the file's extension.
struct SheetViewer: View {
    let url: URL

    var body: some View {
        switch SheetKind(url: url) {
        case .pdf: PDFSheet(url: url)
        case .score: ScoreSheet(url: url)
        case .image: ZoomableImage(url: url)
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
