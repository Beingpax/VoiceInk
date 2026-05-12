import Foundation
import KeyboardShortcuts
import LaunchAtLogin
import SwiftData

enum BackupImportError: LocalizedError {
    case saveFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let error):
            return "Failed to save imported \(item): \(error.localizedDescription)"
        }
    }
}

enum BackupImporter {
    private static let keyIsAudioCleanupEnabled = "IsAudioCleanupEnabled"
    private static let keyIsTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    private static let keyTranscriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    private static let keyAudioRetentionPeriod = "AudioRetentionPeriod"

    private static let keyIsTextFormattingEnabled = "IsTextFormattingEnabled"
    private static let keyRemovePunctuation = "RemovePunctuation"
    private static let keyLowercaseTranscription = "LowercaseTranscription"

    @MainActor
    static func apply(_ backup: BackupFile, categories: Set<BackupCategory>, enhancementService: AIEnhancementService, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) throws {
        if categories.contains(.dictionary) {
            try importDictionary(from: backup, modelContext: modelContext)
        }

        if categories.contains(.general) {
            importGeneral(
                backup.generalSettings,
                hotkeyManager: hotkeyManager,
                menuBarManager: menuBarManager,
                mediaController: mediaController,
                playbackController: playbackController,
                soundManager: soundManager,
                recorderUIManager: recorderUIManager
            )
        }

        if categories.contains(.prompts) {
            let predefinedPrompts = enhancementService.customPrompts.filter { $0.isPredefined }
            enhancementService.customPrompts = predefinedPrompts + backup.customPrompts
            print("Successfully imported \(backup.customPrompts.count) custom prompts.")
        }

        if categories.contains(.powerMode) {
            let powerModeManager = PowerModeManager.shared
            powerModeManager.configurations = backup.powerModeConfigs

            if let shortcuts = backup.powerModeShortcuts {
                for (idString, shortcut) in shortcuts {
                    guard let id = UUID(uuidString: idString) else { continue }
                    KeyboardShortcuts.setShortcut(shortcut, for: .powerMode(id: id))
                }
            }

            powerModeManager.saveConfigurations()

            if let customEmojis = backup.customEmojis {
                let emojiManager = EmojiManager.shared
                for emoji in customEmojis {
                    _ = emojiManager.addCustomEmoji(emoji)
                }
            }
            print("Successfully imported \(backup.powerModeConfigs.count) Power Mode configurations.")
        }

        if categories.contains(.customModels) {
            importCustomModels(backup.customCloudModels, transcriptionModelManager: transcriptionModelManager)
        }

        if categories.contains(.languageModes) {
            if let modes = backup.languageModes {
                let activeId = backup.activeLanguageModeId.flatMap(UUID.init)
                LanguageModeManager.shared.replaceAll(modes: modes, activeId: activeId)
                print("Successfully imported \(modes.count) Language Modes.")
            } else {
                print("No Language Modes found in the imported file.")
            }
        }
    }

    @MainActor
    private static func importGeneral(_ general: GeneralBackup?, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager) {
        guard let general else {
            print("No general settings found in the imported file.")
            return
        }

        if let shortcut = general.toggleMiniRecorderShortcut {
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder)
        }
        if let shortcut2 = general.toggleMiniRecorderShortcut2 {
            KeyboardShortcuts.setShortcut(shortcut2, for: .toggleMiniRecorder2)
        }
        if let pasteShortcut = general.pasteLastTranscriptionShortcut {
            KeyboardShortcuts.setShortcut(pasteShortcut, for: .pasteLastTranscription)
        }
        if let pasteEnhancementShortcut = general.pasteLastEnhancementShortcut {
            KeyboardShortcuts.setShortcut(pasteEnhancementShortcut, for: .pasteLastEnhancement)
        }
        if let retryShortcut = general.retryLastTranscriptionShortcut {
            KeyboardShortcuts.setShortcut(retryShortcut, for: .retryLastTranscription)
        }
        if let cancelShortcut = general.cancelRecorderShortcut {
            KeyboardShortcuts.setShortcut(cancelShortcut, for: .cancelRecorder)
        }
        if let historyShortcut = general.openHistoryWindowShortcut {
            KeyboardShortcuts.setShortcut(historyShortcut, for: .openHistoryWindow)
        }
        if let dictionaryShortcut = general.quickAddToDictionaryShortcut {
            KeyboardShortcuts.setShortcut(dictionaryShortcut, for: .quickAddToDictionary)
        }
        if let enhancementShortcut = general.toggleEnhancementShortcut {
            KeyboardShortcuts.setShortcut(enhancementShortcut, for: .toggleEnhancement)
        }
        if let cycleShortcut = general.cycleLanguageModeShortcut {
            KeyboardShortcuts.setShortcut(cycleShortcut, for: .cycleLanguageMode)
        }

        if let hotkeyRaw = general.selectedHotkey1RawValue,
           let hotkey = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw) {
            hotkeyManager.selectedHotkey1 = hotkey
        }
        if let hotkeyRaw2 = general.selectedHotkey2RawValue,
           let hotkey2 = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw2) {
            hotkeyManager.selectedHotkey2 = hotkey2
        }
        if let hotkeyModeRaw = general.hotkeyMode1RawValue,
           let mode = HotkeyManager.HotkeyMode(rawValue: hotkeyModeRaw) {
            hotkeyManager.hotkeyMode1 = mode
        }
        if let hotkeyModeRaw2 = general.hotkeyMode2RawValue,
           let mode2 = HotkeyManager.HotkeyMode(rawValue: hotkeyModeRaw2) {
            hotkeyManager.hotkeyMode2 = mode2
        }
        if let middleClickEnabled = general.isMiddleClickToggleEnabled {
            hotkeyManager.isMiddleClickToggleEnabled = middleClickEnabled
        }
        if let middleClickDelay = general.middleClickActivationDelay {
            hotkeyManager.middleClickActivationDelay = middleClickDelay
        }
        if let launch = general.launchAtLoginEnabled {
            LaunchAtLogin.isEnabled = launch
        }
        if let menuOnly = general.isMenuBarOnly {
            menuBarManager.isMenuBarOnly = menuOnly
        }
        if let recType = general.recorderType {
            recorderUIManager.recorderType = recType
        }

        if let transcriptionCleanup = general.isTranscriptionCleanupEnabled {
            UserDefaults.standard.set(transcriptionCleanup, forKey: keyIsTranscriptionCleanupEnabled)
        }
        if let transcriptionMinutes = general.transcriptionRetentionMinutes {
            UserDefaults.standard.set(transcriptionMinutes, forKey: keyTranscriptionRetentionMinutes)
        }
        if let audioCleanup = general.isAudioCleanupEnabled {
            UserDefaults.standard.set(audioCleanup, forKey: keyIsAudioCleanupEnabled)
        }
        if let audioRetention = general.audioRetentionPeriod {
            UserDefaults.standard.set(audioRetention, forKey: keyAudioRetentionPeriod)
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
            UserDefaults.standard.set(textFormattingEnabled, forKey: keyIsTextFormattingEnabled)
        }
        if let removePunctuation = general.removePunctuation {
            UserDefaults.standard.set(removePunctuation, forKey: keyRemovePunctuation)
        }
        if let lowercaseTranscription = general.lowercaseTranscription {
            UserDefaults.standard.set(lowercaseTranscription, forKey: keyLowercaseTranscription)
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

        print("Successfully imported general settings.")
    }

    @MainActor
    private static func importDictionary(from backup: BackupFile, modelContext: ModelContext) throws {
        var insertedWords = 0
        var insertedReplacements = 0
        var skippedInvalidReplacements = 0

        if let words = backup.vocabularyWords {
            let descriptor = FetchDescriptor<VocabularyWord>()
            let existingWords = try modelContext.fetch(descriptor)
            var existingWordsSet = Set(existingWords.map { $0.word.lowercased() })

            for item in words {
                let word = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { continue }

                let lowercasedWord = word.lowercased()
                if !existingWordsSet.contains(lowercasedWord) {
                    modelContext.insert(VocabularyWord(word: word))
                    existingWordsSet.insert(lowercasedWord)
                    insertedWords += 1
                }
            }
        } else {
            print("No vocabulary words found in the imported file. Existing items remain unchanged.")
        }

        if let replacements = backup.wordReplacements {
            let descriptor = FetchDescriptor<WordReplacement>()
            let existingReplacements = try modelContext.fetch(descriptor)

            var existingKeys = Set<String>()
            for existing in existingReplacements {
                existingKeys.formUnion(tokens(from: existing.originalText))
            }

            for (original, replacement) in replacements {
                let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                let importTokens = tokens(from: trimmedOriginal)
                guard !importTokens.isEmpty, !trimmedReplacement.isEmpty else {
                    skippedInvalidReplacements += 1
                    continue
                }

                let hasConflict = importTokens.contains { existingKeys.contains($0) }

                if !hasConflict {
                    modelContext.insert(WordReplacement(originalText: trimmedOriginal, replacementText: trimmedReplacement))
                    existingKeys.formUnion(importTokens)
                    insertedReplacements += 1
                }
            }
        } else {
            print("No word replacements found in the imported file. Existing replacements remain unchanged.")
        }

        guard insertedWords > 0 || insertedReplacements > 0 else {
            print("No new dictionary entries were imported.")
            if skippedInvalidReplacements > 0 {
                print("Skipped \(skippedInvalidReplacements) invalid word replacements from the imported file.")
            }
            return
        }

        do {
            try modelContext.save()
            print("Successfully imported \(insertedWords) vocabulary words and \(insertedReplacements) word replacements to SwiftData.")
            if skippedInvalidReplacements > 0 {
                print("Skipped \(skippedInvalidReplacements) invalid word replacements from the imported file.")
            }
        } catch {
            modelContext.rollback()
            throw BackupImportError.saveFailed("dictionary entries", error)
        }
    }

    @MainActor
    private static func importCustomModels(_ models: [CustomModelBackup]?, transcriptionModelManager: TranscriptionModelManager) {
        guard let models else {
            print("No custom models found in the imported file.")
            return
        }

        let customModelManager = CustomCloudModelManager.shared
        customModelManager.customModels = models.map { $0.makeModel() }
        customModelManager.saveCustomModels()
        transcriptionModelManager.refreshAllAvailableModels()
        print("Successfully imported \(models.count) custom model definitions.")
    }

    private static func tokens(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
