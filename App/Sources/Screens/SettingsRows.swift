// The design system's settings rows, shared by Settings and a song's Info: a card with its title and note, a label
// with its control, a field, an action, a value, the separator between rows.
import SwiftUI

/// A labelled card of rows with its note underneath.
struct SettingsCard<Rows: View>: View {
    let title: String
    let note: String?
    @ViewBuilder let rows: Rows
    init(_ title: String, note: String? = nil, @ViewBuilder rows: () -> Rows) { self.title = title; self.note = note; self.rows = rows() }

    var body: some View {
        VStack(spacing: K7Space.s8) {
            SectionTitle(title)
            VStack(spacing: 0) { rows }.card()
            if let note { CardNote(note) }
        }
    }
}

/// A label left, its control or value right, at least a row tall.
struct SettingRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control
    init(_ label: String, @ViewBuilder control: () -> Control) { self.label = label; self.control = control() }

    var body: some View {
        HStack(spacing: K7Space.s12) {
            Text(label)
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: K7Size.row)
        .padding(.leading, K7Space.s20).padding(.trailing, K7Space.s16)
    }
}

/// A label and a borderless right-aligned field filling the rest of the row.
struct FieldRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var capitalized = false

    var body: some View {
        SettingRow(label) {
            Group {
                if secure { SecureField(label, text: $text, prompt: Text(placeholder).foregroundStyle(k7.textPlaceholder)) } else {
                    TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(k7.textPlaceholder))
                        .keyboardType(keyboard).textInputAutocapitalization(capitalized ? .words : .never).autocorrectionDisabled()
                }
            }
            .multilineTextAlignment(.trailing)
            .frame(minHeight: K7Size.touch)
        }
    }
}

/// A full-width row whose label is the action, in the soft accent; greyed while it cannot run.
struct ActionRow: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).fontWeight(.semibold).foregroundStyle(enabled ? k7.accentSoft : k7.textPlaceholder)
                Spacer()
                if busy { ProgressView() }
            }
            .frame(minHeight: K7Size.row)
            .padding(.leading, K7Space.s20).padding(.trailing, K7Space.s16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct Value: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).foregroundStyle(k7.textSecondary).monospacedDigit().lineLimit(1).truncationMode(.middle) }
}

struct Separator: View {
    var body: some View { Rectangle().fill(k7.separator).frame(height: 1).padding(.leading, K7Space.s20) }
}
