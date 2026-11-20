// The 44 pt rule for a control a thumb must hit (docs/app.md), and the design system's stepper.
import SwiftUI

extension View {
    /// At least 44 by 44 points, the whole square hit-testable.
    func target() -> some View { frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
}

/// Minus and plus in one quiet capsule, each a 48 by 44 pt button with a spoken name; the value sits between
/// them (tempo) or to their left in the secondary colour (a settings row).
struct StepperControl: View {
    let label: String
    let minusLabel: String
    let plusLabel: String
    var valueInside = true
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: K7Space.s12) {
            if !valueInside { Text(label).foregroundStyle(k7.textSecondary).monospacedDigit().fixedSize() }
            HStack(spacing: 0) {
                step("minus", minusLabel, minus)
                if valueInside {
                    Text(label).font(.system(size: 15, weight: .semibold)).monospacedDigit().fixedSize().frame(minWidth: 70)
                } else {
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 20).accessibilityHidden(true)
                }
                step("plus", plusLabel, plus)
            }
            .fillControl()
        }
    }

    private func step(_ symbol: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 48, height: K7Size.touch).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
