// The reader's habits: a transposition kept per song, the lyrics lead and the instrument, in UserDefaults.
// What a reader gets wrong: the lead is the reader's, not the song's, so it lives in no song row.
import Foundation
import Observation

/// What the reader plays the chords on.
enum Instrument: String, CaseIterable {
    case guitar, piano
    var symbol: String { self == .guitar ? "guitars" : "pianokeys" }
}

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
    /// The diagrams' instrument; on the piano the capo is ignored and the chords read in the sounding key.
    var instrument: Instrument { didSet { defaults.set(instrument.rawValue, forKey: "instrument") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transposes = defaults.dictionary(forKey: "songTranspose") as? [String: Int] ?? [:]
        instrumentals = Set(defaults.stringArray(forKey: "songInstrumental") ?? [])
        headsetInput = defaults.bool(forKey: "headsetInput")
        lyricsLead = defaults.object(forKey: "lyricsLead") as? Double ?? Self.defaultLead
        instrument = defaults.string(forKey: "instrument").flatMap(Instrument.init) ?? .guitar
    }

    func isInstrumental(_ songID: String) -> Bool { instrumentals.contains(songID) }

    func setInstrumental(_ on: Bool, for songID: String) {
        if on { instrumentals.insert(songID) } else { instrumentals.remove(songID) }
        defaults.set(Array(instrumentals), forKey: "songInstrumental")
    }

    func transpose(of songID: String) -> Int { transposes[songID] ?? 0 }

    /// The semitones the chords are shown moved by: the transposition, plus the capo on the piano, which has none.
    func shownSemitones(of song: Song) -> Int { transpose(of: song.id) + (instrument == .piano ? song.capo : 0) }

    func setTranspose(_ semitones: Int, of songID: String) {
        let wrapped = ((semitones % 12) + 12) % 12
        // Kept in -5...6 so the menu never reads +11.
        let shown = wrapped > 6 ? wrapped - 12 : wrapped
        if shown == 0 { transposes[songID] = nil } else { transposes[songID] = shown }
        defaults.set(transposes, forKey: "songTranspose")
    }
}
