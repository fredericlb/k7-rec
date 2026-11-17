// The reader's habits: a transposition kept per song and the lyrics lead, in UserDefaults.
// What a reader gets wrong: the lead is the reader's, not the song's, so it lives in no song row.
import Foundation
import Observation

@Observable @MainActor
final class SongPrefs {
    static let defaultLead = 1.0
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var transposes: [String: Int]
    /// The songs that play their instrumental version, the reader's choice per song.
    private(set) var instrumentals: Set<String>
    /// The take's input may be a Bluetooth headset's microphone, at the price of narrowband sound.
    var headsetInput: Bool { didSet { defaults.set(headsetInput, forKey: "headsetInput") } }
    var lyricsLead: Double { didSet { defaults.set(lyricsLead, forKey: "lyricsLead") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transposes = defaults.dictionary(forKey: "songTranspose") as? [String: Int] ?? [:]
        instrumentals = Set(defaults.stringArray(forKey: "songInstrumental") ?? [])
        headsetInput = defaults.bool(forKey: "headsetInput")
        lyricsLead = defaults.object(forKey: "lyricsLead") as? Double ?? Self.defaultLead
    }

    func isInstrumental(_ songID: String) -> Bool { instrumentals.contains(songID) }

    func setInstrumental(_ on: Bool, for songID: String) {
        if on { instrumentals.insert(songID) } else { instrumentals.remove(songID) }
        defaults.set(Array(instrumentals), forKey: "songInstrumental")
    }

    func transpose(of songID: String) -> Int { transposes[songID] ?? 0 }

    func setTranspose(_ semitones: Int, of songID: String) {
        let wrapped = ((semitones % 12) + 12) % 12
        // Kept in -5...6 so the menu never reads +11.
        let shown = wrapped > 6 ? wrapped - 12 : wrapped
        if shown == 0 { transposes[songID] = nil } else { transposes[songID] = shown }
        defaults.set(transposes, forKey: "songTranspose")
    }
}
