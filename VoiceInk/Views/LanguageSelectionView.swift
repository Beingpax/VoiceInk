import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var whisperState: WhisperState
    @AppStorage(UserDefaultsKeys.TranscriptionService.selectedLanguage) private var localSelectedLanguage: String = "en"
    @AppStorage(UserDefaultsKeys.TranscriptionService.cloudTranscriptionLanguage) private var cloudSelectedLanguage: String = "en"
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full
    
    private var selectedLanguage: String {
        whisperState.transcriptionServiceType == .local ? localSelectedLanguage : cloudSelectedLanguage
    }

    private func updateLanguage(_ language: String) {
        if whisperState.transcriptionServiceType == .local {
            localSelectedLanguage = language
        } else {
            cloudSelectedLanguage = language
        }
        
        // Update language settings in WhisperState
        if whisperState.transcriptionServiceType == .local {
            whisperState.selectedLanguage = language
        } else {
            whisperState.cloudTranscriptionLanguage = language
        }
        
        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
    
    // Function to check if current model is multilingual
    private func isMultilingualModel() -> Bool {
        // For cloud transcription service, all models are multilingual
        if whisperState.transcriptionServiceType == .cloud {
            return true
        }
        
        // For local models, check if they support multiple languages
        guard let currentModel = whisperState.currentModel,
               let predefinedModel = PredefinedModels.models.first(where: { $0.name == currentModel.name }) else {
            return false
        }
        return predefinedModel.isMultilingualModel
    }

    // Function to get current model's supported languages
    private func getCurrentModelLanguages() -> [String: String] {
        guard let currentModel = whisperState.currentModel,
              let predefinedModel = PredefinedModels.models.first(where: {
                  $0.name == currentModel.name
              })
        else {
            return ["en": "English"] // Default to English if no model found
        }
        return predefinedModel.supportedLanguages
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
            let serviceTypeText = whisperState.transcriptionServiceType == .local ? "Local" : "Cloud"
            Text("\(serviceTypeText) Transcription Language")
                .font(.headline)

            if whisperState.transcriptionServiceType == .cloud {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Select Language", selection: Binding(
                        get: { self.selectedLanguage },
                        set: { self.updateLanguage($0) }
                    )) {
                        ForEach(
                            getCurrentModelLanguages().sorted(by: { $0.value < $1.value }), id: \.key
                        ) { key, value in
                            Text(value).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Text("Cloud model: \(whisperState.cloudTranscriptionModelName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Cloud transcription supports multiple languages.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let currentModel = whisperState.currentModel,
                     let predefinedModel = PredefinedModels.models.first(where: {
                         $0.name == currentModel.name
                     })
            {
                // Local transcription service language settings
                if isMultilingualModel() {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Select Language", selection: Binding(
                            get: { self.selectedLanguage },
                            set: { self.updateLanguage($0) }
                        )) {
                            ForEach(
                                predefinedModel.supportedLanguages.sorted(by: {
                                    $0.value < $1.value
                                }), id: \.key
                            ) { key, value in
                                Text(value).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This model supports multiple languages. You can choose auto-detect or select a specific language."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } else {
                    // For English-only models, force set language to English
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: English")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This is an English-optimized model and only supports English transcription."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .onAppear {
                        // Ensure English is set when viewing English-only model
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

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if isMultilingualModel() {
                Menu {
                    ForEach(
                        getCurrentModelLanguages().sorted(by: { $0.value < $1.value }), id: \.key
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
                        let serviceType = whisperState.transcriptionServiceType == .local ? "Local" : "Cloud"
                        Text("\(serviceType) Language: \(currentLanguageDisplayName())")
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
