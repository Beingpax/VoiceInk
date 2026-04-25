import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("SelectedLanguages") private var selectedLanguagesCSV: String = "en"
    var displayMode: LanguageDisplayMode = .full
    @ObservedObject var whisperPrompt: WhisperPrompt

    // MARK: - Selection helpers

    private var selectedLanguages: [String] {
        let parsed = selectedLanguagesCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? ["en"] : parsed
    }

    private func setSelection(_ languages: [String]) {
        let cleaned = languages
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let final = cleaned.isEmpty ? ["en"] : cleaned

        // @AppStorage drives both UserDefaults keys directly so SwiftUI re-renders. The plain
        // legacy key is kept in sync for code that still reads `SelectedLanguage`.
        selectedLanguagesCSV = final.joined(separator: ",")
        selectedLanguage = final.first ?? "en"

        whisperPrompt.updateTranscriptionPrompt()
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func updateLanguage(_ language: String) {
        setSelection([language])
    }

    private func toggleLanguage(_ language: String) {
        var current = selectedLanguages
        if language == "auto" {
            // Picking auto-detect clears all other choices.
            setSelection(["auto"])
            return
        }
        // Adding a real language replaces auto-detect.
        current.removeAll { $0 == "auto" }
        if let index = current.firstIndex(of: language) {
            current.remove(at: index)
        } else {
            current.append(language)
        }
        if current.isEmpty {
            current = ["auto"]
        }
        setSelection(current)
    }

    // MARK: - Capability checks

    private func isMultilingualModel() -> Bool {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }
        return currentModel.isMultilingualModel
    }

    private func languageSelectionDisabled() -> Bool {
        guard let provider = transcriptionModelManager.currentTranscriptionModel?.provider else {
            return false
        }
        return provider == .fluidAudio || provider == .gemini
    }

    private func supportsMultiLanguageSelection() -> Bool {
        // Soniox is the only provider that exposes multi-language `language_hints`. Other providers
        // accept a single language code per request, so we keep the picker single-select for them.
        guard let provider = transcriptionModelManager.currentTranscriptionModel?.provider else {
            return false
        }
        return provider == .soniox
    }

    private func getCurrentModelLanguages() -> [String: String] {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return ["en": "English"]
        }
        return currentModel.supportedLanguages
    }

    private func currentLanguageDisplayName() -> String {
        return getCurrentModelLanguages()[selectedLanguage] ?? "Unknown"
    }

    private func multiLanguageDisplayName() -> String {
        let names = selectedLanguages.compactMap { getCurrentModelLanguages()[$0] }
        if names.isEmpty { return "None" }
        if names.count == 1 { return names[0] }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }

    private func sortedLanguages() -> [(key: String, value: String)] {
        getCurrentModelLanguages().sorted(by: {
            if $0.key == "auto" { return true }
            if $1.key == "auto" { return false }
            return $0.value < $1.value
        })
    }

    var body: some View {
        switch displayMode {
        case .full:
            fullView
        case .menuItem:
            menuItemView
        }
    }

    // MARK: - Settings view

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageSelectionSection
        }
    }

    private var languageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Language")
                .font(.headline)

            if let currentModel = transcriptionModelManager.currentTranscriptionModel {
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
                    if supportsMultiLanguageSelection() {
                        multiSelectFullView(currentModel: currentModel)
                    } else {
                        singleSelectFullView(currentModel: currentModel)
                    }
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

    private func singleSelectFullView(currentModel: any TranscriptionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Select Language", selection: Binding(
                get: { selectedLanguages.first ?? "auto" },
                set: { updateLanguage($0) }
            )) {
                ForEach(sortedLanguages(), id: \.key) { key, value in
                    Text(value).tag(key)
                }
            }
            .pickerStyle(MenuPickerStyle())

            Text("Current model: \(currentModel.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("This model supports multiple languages. Select a specific language or auto-detect (if available).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func multiSelectFullView(currentModel: any TranscriptionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(sortedLanguages(), id: \.key) { key, value in
                    Button {
                        toggleLanguage(key)
                    } label: {
                        HStack {
                            Text(value)
                            if selectedLanguages.contains(key) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Languages: \(multiLanguageDisplayName())")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }
            .menuStyle(.borderlessButton)

            Text("Current model: \(currentModel.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Soniox supports mixed-language audio. Select every language you expect to hear, or pick Auto-detect to let the model decide.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Menu bar view

    private var menuItemView: some View {
        Group {
            if languageSelectionDisabled() {
                Button {
                    // Info-only entry.
                } label: {
                    Text("Language: Autodetected")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
            } else if isMultilingualModel() {
                if supportsMultiLanguageSelection() {
                    multiSelectMenu
                } else {
                    singleSelectMenu
                }
            } else {
                Button {
                    // Info-only entry.
                } label: {
                    Text("Language: English (only)")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
                .onAppear {
                    updateLanguage("en")
                }
            }
        }
    }

    private var singleSelectMenu: some View {
        Menu {
            ForEach(sortedLanguages(), id: \.key) { key, value in
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
    }

    private var multiSelectMenu: some View {
        Menu {
            ForEach(sortedLanguages(), id: \.key) { key, value in
                Button {
                    toggleLanguage(key)
                } label: {
                    HStack {
                        Text(value)
                        if selectedLanguages.contains(key) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("Languages: \(multiLanguageDisplayName())")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
        }
    }
}
