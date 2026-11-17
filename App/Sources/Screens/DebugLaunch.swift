// Debug builds only: launch arguments that open the first song on a tab, play from a second and open the menu.
import Foundation

enum DebugLaunch {
    #if DEBUG
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    static let openFirst = defaults.bool(forKey: "OpenFirstSong")
    static let tab = defaults.string(forKey: "OpenTab").flatMap { SongTab(rawValue: $0) }
    static let seek = defaults.string(forKey: "OpenSeek").flatMap(Double.init)
    static let menu = defaults.bool(forKey: "OpenMenu")
    /// UI tests start from an empty library in a temp folder, so what an earlier run left cannot open first.
    static let freshLibrary = defaults.bool(forKey: "FreshLibrary")
    /// UI tests never reach lrclib.net.
    static let noLyricsLookup = defaults.bool(forKey: "NoLyricsLookup")
    #else
    static let openFirst = false
    static let tab: SongTab? = nil
    static let seek: Double? = nil
    static let menu = false
    static let freshLibrary = false
    static let noLyricsLookup = false
    #endif
}
