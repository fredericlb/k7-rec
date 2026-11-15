// What a media-library item becomes here: an exported file, a playable reference, or nothing.
// What a reader gets wrong: `hasProtectedAsset` and a nil `assetURL` both mean the sound is unreadable (docs/app.md).
import Foundation
import RehearsalStore

/// The part of an `MPMediaItem` the app reads, so a test can stand in for the library.
protocol MediaItemInfo: Sendable {
    var itemID: String { get }
    var title: String { get }
    var artist: String { get }
    var album: String { get }
    var duration: TimeInterval { get }
    var assetURL: URL? { get }
    var hasProtectedAsset: Bool { get }
    var playbackStoreID: String { get }
}

enum AppleMusicPlan: Equatable {
    case exportFile
    case reference(storeID: String)
    case skip(String)
}

enum MusicAccess: Equatable {
    case notDetermined, denied, restricted, authorized
}

@MainActor
protocol MusicAuthorizing: AnyObject {
    var access: MusicAccess { get }
    func request() async -> MusicAccess
}

@MainActor
final class FakeMusicAuthorizer: MusicAuthorizing {
    var access: MusicAccess
    private let answer: MusicAccess
    init(access: MusicAccess = .notDetermined, answer: MusicAccess = .authorized) { (self.access, self.answer) = (access, answer) }
    func request() async -> MusicAccess { access = answer; return access }
}

enum AppleMusic {
    static func plan(for item: some MediaItemInfo) -> AppleMusicPlan {
        if item.assetURL != nil, !item.hasProtectedAsset { return .exportFile }
        if !item.playbackStoreID.isEmpty { return .reference(storeID: item.playbackStoreID) }
        return .skip("\(label(item)) has no readable file and no Apple Music id.")
    }

    /// The uuid a song made from `item` carries, so picking the item again finds its row.
    static func uuid(of item: some MediaItemInfo) -> String { "apple:" + item.itemID }

    /// The song row for `item`; `id` is kept when the item was imported before.
    static func row(for item: some MediaItemInfo, plan: AppleMusicPlan, id: String = newID(), createdAt: Double = Date().timeIntervalSince1970, folder: String = "") -> RehearsalStore.Song {
        var storeID = ""
        if case .reference(let s) = plan { storeID = s }
        return RehearsalStore.Song(
            id: id, uuid: uuid(of: item), title: item.title.isEmpty ? "Untitled" : item.title, artist: item.artist,
            createdAt: createdAt, source: storeID.isEmpty ? .file : .appleMusicReference, storeId: storeID, folder: folder)
    }

    /// The folder under the songs folder that holds what is made for `item`: its title and the end of its id.
    static func folderName(for item: some MediaItemInfo) -> String {
        SongImporter.safe(item.title.isEmpty ? "Untitled" : item.title) + " " + String(item.itemID.suffix(8))
    }

    /// What to tell the person when the library is not open to the app; nil when it is.
    static func refusal(_ access: MusicAccess) -> String? {
        switch access {
        case .authorized: nil
        case .restricted: "Apple Music is restricted on this device, so Rehearsal cannot read it."
        case .denied: "Apple Music access is off. Allow it in Settings."
        case .notDetermined: "Apple Music access was not given."
        }
    }

    static func label(_ item: some MediaItemInfo) -> String { item.title.isEmpty ? "An item" : "\u{201C}\(item.title)\u{201D}" }
}
