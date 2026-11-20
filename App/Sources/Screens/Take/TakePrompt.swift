// The one text question a take's page asks: a title for a moment or a name for a pin, new or renamed.
import RehearsalAudio
import SwiftUI

enum TakePrompt: Identifiable {
    case saveMoment(DetectedMoment)
    case renameMoment(SavedMoment)
    case newPin
    case renamePin(Pin)

    var id: String {
        switch self {
        case .saveMoment(let m): "save\(m.startSec)"
        case .renameMoment(let m): m.id
        case .newPin: "pin"
        case .renamePin(let p): p.id
        }
    }

    var heading: String {
        switch self {
        case .saveMoment: "Save highlight"
        case .renameMoment: "Rename highlight"
        case .newPin: "Add marker"
        case .renamePin: "Rename marker"
        }
    }

    var initial: String {
        switch self {
        case .saveMoment(let m): TakeMoments.defaultTitle(at: m.startSec)
        case .renameMoment(let m): m.title
        case .newPin: ""
        case .renamePin(let p): p.note
        }
    }
}
