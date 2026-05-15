import Foundation
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
    static func apply(_ backup: BackupFile, categories: Set<BackupCategory>, enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) throws {
        if categories.contains(.dictionary) {
            try importDictionary(from: backup, modelContext: modelContext)
        }

        if categories.contains(.general) {
            importGeneral(
                backup.generalSettings,
                recordingShortcutManager: recordingShortcutManager,
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
            for config in powerModeManager.configurations {
                ShortcutStore.removeShortcutStorage(for: .powerMode(config.id))
            }

            powerModeManager.configurations = backup.powerModeConfigs
            let importedPowerModeIds = Set(backup.powerModeConfigs.map(\.id))

            if let shortcuts = backup.powerModeShortcuts {
                for (idString, shortcutBackup) in shortcuts {
                    guard
                        let id = UUID(uuidString: idString),
                        importedPowerModeIds.contains(id)
                    else {
                        continue
                    }

                    ShortcutStore.setShortcut(shortcutBackup.shortcut, for: .powerMode(id))
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
    }

    @MainActor
    private static func importGeneral(_ general: GeneralBackup?, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager) {
        guard let general else {
            print("No general settings found in the imported file.")
            return
        }

        if let shortcut = general.primaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut.shortcut, for: .primaryRecording)
            recordingShortcutManager.primaryRecordingShortcut = .custom
        }
        if let shortcut2 = general.secondaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut2.shortcut, for: .secondaryRecording)
            recordingShortcutManager.secondaryRecordingShortcut = .custom
        }
        if let pasteShortcut = general.pasteLastTranscriptionShortcut {
            ShortcutStore.setShortcut(pasteShortcut.shortcut, for: .pasteLastTranscription)
        }
        if let pasteEnhancementShortcut = general.pasteLastEnhancementShortcut {
            ShortcutStore.setShortcut(pasteEnhancementShortcut.shortcut, for: .pasteLastEnhancement)
        }
        if let retryShortcut = general.retryLastTranscriptionShortcut {
            ShortcutStore.setShortcut(retryShortcut.shortcut, for: .retryLastTranscription)
        }
        if let cancelShortcut = general.cancelRecorderShortcut {
            ShortcutStore.setShortcut(cancelShortcut.shortcut, for: .cancelRecorder)
        }
        if let historyShortcut = general.openHistoryWindowShortcut {
            ShortcutStore.setShortcut(historyShortcut.shortcut, for: .openHistoryWindow)
        }
        if let dictionaryShortcut = general.quickAddToDictionaryShortcut {
            ShortcutStore.setShortcut(dictionaryShortcut.shortcut, for: .quickAddToDictionary)
        }
        if let enhancementShortcut = general.toggleEnhancementShortcut {
            ShortcutStore.setShortcut(enhancementShortcut.shortcut, for: .toggleEnhancement)
        }

        if let shortcutRawValue = general.primaryRecordingShortcutRawValue,
           let shortcut = RecordingShortcutManager.ShortcutSelection(rawValue: shortcutRawValue) {
            recordingShortcutManager.primaryRecordingShortcut = shortcut
        }
        if let secondaryShortcutRawValue = general.secondaryRecordingShortcutRawValue,
           let secondaryShortcut = RecordingShortcutManager.ShortcutSelection(rawValue: secondaryShortcutRawValue) {
            recordingShortcutManager.secondaryRecordingShortcut = secondaryShortcut
        }
        if let modeRawValue = general.primaryRecordingShortcutModeRawValue,
           let mode = RecordingShortcutManager.Mode(rawValue: modeRawValue) {
            recordingShortcutManager.primaryRecordingShortcutMode = mode
        }
        if let secondaryModeRawValue = general.secondaryRecordingShortcutModeRawValue,
           let secondaryMode = RecordingShortcutManager.Mode(rawValue: secondaryModeRawValue) {
            recordingShortcutManager.secondaryRecordingShortcutMode = secondaryMode
        }
        if let middleClickEnabled = general.isMiddleClickToggleEnabled {
            recordingShortcutManager.isMiddleClickToggleEnabled = middleClickEnabled
        }
        if let middleClickDelay = general.middleClickActivationDelay {
            recordingShortcutManager.middleClickActivationDelay = middleClickDelay
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
