import SwiftUI
import KeyboardShortcuts

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Dictionary Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }

            // Content
            Form {
                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        KeyboardShortcuts.Recorder(for: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcuts")
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
