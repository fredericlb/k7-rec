// Saving lyrics or chords times the chords from the lyrics' timecodes, so a tap on a chord line seeks the song.
import Foundation

extension SongLibrary {
    /// Saves the lyrics, then the chords timed onto them when RehearsalText can; returns a failure message.
    func saveLyrics(_ text: String, for song: Song) async -> String? {
        if let failure = await saveText(.lyrics, text, for: song) { return failure }
        guard let retimed = SongText.timedChords(chords: song.chords, lyrics: text), retimed != song.chords else { return nil }
        return await saveText(.chords, retimed, for: song)
    }

    /// Saves the chords, timed from the song's lyrics when those carry times; what was typed stays when nothing is placed.
    func saveChords(_ text: String, for song: Song) async -> String? {
        await saveText(.chords, SongText.timedChords(chords: text, lyrics: song.lyrics) ?? text, for: song)
    }
}
