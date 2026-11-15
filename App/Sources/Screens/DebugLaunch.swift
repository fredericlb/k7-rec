// Debug builds only: launch arguments that open the first song on a tab, play from a second and open the menu.
import Foundation

enum DebugLaunch {
    #if DEBUG
    private static let defaults = UserDefaults.standard
    static let openFirst = defaults.bool(forKey: "OpenFirstSong")
    static let tab = defaults.string(forKey: "OpenTab").flatMap { SongTab(rawValue: $0) }
    static let seek = defaults.string(forKey: "OpenSeek").flatMap(Double.init)
    static let menu = defaults.bool(forKey: "OpenMenu")
    #else
    static let openFirst = false
    static let tab: SongTab? = nil
    static let seek: Double? = nil
    static let menu = false
    #endif
}
