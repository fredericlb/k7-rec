// The K7 design system applied to the app: the Rec theme, the platform sizes, the header with the logo, cards,
// wells, the empty state (the backdrop is Backdrop.swift). Values come from K7Tokens.swift; docs/app.md, "Look".
import SwiftUI

/// The app's one theme: the design system's Rec theme, orange on warm black.
let k7 = K7Theme.rec

/// What changes between iPhone and the wide layouts (iPad, and the Mac, which is the iPad layout in a window).
struct Metrics {
    let wide: Bool
    init(_ sizeClass: UserInterfaceSizeClass?) { wide = sizeClass == .regular }

    var margin: CGFloat {
        #if targetEnvironment(macCatalyst)
        K7Space.s64
        #else
        wide ? K7Space.s40 : K7Space.s16
        #endif
    }
    /// The gap between the status bar (or the Mac's title bar) and the header, as the design's screens leave it.
    var top: CGFloat {
        #if targetEnvironment(macCatalyst)
        28
        #else
        wide ? 22 : 10
        #endif
    }
    var bar: CGFloat { wide ? K7Size.bar : K7Size.barPhone }
    var tab: CGFloat { wide ? K7Size.tab : 86 }
    /// A waveform well's height: the song's, the take's or the live input's, about 30% shorter on iPhone.
    func well(_ full: CGFloat) -> CGFloat { wide ? full : (full * 0.7).rounded() }
}

extension View {
    /// A screen of a navigation stack: see-through, so the one backdrop behind the tabs shows (Backdrop.swift).
    func screenBackground() -> some View {
        scrollContentBackground(.hidden)
            .containerBackground(Color.clear, for: .navigation)
    }

    /// The dense top bar of every screen: the K7 REC mark, the title and its subtitle, after the back button if any.
    func k7Header(_ title: String, subtitle: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HeaderTitle(title: title, subtitle: subtitle) }
                    .sharedBackgroundVisibility(.hidden)
            }
    }

    /// The recessed well a waveform is drawn in.
    func waveWell() -> some View {
        background(k7.well, in: RoundedRectangle(cornerRadius: K7Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: K7Radius.panel).strokeBorder(k7.wellBorder))
            .clipShape(RoundedRectangle(cornerRadius: K7Radius.panel))
    }

    /// A card on the ground: lists, settings, chord diagrams.
    func card(radius: CGFloat = K7Radius.card, fill: Color = k7.surfaceCard) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(k7.hairlineCard))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    /// A quiet control inside a card or a sheet, where glass would stack on glass.
    func fillControl<S: Shape>(_ shape: S = Capsule()) -> some View {
        background(k7.fillControl, in: shape)
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }
}

private struct HeaderTitle: View {
    let title: String
    let subtitle: String
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: K7Space.s12) {
            Image("K7Rec").resizable().scaledToFit().frame(height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.2).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 14)).foregroundStyle(k7.textSecondary).lineLimit(1) }
            }
            // The bar gives a leading item its ideal width, so a long title is capped here to leave room for the actions.
            .frame(maxWidth: Metrics(sizeClass).wide ? 460 : 170, alignment: .leading)
        }
        .fixedSize()
    }
}

/// A card's label: small, uppercase, in the secondary colour, inset like the rows below it.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.4).foregroundStyle(k7.textSecondary)
            .padding(.leading, K7Space.s20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The note under a card: what the setting does, in one or two sentences.
struct CardNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(k7.textSecondary).padding(.horizontal, K7Space.s20)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 42 pt rounded square that starts a list row.
struct IconTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(k7.accentIcon)
            .frame(width: K7Size.tile, height: K7Size.tile)
            .background(k7.accentTile, in: RoundedRectangle(cornerRadius: K7Radius.tile))
            .accessibilityHidden(true)
    }
}

/// What a list or a panel shows when it has nothing: a disc, the situation, one sentence (300 pt wide at most on
/// iPhone, 480 on iPad and the Mac), maybe one action.
struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    var sentence: String?
    @ViewBuilder var action: Action
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(k7.accentIcon)
                .frame(width: 76, height: 76).background(k7.accentTile, in: Circle()).accessibilityHidden(true)
            Text(title).font(.system(size: 22, weight: .bold)).tracking(-0.2)
            if let sentence {
                Text(sentence).font(.system(size: 16)).foregroundStyle(k7.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics(sizeClass).wide ? 480 : 300)
            }
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Action == EmptyView {
    init(symbol: String, title: String, sentence: String? = nil) {
        self.init(symbol: symbol, title: title, sentence: sentence) { EmptyView() }
    }
}
