// What the play button and the Takes list need from the player.
import Foundation

protocol TakePlaying: AnyObject {
    var playingID: String? { get }
    func play(id: String)
    func stop()
}

final class FakeTakePlayer: TakePlaying {
    private(set) var playingID: String?
    func play(id: String) { playingID = id }
    func stop() { playingID = nil }
}
