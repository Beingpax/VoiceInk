import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var whisperState: WhisperState
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("AutoSwitchLanguageByKeyboard") private var autoSwitchEnabled: Bool = false
    var displayMode: LanguageDisplayMode = .full
    @ObservedObject var whisperPrompt: WhisperPrompt
    @StateObject private var keyboardMonitor = KeyboardInputSourceMonitor.shared
    @State private var expandedSections: Set<ExpandableSection> = []

    private func updateLanguage(_ language: String) {
        // Update UI state - the UserDefaults updating is now automatic with @AppStorage
        selectedLanguage = language

        // Force the prompt to update for the new language
        whisperPrompt.updateTranscriptionPrompt()

        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    // Function to check if current model is multilingual
    private func isMultilingualModel() -> Bool {
        guard let currentModel = whisperState.currentTranscriptionModel else {
            return false
        }
        return currentModel.isMultilingualModel
    }

    private func languageSelectionDisabled() -> Bool {
        guard let provider = whisperState.currentTranscriptionModel?.provider else {
            return false
        }
        return provider == .parakeet || provider == .gemini
    }

    // Function to get current model's supported languages
    private func getCurrentModelLanguages() -> [String: String] {
        guard let currentModel = whisperState.currentTranscriptionModel else {
            return ["en": "English"] // Default to English if no model found
        }
        return currentModel.supportedLanguages
    }

    // Get the display name of the current language
    private func currentLanguageDisplayName() -> String {
        return getCurrentModelLanguages()[selectedLanguage] ?? "Unknown"
    }

    var body: some View {
        switch displayMode {
        case .full:
            fullView
        case .menuItem:
            menuItemView
        }
    }

    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageSelectionSection
        }
    }
    
    private var languageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Language")
                .font(.headline)

            if let currentModel = whisperState.currentTranscriptionModel
            {
                if languageSelectionDisabled() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: Autodetected")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("Current model: \(currentModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("The transcription language is automatically detected by the model.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                } else if isMultilingualModel() {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Select Language", selection: $selectedLanguage) {
                            ForEach(
                                currentModel.supportedLanguages.sorted(by: {
                                    if $0.key == "auto" { return true }
                                    if $1.key == "auto" { return false }
                                    return $0.value < $1.value
                                }), id: \.key
                            ) { key, value in
                                Text(value).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .disabled(autoSwitchEnabled)
                        .onChange(of: selectedLanguage) { oldValue, newValue in
                            updateLanguage(newValue)
                        }

                        Text("Current model: \(currentModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This model supports multiple languages. Select a specific language or auto-detect(if available)"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Divider()

                    autoSwitchKeyboardSection
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: English")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("Current model: \(currentModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This is an English-optimized model and only supports English transcription."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .onAppear {
                        updateLanguage("en")
                    }
                }
            } else {
                Text("No model selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var autoSwitchKeyboardSection: some View {
        ExpandableToggleSection(
            section: .autoSwitchKeyboard,
            title: "Auto-switch with keyboard",
            helpText: "Automatically change the transcription language when you switch your system keyboard input source",
            isEnabled: $autoSwitchEnabled,
            expandedSections: $expandedSections
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)
                    Text("Current keyboard:")
                        .foregroundColor(.secondary)
                    Text(keyboardMonitor.currentKeyboardDisplayName)
                        .fontWeight(.medium)
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("Detected language:")
                        .foregroundColor(.secondary)
                    Text(keyboardMonitor.currentKeyboardLanguage)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: autoSwitchEnabled) { _, newValue in
            if newValue {
                keyboardMonitor.syncLanguageIfEnabled()
            }
        }
    }

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if languageSelectionDisabled() {
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: Autodetected")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
            } else if isMultilingualModel() {
                Menu {
                    ForEach(
                        getCurrentModelLanguages().sorted(by: {
                            if $0.key == "auto" { return true }
                            if $1.key == "auto" { return false }
                            return $0.value < $1.value
                        }), id: \.key
                    ) { key, value in
                        Button {
                            updateLanguage(key)
                        } label: {
                            HStack {
                                Text(value)
                                if selectedLanguage == key {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Language: \(currentLanguageDisplayName())")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
            } else {
                // For English-only models
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: English (only)")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
                .onAppear {
                    // Ensure English is set for English-only models
                    updateLanguage("en")
                }
            }
        }
    }
}
