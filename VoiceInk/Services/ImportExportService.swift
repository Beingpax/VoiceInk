import Foundation
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts
import LaunchAtLogin
import SwiftData

struct GeneralSettings: Codable {
    let toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    let toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?
    let retryLastTranscriptionShortcut: KeyboardShortcuts.Shortcut?
    let selectedHotkey1RawValue: String?
    let selectedHotkey2RawValue: String?
    let launchAtLoginEnabled: Bool?
    let isMenuBarOnly: Bool?
    let recorderType: String?
    let isTranscriptionCleanupEnabled: Bool?
    let transcriptionRetentionMinutes: Int?
    let isAudioCleanupEnabled: Bool?
    let audioRetentionPeriod: Int?

    let isSoundFeedbackEnabled: Bool?
    let isSystemMuteEnabled: Bool?
    let isPauseMediaEnabled: Bool?
    let audioResumptionDelay: Double?
    let isTextFormattingEnabled: Bool?
    let isExperimentalFeaturesEnabled: Bool?
    let restoreClipboardAfterPaste: Bool?
    let clipboardRestoreDelay: Double?
    let useAppleScriptPaste: Bool?
}

// Simple codable struct for vocabulary words (for export/import only)
struct VocabularyWordData: Codable {
    let word: String
}

struct VoiceInkExportedSettings: Codable {
    let version: String
    let customPrompts: [CustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let vocabularyWords: [VocabularyWordData]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralSettings?
    let customEmojis: [String]?
    let customCloudModels: [CustomCloudModel]?
}

class ImportExportService {
    static let shared = ImportExportService()
    private let currentSettingsVersion: String
    private let dictionaryItemsKey = "CustomVocabularyItems"
    private let wordReplacementsKey = "wordReplacements"


    private let keyIsMenuBarOnly = "IsMenuBarOnly"
    private let keyRecorderType = "RecorderType"
    private let keyIsAudioCleanupEnabled = "IsAudioCleanupEnabled"
    private let keyIsTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    private let keyTranscriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    private let keyAudioRetentionPeriod = "AudioRetentionPeriod"

    private let keyIsSoundFeedbackEnabled = "isSoundFeedbackEnabled"
    private let keyIsSystemMuteEnabled = "isSystemMuteEnabled"
    private let keyIsTextFormattingEnabled = "IsTextFormattingEnabled"

    private init() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentSettingsVersion = version
        } else {
            self.currentSettingsVersion = "0.0.0"
        }
    }

    @MainActor
    func exportSettings(enhancementService: AIEnhancementService, whisperPrompt: WhisperPrompt, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, whisperState: WhisperState) {
        let powerModeManager = PowerModeManager.shared
        let emojiManager = EmojiManager.shared

        let exportablePrompts = enhancementService.customPrompts.filter { !$0.isPredefined }

        let powerConfigs = powerModeManager.configurations
        
        // Export custom models
        let customModels = CustomModelManager.shared.customModels

        // Fetch vocabulary words from SwiftData
        var exportedDictionaryItems: [VocabularyWordData]? = nil
        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
        if let items = try? whisperState.modelContext.fetch(vocabularyDescriptor), !items.isEmpty {
            exportedDictionaryItems = items.map { VocabularyWordData(word: $0.word) }
        }

        // Fetch word replacements from SwiftData
        var exportedWordReplacements: [String: String]? = nil
        let replacementsDescriptor = FetchDescriptor<WordReplacement>()
        if let replacements = try? whisperState.modelContext.fetch(replacementsDescriptor), !replacements.isEmpty {
            exportedWordReplacements = Dictionary(uniqueKeysWithValues: replacements.map { ($0.originalText, $0.replacementText) })
        }

        let generalSettingsToExport = GeneralSettings(
            toggleMiniRecorderShortcut: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder),
            toggleMiniRecorderShortcut2: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2),
            retryLastTranscriptionShortcut: KeyboardShortcuts.getShortcut(for: .retryLastTranscription),
            selectedHotkey1RawValue: hotkeyManager.selectedHotkey1.rawValue,
            selectedHotkey2RawValue: hotkeyManager.selectedHotkey2.rawValue,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            isMenuBarOnly: menuBarManager.isMenuBarOnly,
            recorderType: whisperState.recorderType,
            isTranscriptionCleanupEnabled: UserDefaults.standard.bool(forKey: keyIsTranscriptionCleanupEnabled),
            transcriptionRetentionMinutes: UserDefaults.standard.integer(forKey: keyTranscriptionRetentionMinutes),
            isAudioCleanupEnabled: UserDefaults.standard.bool(forKey: keyIsAudioCleanupEnabled),
            audioRetentionPeriod: UserDefaults.standard.integer(forKey: keyAudioRetentionPeriod),

            isSoundFeedbackEnabled: soundManager.isEnabled,
            isSystemMuteEnabled: mediaController.isSystemMuteEnabled,
            isPauseMediaEnabled: playbackController.isPauseMediaEnabled,
            audioResumptionDelay: mediaController.audioResumptionDelay,
            isTextFormattingEnabled: UserDefaults.standard.bool(forKey: keyIsTextFormattingEnabled),
            isExperimentalFeaturesEnabled: UserDefaults.standard.bool(forKey: "isExperimentalFeaturesEnabled"),
            restoreClipboardAfterPaste: UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste"),
            clipboardRestoreDelay: UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            useAppleScriptPaste: UserDefaults.standard.bool(forKey: "useAppleScriptPaste")
        )

        let exportedSettings = VoiceInkExportedSettings(
            version: currentSettingsVersion,
            customPrompts: exportablePrompts,
            powerModeConfigs: powerConfigs,
            vocabularyWords: exportedDictionaryItems,
            wordReplacements: exportedWordReplacements,
            generalSettings: generalSettingsToExport,
            customEmojis: emojiManager.customEmojis,
            customCloudModels: customModels
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(exportedSettings)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = "VoiceInk_Settings_Backup.json"
            savePanel.title = "Export VoiceInk Settings"
            savePanel.message = "Choose a location to save your settings."

            DispatchQueue.main.async {
                if savePanel.runModal() == .OK {
                    if let url = savePanel.url {
                        do {
                            try jsonData.write(to: url)
                            self.showAlert(title: "Export Successful", message: "Your settings have been successfully exported to \(url.lastPathComponent).")
                        } catch {
                            self.showAlert(title: "Export Error", message: "Could not save settings to file: \(error.localizedDescription)")
                        }
                    }
                } else {
                    self.showAlert(title: "Export Canceled", message: "The settings export operation was canceled.")
                }
            }
        } catch {
            self.showAlert(title: "Export Error", message: "Could not encode settings to JSON: \(error.localizedDescription)")
        }
    }

    @MainActor
    func importSettings(enhancementService: AIEnhancementService, whisperPrompt: WhisperPrompt, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, whisperState: WhisperState) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import VoiceInk Settings"
        openPanel.message = "Choose a settings file to import. This will overwrite ALL settings (prompts, power modes, dictionary, general app settings)."

        DispatchQueue.main.async {
            if openPanel.runModal() == .OK {
                guard let url = openPanel.url else {
                    self.showAlert(title: "Import Error", message: "Could not get the file URL from the open panel.")
                    return
                }

                do {
                    let jsonData = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let importedSettings = try decoder.decode(VoiceInkExportedSettings.self, from: jsonData)
                    
                    if importedSettings.version != self.currentSettingsVersion {
                        self.showAlert(title: "Version Mismatch", message: "The imported settings file (version \(importedSettings.version)) is from a different version than your application (version \(self.currentSettingsVersion)). Proceeding with import, but be aware of potential incompatibilities.")
                    }

                    let predefinedPrompts = enhancementService.customPrompts.filter { $0.isPredefined }
                    enhancementService.customPrompts = predefinedPrompts + importedSettings.customPrompts
                    
                    let powerModeManager = PowerModeManager.shared
                    powerModeManager.configurations = importedSettings.powerModeConfigs
                    powerModeManager.saveConfigurations()

                    // Import Custom Models
                    if let modelsToImport = importedSettings.customCloudModels {
                        let customModelManager = CustomModelManager.shared
                        customModelManager.customModels = modelsToImport
                        customModelManager.saveCustomModels() // Ensure they are persisted
                        whisperState.refreshAllAvailableModels() // Refresh the UI
                        print("Successfully imported \(modelsToImport.count) custom models.")
                    } else {
                        print("No custom models found in the imported file.")
                    }

                    if let customEmojis = importedSettings.customEmojis {
                        let emojiManager = EmojiManager.shared
                        for emoji in customEmojis {
                            _ = emojiManager.addCustomEmoji(emoji)
                        }
                    }

                    // Import vocabulary words to SwiftData
                    if let itemsToImport = importedSettings.vocabularyWords {
                        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
                        let existingWords = (try? whisperState.modelContext.fetch(vocabularyDescriptor)) ?? []
                        let existingWordsSet = Set(existingWords.map { $0.word.lowercased() })

                        for item in itemsToImport {
                            if !existingWordsSet.contains(item.word.lowercased()) {
                                let newWord = VocabularyWord(word: item.word)
                                whisperState.modelContext.insert(newWord)
                            }
                        }
                        try? whisperState.modelContext.save()
                        print("Successfully imported vocabulary words to SwiftData.")
                    } else {
                        print("No vocabulary words found in the imported file. Existing items remain unchanged.")
                    }

                    // Import word replacements to SwiftData
                    if let replacementsToImport = importedSettings.wordReplacements {
                        let replacementsDescriptor = FetchDescriptor<WordReplacement>()
                        let existingReplacements = (try? whisperState.modelContext.fetch(replacementsDescriptor)) ?? []

                        // Build a set of existing replacement keys for duplicate checking
                        var existingKeysSet = Set<String>()
                        for existing in existingReplacements {
                            let tokens = existing.originalText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                                .filter { !$0.isEmpty }
                            existingKeysSet.formUnion(tokens)
                        }

                        for (original, replacement) in replacementsToImport {
                            let importTokens = original
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                                .filter { !$0.isEmpty }

                            // Check if any token already exists
                            let hasConflict = importTokens.contains { existingKeysSet.contains($0) }

                            if !hasConflict {
                                let newReplacement = WordReplacement(originalText: original, replacementText: replacement)
                                whisperState.modelContext.insert(newReplacement)
                                // Add these tokens to the set to prevent duplicates within the import
                                existingKeysSet.formUnion(importTokens)
                            }
                        }
                        try? whisperState.modelContext.save()
                        print("Successfully imported word replacements to SwiftData.")
                    } else {
                        print("No word replacements found in the imported file. Existing replacements remain unchanged.")
                    }

                    if let general = importedSettings.generalSettings {
                        if let shortcut = general.toggleMiniRecorderShortcut {
                            KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder)
                        }
                        if let shortcut2 = general.toggleMiniRecorderShortcut2 {
                            KeyboardShortcuts.setShortcut(shortcut2, for: .toggleMiniRecorder2)
                        }
                        if let retryShortcut = general.retryLastTranscriptionShortcut {
                            KeyboardShortcuts.setShortcut(retryShortcut, for: .retryLastTranscription)
                        }
                        if let hotkeyRaw = general.selectedHotkey1RawValue,
                           let hotkey = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw) {
                            hotkeyManager.selectedHotkey1 = hotkey
                        }
                        if let hotkeyRaw2 = general.selectedHotkey2RawValue,
                           let hotkey2 = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw2) {
                            hotkeyManager.selectedHotkey2 = hotkey2
                        }
                        if let launch = general.launchAtLoginEnabled {
                            LaunchAtLogin.isEnabled = launch
                        }
                        if let menuOnly = general.isMenuBarOnly {
                            menuBarManager.isMenuBarOnly = menuOnly
                        }
                        if let recType = general.recorderType {
                            whisperState.recorderType = recType
                        }

                        if let transcriptionCleanup = general.isTranscriptionCleanupEnabled {
                            UserDefaults.standard.set(transcriptionCleanup, forKey: self.keyIsTranscriptionCleanupEnabled)
                        }
                        if let transcriptionMinutes = general.transcriptionRetentionMinutes {
                            UserDefaults.standard.set(transcriptionMinutes, forKey: self.keyTranscriptionRetentionMinutes)
                        }
                        if let audioCleanup = general.isAudioCleanupEnabled {
                            UserDefaults.standard.set(audioCleanup, forKey: self.keyIsAudioCleanupEnabled)
                        }
                        if let audioRetention = general.audioRetentionPeriod {
                            UserDefaults.standard.set(audioRetention, forKey: self.keyAudioRetentionPeriod)
                        }

                        if let soundFeedback = general.isSoundFeedbackEnabled {
                            soundManager.isEnabled = soundFeedback
                        }
                        if let muteSystem = general.isSystemMuteEnabled {
                            mediaController.isSystemMuteEnabled = muteSystem
                        }
                        if let pauseMedia = general.isPauseMediaEnabled {
                            playbackController.isPauseMediaEnabled = pauseMedia
                        }
                        if let audioDelay = general.audioResumptionDelay {
                            mediaController.audioResumptionDelay = audioDelay
                        }
                        if let experimentalEnabled = general.isExperimentalFeaturesEnabled {
                            UserDefaults.standard.set(experimentalEnabled, forKey: "isExperimentalFeaturesEnabled")
                            if experimentalEnabled == false {
                                playbackController.isPauseMediaEnabled = false
                            }
                        }
                        if let textFormattingEnabled = general.isTextFormattingEnabled {
                            UserDefaults.standard.set(textFormattingEnabled, forKey: self.keyIsTextFormattingEnabled)
                        }
                        if let restoreClipboard = general.restoreClipboardAfterPaste {
                            UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboardAfterPaste")
                        }
                        if let clipboardDelay = general.clipboardRestoreDelay {
                            UserDefaults.standard.set(clipboardDelay, forKey: "clipboardRestoreDelay")
                        }
                        if let appleScriptPaste = general.useAppleScriptPaste {
                            UserDefaults.standard.set(appleScriptPaste, forKey: "useAppleScriptPaste")
                        }
                    }

                    self.showRestartAlert(message: "Settings imported successfully from \(url.lastPathComponent). All settings (including general app settings) have been applied.")

                } catch {
                    self.showAlert(title: "Import Error", message: "Error importing settings: \(error.localizedDescription). The file might be corrupted or not in the correct format.")
                }
            } else {
                self.showAlert(title: "Import Canceled", message: "The settings import operation was canceled.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showRestartAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Import Successful"
            alert.informativeText = message + "\n\nIMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.\n\nIt is recommended to restart VoiceInk for all changes to take full effect."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Configure API Keys")
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Enhancement"]
                )
            }
        }
    }
}