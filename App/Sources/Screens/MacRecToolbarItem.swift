// The Mac's rec button: an item of the window's title bar toolbar, right of the tabs the system puts there.
// The tab bar owns that toolbar's delegate, so this one stands in front of it and forwards (docs/mac.md).
#if targetEnvironment(macCatalyst)
import UIKit

@MainActor
final class MacRecToolbarItem: NSObject, NSToolbarDelegate {
    static let id = NSToolbarItem.Identifier("rehearsal.rec")
    private let model: AppModel
    private weak var original: (any NSToolbarDelegate)?
    private weak var toolbar: NSToolbar?
    private var item: NSToolbarItem?
    private var shown: Int?
    private var timer: Timer?

    init(model: AppModel) { self.model = model }

    /// Joins the window's toolbar once the tab bar has made it, and again if the tab bar ever replaces it.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let bar = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.titlebar?.toolbar }.first
        if let bar, bar !== toolbar || !(bar.delegate === self) { install(on: bar) }
        refresh()
    }

    private func install(on bar: NSToolbar) {
        if !(bar.delegate === self) { original = bar.delegate }
        toolbar = bar
        bar.delegate = self
        if !bar.items.contains(where: { $0.itemIdentifier == Self.id }) {
            bar.insertItem(withItemIdentifier: .flexibleSpace, at: bar.items.count)
            bar.insertItem(withItemIdentifier: Self.id, at: bar.items.count)
        }
    }

    /// Redraws the item only when what it shows changes: idle, or one of 32 LED shades.
    private func refresh() {
        guard let item else { return }
        let state = model.recording ? Int(LevelLED.position(model.recorder.paused ? 0 : model.recorder.level) * 31) : -1
        guard state != shown else { return }
        shown = state
        item.image = state < 0 ? Self.idleImage : Self.led(model.recorder.paused ? 0 : model.recorder.level)
        item.label = state < 0 ? "Record" : "Take running"
        item.toolTip = state < 0 ? "Record a take here" : "Show the take's controls"
    }

    @objc private func tapped() {
        if model.recording { model.recorderOpen = true } else { Task { await model.startTake(song: model.shownSong) } }
    }

    private static let idleImage = UIImage(systemName: "record.circle")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)

    private static func led(_ level: Double) -> UIImage {
        let c = LevelLED.rgb(level)
        return UIGraphicsImageRenderer(size: CGSize(width: 15, height: 15)).image { ctx in
            let rect = CGRect(x: 1, y: 1, width: 13, height: 13)
            UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: rect)
            UIColor.systemRed.setStroke()
            ctx.cgContext.setLineWidth(1.5)
            ctx.cgContext.strokeEllipse(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: NSToolbarDelegate, forwarding all but the rec item to the tab bar's delegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (original?.toolbarDefaultItemIdentifiers?(toolbar) ?? []) + [.flexibleSpace, Self.id]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (original?.toolbarAllowedItemIdentifiers?(toolbar) ?? []) + [.flexibleSpace, Self.id]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.id else { return original?.toolbar?(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: flag) }
        let button = UIBarButtonItem(image: Self.idleImage, style: .plain, target: self, action: #selector(tapped))
        let made = NSToolbarItem(itemIdentifier: id, barButtonItem: button)
        made.isBordered = false
        item = made
        shown = nil
        return made
    }

    func toolbarWillAddItem(_ notification: Notification) { original?.toolbarWillAddItem?(notification) }
    func toolbarDidRemoveItem(_ notification: Notification) { original?.toolbarDidRemoveItem?(notification) }

    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
    override func forwardingTarget(for selector: Selector!) -> Any? { original }
}
#endif
