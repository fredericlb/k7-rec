// Debug builds only: launch arguments that open a tab, the first song on one of its views, play from a second,
// open the menu or the take panel.
import Foundation

enum DebugLaunch {
    #if DEBUG
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    static let openFirst = defaults.bool(forKey: "OpenFirstSong")
    static let tab = defaults.string(forKey: "OpenTab").flatMap { SongTab(rawValue: $0) }
    static let seek = defaults.string(forKey: "OpenSeek").flatMap(Double.init)
    static let menu = defaults.bool(forKey: "OpenMenu")
    /// The tab in front at launch, and the take panel opened over it, for screenshots.
    static let appTab = defaults.string(forKey: "OpenAppTab").flatMap { AppTab(rawValue: $0) }
    static let recorder = defaults.bool(forKey: "OpenRecorder")
    /// UI tests start from an empty library in a temp folder, so what an earlier run left cannot open first.
    static let freshLibrary = defaults.bool(forKey: "FreshLibrary")
    /// UI tests never reach lrclib.net.
    static let noLyricsLookup = defaults.bool(forKey: "NoLyricsLookup")
    #else
    static let openFirst = false
    static let tab: SongTab? = nil
    static let seek: Double? = nil
    static let menu = false
    static let appTab: AppTab? = nil
    static let recorder = false
    static let freshLibrary = false
    static let noLyricsLookup = false
    #endif
}
