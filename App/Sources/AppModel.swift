// The app's state holder; it only talks to the seams, never to a package.
import Observation
import SwiftUI

@Observable
final class AppModel {
    let library: SongLibrary
    let recorder: TakeRecording
    let player: TakePlaying
    var openSongID: String?
    var recording = false

    init(
        library: SongLibrary = FakeSongLibrary(),
        recorder: TakeRecording = FakeTakeRecorder(),
        player: TakePlaying = FakeTakePlayer()
    ) {
        self.library = library
        self.recorder = recorder
        self.player = player
    }

    func startTake(song: Song) {
        recorder.start(songID: song.id)
        recording = true
    }

    func stopTake() {
        recorder.stop()
        recording = false
    }
}
