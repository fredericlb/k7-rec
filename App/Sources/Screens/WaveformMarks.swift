// What is drawn over a take's waveform: the detector's floor, detected and saved spans, and the pins.
// What a reader gets wrong: it never moves with the playhead, so it is an Equatable layer of its own.
import SwiftUI

struct WaveformMarks: View, Equatable {
    let duration: TimeInterval
    var floor: Double?
    var found: [ClosedRange<TimeInterval>] = []
    var saved: [ClosedRange<TimeInterval>] = []
    var pins: [TimeInterval] = []

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            func x(_ t: TimeInterval) -> CGFloat { CGFloat(min(max(t / duration, 0), 1)) * size.width }
            func band(_ span: ClosedRange<TimeInterval>, _ color: Color) {
                context.fill(Path(CGRect(x: x(span.lowerBound), y: 0, width: max(2, x(span.upperBound) - x(span.lowerBound)), height: size.height)), with: .color(color))
            }
            for span in saved { band(span, .green.opacity(0.22)) }
            for span in found { band(span, .orange.opacity(0.25)) }
            if let floor {
                for sign in [-1.0, 1.0] {
                    let y = size.height / 2 + CGFloat(sign * min(floor, 1)) * size.height / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            for pin in pins {
                context.fill(Path(CGRect(x: x(pin) - 0.5, y: 0, width: 1, height: size.height)), with: .color(.blue))
                context.fill(Path(ellipseIn: CGRect(x: x(pin) - 4, y: 0, width: 8, height: 8)), with: .color(.blue))
            }
        }
        .allowsHitTesting(false)
    }
}
