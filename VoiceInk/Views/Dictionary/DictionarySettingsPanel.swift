import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Dictionary Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
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
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            Form {
                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        ShortcutRecorder(action: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcuts")
                }

                Section {
                    Toggle("Auto-learn from corrections", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "AutoLearnFromCorrections") },
                        set: { UserDefaults.standard.set($0, forKey: "AutoLearnFromCorrections") }
                    ))
                    Text("When you correct a transcription in the target app, the corrected word is automatically added to your dictionary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Auto-Learn")
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
