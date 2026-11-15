// The real media library: the permission, and an `MPMediaItem` seen through the app's protocol.
// What a reader gets wrong: only the simulator lacks a library to pick from; the permission API works there.
import MediaPlayer

@MainActor
final class MediaAuthorizer: MusicAuthorizing {
    var access: MusicAccess { Self.map(MPMediaLibrary.authorizationStatus()) }

    func request() async -> MusicAccess {
        await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: Self.map($0)) } }
    }

    nonisolated static func map(_ s: MPMediaLibraryAuthorizationStatus) -> MusicAccess {
        switch s {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }
}

struct LibraryItem: MediaItemInfo, @unchecked Sendable {
    let item: MPMediaItem
    var itemID: String { String(item.persistentID) }
    var title: String { item.title ?? "" }
    var artist: String { item.artist ?? "" }
    var album: String { item.albumTitle ?? "" }
    var duration: TimeInterval { item.playbackDuration }
    var assetURL: URL? { item.assetURL }
    var hasProtectedAsset: Bool { item.hasProtectedAsset }
    var playbackStoreID: String { item.playbackStoreID }
}
