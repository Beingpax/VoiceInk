import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Form {
                Section {
                    Toggle("Auto-Learn Dictionary", isOn: $isAutoLearnDictionaryEnabled)
                    .onChange(of: isAutoLearnDictionaryEnabled) { _, isEnabled in
                        Task {
                            await AutoLearnService.shared.settingDidChange(isEnabled: isEnabled)
                        }
                    }

                    if isAutoLearnDictionaryEnabled {
                        AutoLearnModelSelectionView()
                    }
                } header: {
                    AutoLearnSectionHeader()
                }

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
