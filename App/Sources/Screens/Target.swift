// The 44 pt rule for a control a thumb must hit (docs/app.md).
import SwiftUI

extension View {
    /// At least 44 by 44 points, the whole square hit-testable.
    func target() -> some View { frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
}

/// A minus, a value and a plus, each button a 44 pt target with a spoken name.
struct StepperControl: View {
    let label: String
    let minusLabel: String
    let plusLabel: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: minus) { Image(systemName: "minus").target() }.buttonStyle(.bordered).accessibilityLabel(minusLabel)
            Text(label).monospacedDigit().fixedSize().frame(minWidth: 70)
            Button(action: plus) { Image(systemName: "plus").target() }.buttonStyle(.bordered).accessibilityLabel(plusLabel)
        }
    }
}
