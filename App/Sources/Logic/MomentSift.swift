// The two sliders of the moment detector as one value, and the run of RehearsalAudio's detector they drive.
// What a reader gets wrong: the floor is an absolute level of the stored envelope, 15% of its peak until moved.
import RehearsalAudio

struct MomentSift: Equatable {
    var floor: Double
    var silence = 2.0
    static let silenceRange = 0.5...10.0

    /// The sliders as the page opens them: the detector's own default floor over `samples`.
    init(samples: [Double]) { floor = (samples.max() ?? 0) * 0.15 }

    func detect(_ samples: [Double]) -> DetectResult {
        MomentDetector.detect(envelope: Envelope(samples: samples), floor: floor, silence: silence)
    }
}
