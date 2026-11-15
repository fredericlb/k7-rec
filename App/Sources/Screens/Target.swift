// The 44 pt rule for a control a thumb must hit (docs/app.md).
import SwiftUI

extension View {
    /// At least 44 by 44 points, the whole square hit-testable.
    func target() -> some View { frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
}
