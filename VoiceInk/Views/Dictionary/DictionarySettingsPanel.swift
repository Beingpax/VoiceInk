import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Form {
                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        ShortcutRecorder(action: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcut")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var panelHeader: some View {
        AppPanelHeader(title: "Dictionary Settings", onClose: onDismiss)
    }
}
