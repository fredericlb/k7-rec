// Three tabs under one floating Liquid Glass bar with the rec button beside it, the same on iPhone, iPad
// and Mac; the take panel opens over them. Choices in docs/app.md, "Screens".
import SwiftUI

enum AppTab: String, CaseIterable {
    case songs = "Songs", takes = "Takes", settings = "Settings"

    var symbol: String {
        switch self {
        case .songs: "music.note"
        case .takes: "waveform"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = DebugLaunch.appTab ?? .songs
    /// Bumped when the tab in front is picked again, which takes that tab back to its list.
    @State private var resets: [AppTab: Int] = [:]
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        ZStack {
            // Every tab stays alive behind the one in front, so its pages and scroll survive a switch.
            ForEach(AppTab.allCases, id: \.self) { t in
                screen(t).id(resets[t, default: 0])
                    .opacity(t == tab ? 1 : 0)
                    .allowsHitTesting(t == tab)
                    .accessibilityHidden(t != tab)
            }
        }
        .background(TopGap(points: metrics.top))
        .safeAreaInset(edge: .bottom) { TabBar(tab: tab, pick: pick).padding(.top, 8).padding(.bottom, metrics.wide ? 16 : 0) }
        .background(Backdrop())
        .preferredColorScheme(.dark)
        .onAppear { model.songsInFront = tab == .songs; if DebugLaunch.recorder { model.recorderOpen = true } }
        .onChange(of: model.stoppedTake) { _, id in
            // A stopped take opens on its page: the Takes tab comes forward, which pushes it.
            guard id != nil, tab != .takes else { return }
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15)) { tab = .takes }
            model.songsInFront = false
        }
        .onChange(of: model.sharedSong) { _, id in
            // A song shared from another app opens on its page: the Songs tab comes forward, which pushes it.
            guard id != nil, tab != .songs else { return }
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15)) { tab = .songs }
            model.songsInFront = true
        }
        .sheet(isPresented: Bindable(model).recorderOpen) { RecordingScreen().environment(model) }
        .alert("K7 REC", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
    }

    @ViewBuilder private func screen(_ t: AppTab) -> some View {
        switch t {
        case .songs: SongsScreen()
        case .takes: TakesScreen()
        case .settings: SettingsScreen()
        }
    }

    private func pick(_ t: AppTab) {
        if t == tab { resets[t, default: 0] += 1; return }
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.15)) { tab = t }
        model.songsInFront = t == .songs
    }
}

/// The capsule of tabs, a lozenge sliding to the one in front, and the round rec button, merged as one glass.
struct TabBar: View {
    let tab: AppTab
    let pick: (AppTab) -> Void
    @Namespace private var lozenge
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        GlassEffectContainer(spacing: K7Space.s12) {
            HStack(spacing: K7Space.s12) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { t in item(t) }
                }
                .padding(K7Space.s4)
                .glassEffect(.regular.interactive(), in: .capsule)
                RecButton(size: metrics.bar)
            }
        }
    }

    private func item(_ t: AppTab) -> some View {
        Button { pick(t) } label: {
            VStack(spacing: 2) {
                Image(systemName: t.symbol).font(.system(size: 21)).frame(height: 24)
                Text(t.rawValue).font(.system(size: 11, weight: .semibold))
            }
            .frame(width: metrics.tab, height: metrics.bar - 2 * K7Space.s4)
            .foregroundStyle(t == tab ? k7.accentSoft : k7.textInactive)
            .background {
                if t == tab {
                    Capsule().fill(k7.fillSelected).matchedGeometryEffect(id: "lozenge", in: lozenge)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.rawValue)
        .accessibilityAddTraits(t == tab ? .isSelected : [])
    }
}

/// Lowers every navigation bar by the design's gap under the status bar. The bars are placed from the window's
/// safe area, which SwiftUI's padding does not move, so the gap is the root controller's extra top inset.
private struct TopGap: UIViewRepresentable {
    let points: CGFloat

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.points = points; view.apply() }

    final class Probe: UIView {
        var points: CGFloat = 0
        override func didMoveToWindow() { super.didMoveToWindow(); apply() }
        func apply() {
            guard let root = window?.rootViewController, root.additionalSafeAreaInsets.top != points else { return }
            root.additionalSafeAreaInsets.top = points
        }
    }
}
