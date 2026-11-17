// What the stems sheet tells a device that may be too small for the model.
// What a reader gets wrong: the threshold is a guess to be replaced by a measurement on a phone (docs/stems.md).
import Foundation

enum StemAdvice {
    /// Below this the 407 MB model may be killed by the system; a 4 GB phone reports a little under 4e9 bytes.
    static let comfortableMemory: UInt64 = 3_500_000_000

    static func memoryNote(physical: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String? {
        physical >= comfortableMemory ? nil : "This device has little memory. The app may be closed by the system while it separates; nothing is lost if it is."
    }
}
