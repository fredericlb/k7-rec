// Saving lyrics keeps timed chords in step: they are re-timed from the new lyrics when they carry timecodes.
import Foundation

extension SongLibrary {
    /// Saves the lyrics, then the chords re-timed onto them when RehearsalText can; returns a failure message.
    func saveLyrics(_ text: String, for song: Song) async -> String? {
        if let failure = await saveText(.lyrics, text, for: song) { return failure }
        guard let retimed = SongText.retimedChords(chords: song.chords, lyrics: text), retimed != song.chords else { return nil }
        return await saveText(.chords, retimed, for: song)
    }
}
