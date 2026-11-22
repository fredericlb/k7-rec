// The design system's segmented control: views of one thing in a Liquid Glass capsule, a lozenge sliding to the
// one picked. Segments are 104 pt wide on iPad and the Mac and share the full width on iPhone. A segment with
// nothing in it yet shows a small plus: picking it asks for its content.
import SwiftUI

struct GlassSegments<Value: Hashable>: View {
    let items: [(value: Value, label: String, empty: Bool)]
    let selection: Value
    let wide: Bool
    let pick: (Value) -> Void
    @Namespace private var lozenge

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                let on = item.value == selection
                Button { withAnimation(.bouncy(duration: 0.45, extraBounce: 0.15)) { pick(item.value) } } label: {
                    HStack(spacing: 3) {
                        if item.empty { Image(systemName: "plus").font(.system(size: wide ? 11 : 10, weight: .bold)) }
                        Text(item.label)
                    }
                    .font(.system(size: wide ? 15 : 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: wide ? 104 : .infinity, minHeight: 36)
                        .frame(width: wide ? 104 : nil)
                        .foregroundStyle(on ? Color.white : k7.textInactive.opacity(item.empty ? 0.75 : 1))
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: K7Radius.panel).fill(k7.fillSelected)
                                    .matchedGeometryEffect(id: "lozenge", in: lozenge)
                            }
                        }
                        .frame(minHeight: K7Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.empty ? "Add \(item.label.lowercased())" : item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
