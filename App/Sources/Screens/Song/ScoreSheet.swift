// A MusicXML sheet: Verovio draws it in a web view, the score player plays its MIDI with the sounding
// notes lit, and floating controls play, pick a part, transpose and zoom (docs/score.md).
import SwiftUI
import WebKit

struct ScoreSheet: View {
    @Environment(AppModel.self) private var model
    let url: URL
    @State private var engine = ScoreEngine()
    @State private var whole: String?
    @State private var parts: [MusicXML.Part] = []
    /// The part drawn alone, nil for all of them.
    @State private var part: Int?
    @State private var transpose = 0
    @State private var scale: Double?
    @State private var failure: String?

    static let zoomSteps: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static let transposeRange = -12...12
    private var playing: Bool { model.scorePlayer.isPlaying && engine.ready }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                ScoreWebView(engine: engine)
                if let failure {
                    ContentUnavailableView("This score cannot be drawn", systemImage: "music.note.list", description: Text(failure))
                        .background(Color(.systemBackground))
                } else if !engine.drawn {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if failure == nil { controls }
            }
            .onAppear { if scale == nil { scale = Self.openingScale(width: geo.size.width) } }
        }
        .task { await open() }
        .task(id: playing) { await follow() }
        .onChange(of: engine.ready) { engrave() }
        .onChange(of: part) { engrave() }
        .onChange(of: transpose) { engrave() }
        .onChange(of: scale) { if let scale { engine.redraw(scale: scale) } }
        .onDisappear { model.scorePlayer.unload() }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { play() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").target() }
                .accessibilityLabel(playing ? "Pause score" : "Play score")
                .disabled(engine.midi == nil)
            if parts.count > 1 {
                Menu {
                    Picker("Part", selection: $part) {
                        Text("All").tag(Int?.none)
                        ForEach(parts.indices, id: \.self) { Text(parts[$0].name).tag(Int?.some($0)) }
                    }
                } label: { Image(systemName: "person.2").target() }
                    .accessibilityLabel("Part")
            }
            Button { transpose = max(transpose - 1, Self.transposeRange.lowerBound) } label: { Image(systemName: "minus").target() }
                .accessibilityLabel("Transpose down")
            Text(Self.formatTranspose(transpose)).monospacedDigit().frame(minWidth: 28)
                .accessibilityLabel("Transposition \(transpose) semitones")
            Button { transpose = min(transpose + 1, Self.transposeRange.upperBound) } label: { Image(systemName: "plus").target() }
                .accessibilityLabel("Transpose up")
            Button { scale = Self.step(scale ?? 1, by: -1) } label: { Image(systemName: "minus.magnifyingglass").target() }
                .accessibilityLabel("Zoom out")
            Button { scale = Self.step(scale ?? 1, by: 1) } label: { Image(systemName: "plus.magnifyingglass").target() }
                .accessibilityLabel("Zoom in")
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
    }

    private func open() async {
        let file = url
        let read = await Task.detached { () -> Result<String, Error> in
            Result { try MusicXML.text(of: Data(contentsOf: file)) }
        }.value
        switch read {
        case .success(let text): whole = text; parts = MusicXML.parts(of: text); engrave()
        case .failure(let error): failure = error.localizedDescription
        }
    }

    private func engrave() {
        guard let whole, engine.ready else { return }
        let shown = part.map { MusicXML.keepPart(whole, index: $0) } ?? whole
        engine.engrave(whole: whole, shown: shown, transpose: transpose, scale: scale ?? 1) { midi in
            do { try model.scorePlayer.load(midi: midi) } catch { failure = error.localizedDescription }
        } failed: { failure = $0 }
        engine.onSeek = { model.scorePlayer.seek(to: $0) }
    }

    private func play() {
        if !model.scorePlayer.isPlaying, model.player.isPlaying { model.player.toggle() }
        model.scorePlayer.toggle()
    }

    /// Lights the sounding notes while the score plays, about thirty times a second.
    private func follow() async {
        guard playing else { engine.clear(); return }
        while !Task.isCancelled, model.scorePlayer.isPlaying {
            engine.light(seconds: model.scorePlayer.position)
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Half a phone's width reads a line, three quarters a tablet's, and a wider screen opens whole.
    static func openingScale(width: CGFloat) -> Double { width < 640 ? 0.5 : width < 1025 ? 0.75 : 1 }

    /// The next zoom step in a direction, staying on the ladder even from a value off it.
    static func step(_ current: Double, by dir: Int) -> Double {
        dir > 0 ? zoomSteps.first { $0 > current + 1e-9 } ?? zoomSteps.last! : zoomSteps.last { $0 < current - 1e-9 } ?? zoomSteps[0]
    }

    /// A shift as a musician reads it: 0, ♯2, ♭3.
    static func formatTranspose(_ n: Int) -> String { n == 0 ? "0" : (n > 0 ? "♯" : "♭") + "\(abs(n))" }
}

/// The web view and the page's script; it holds the state the page reports.
@Observable @MainActor
final class ScoreEngine: NSObject, WKScriptMessageHandler {
    private(set) var ready = false
    private(set) var drawn = false
    private(set) var midi: Data?
    @ObservationIgnored var onSeek: ((TimeInterval) -> Void)?
    @ObservationIgnored private var onEngraved: ((Data) -> Void)?
    @ObservationIgnored private var onFailed: ((String) -> Void)?
    @ObservationIgnored private(set) lazy var webView: WKWebView = makeWebView()

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakHandler(self), name: "score")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        if let page = Bundle.main.url(forResource: "score", withExtension: "html") {
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return view
    }

    func engrave(whole: String, shown: String, transpose: Int, scale: Double,
                 loaded: @escaping (Data) -> Void, failed: @escaping (String) -> Void) {
        onEngraved = loaded
        onFailed = failed
        drawn = false
        let args: [String: Any] = ["whole": whole, "shown": shown, "transpose": transpose, "scale": scale]
        webView.callAsyncJavaScript("k7.engrave(args)", arguments: ["args": args], in: nil, in: .page)
    }

    func redraw(scale: Double) { run("k7.redraw(\(scale))") }
    func light(seconds: TimeInterval) { run("k7.light(\(Int(seconds * 1000)))") }
    func clear() { run("k7.clear()") }

    private func run(_ script: String) {
        guard ready else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready": ready = true
        case "engraved":
            drawn = true
            guard let base64 = body["midi"] as? String, let data = Data(base64Encoded: base64) else { return }
            midi = data
            onEngraved?(data)
        case "seek": if let ms = body["ms"] as? Double { onSeek?(ms / 1000) }
        case "error": drawn = true; onFailed?(body["message"] as? String ?? "Verovio could not read this score.")
        default: break
        }
    }
}

/// The content controller keeps its handler strongly; this keeps the engine weakly, so the page does not hold it.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: ScoreEngine?
    init(_ target: ScoreEngine) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.userContentController(controller, didReceive: message) }
    }
}

private struct ScoreWebView: UIViewRepresentable {
    let engine: ScoreEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
