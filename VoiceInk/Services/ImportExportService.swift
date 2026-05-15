import Foundation
import AppKit
import UniformTypeIdentifiers
import LaunchAtLogin
import SwiftData

private final class BackupOptions: NSObject {
    let view: NSView

    private let allButton: NSButton
    private let individualButton: NSButton
    private let categoryButtons: [BackupCategory: NSButton]

    override init() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 188))
        self.allButton = NSButton(radioButtonWithTitle: "All", target: nil, action: nil)
        self.individualButton = NSButton(radioButtonWithTitle: "Individual categories", target: nil, action: nil)

        var buttons: [BackupCategory: NSButton] = [:]
        for category in BackupCategory.allCases {
            let button = NSButton(checkboxWithTitle: category.title, target: nil, action: nil)
            button.state = .on
            button.isEnabled = false
            buttons[category] = button
        }
        self.categoryButtons = buttons

        super.init()

        allButton.state = .on
        individualButton.state = .off
        allButton.target = self
        allButton.action = #selector(modeChanged(_:))
        individualButton.target = self
        individualButton.action = #selector(modeChanged(_:))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let categoryStack = NSStackView()
        categoryStack.orientation = .vertical
        categoryStack.alignment = .leading
        categoryStack.spacing = 6
        categoryStack.translatesAutoresizingMaskIntoConstraints = false

        for category in BackupCategory.allCases {
            guard let button = categoryButtons[category] else { continue }
            button.target = self
            button.action = #selector(categoryChanged(_:))
            categoryStack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        view.addSubview(categoryStack)
        stack.addArrangedSubview(allButton)
        stack.addArrangedSubview(individualButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            categoryStack.topAnchor.constraint(equalTo: individualButton.bottomAnchor, constant: 6),
            categoryStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            categoryStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    var selectedCategories: Set<BackupCategory> {
        if allButton.state == .on {
            return Set(BackupCategory.allCases)
        }

        return Set(categoryButtons.compactMap { category, button in
            button.state == .on ? category : nil
        })
    }

    @objc private func modeChanged(_ sender: NSButton) {
        let useAll = sender == allButton
        allButton.state = useAll ? .on : .off
        individualButton.state = useAll ? .off : .on
        setCategoryButtonsEnabled(!useAll)
    }

    @objc private func categoryChanged(_ sender: NSButton) {
        guard individualButton.state != .on else { return }
        allButton.state = .off
        individualButton.state = .on
        setCategoryButtonsEnabled(true)
    }

    private func setCategoryButtonsEnabled(_ isEnabled: Bool) {
        for button in categoryButtons.values {
            button.isEnabled = isEnabled
        }
    }
}

class ImportExportService {
    static let shared = ImportExportService()
    private let currentSettingsVersion: String

    private let keyIsAudioCleanupEnabled = "IsAudioCleanupEnabled"
    private let keyIsTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    private let keyTranscriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    private let keyAudioRetentionPeriod = "AudioRetentionPeriod"

    private let keyIsTextFormattingEnabled = "IsTextFormattingEnabled"
    private let keyRemovePunctuation = "RemovePunctuation"
    private let keyLowercaseTranscription = "LowercaseTranscription"

    private init() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentSettingsVersion = version
        } else {
            self.currentSettingsVersion = "0.0.0"
        }
    }

    @MainActor
    func exportSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext) {
        let powerModeManager = PowerModeManager.shared
        let emojiManager = EmojiManager.shared

        let exportablePrompts = enhancementService.customPrompts.filter { !$0.isPredefined }

        let powerConfigs = powerModeManager.configurations
        let powerModeShortcuts = Dictionary(uniqueKeysWithValues: powerConfigs.compactMap { config -> (String, ShortcutBackup)? in
            guard let shortcut = ShortcutStore.shortcut(for: .powerMode(config.id)) else { return nil }
            return (config.id.uuidString, ShortcutBackup(shortcut))
        })

        // Export custom models
        let customModels = CustomCloudModelManager.shared.customModels.map { CustomModelBackup(model: $0) }

        // Fetch vocabulary words from SwiftData
        var exportedDictionaryItems: [WordBackup]? = nil
        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
        if let items = try? modelContext.fetch(vocabularyDescriptor), !items.isEmpty {
            exportedDictionaryItems = items.map { WordBackup(word: $0.word) }
        }

        // Fetch word replacements from SwiftData
        var exportedWordReplacements: [String: String]? = nil
        let replacementsDescriptor = FetchDescriptor<WordReplacement>()
        if let replacements = try? modelContext.fetch(replacementsDescriptor), !replacements.isEmpty {
            exportedWordReplacements = Dictionary(replacements.map { ($0.originalText, $0.replacementText) }, uniquingKeysWith: { _, last in last })
        }

        let generalSettingsToExport = GeneralBackup(
            primaryRecordingShortcut: ShortcutStore.shortcut(for: .primaryRecording).map(ShortcutBackup.init),
            secondaryRecordingShortcut: ShortcutStore.shortcut(for: .secondaryRecording).map(ShortcutBackup.init),
            pasteLastTranscriptionShortcut: ShortcutStore.shortcut(for: .pasteLastTranscription).map(ShortcutBackup.init),
            pasteLastEnhancementShortcut: ShortcutStore.shortcut(for: .pasteLastEnhancement).map(ShortcutBackup.init),
            retryLastTranscriptionShortcut: ShortcutStore.shortcut(for: .retryLastTranscription).map(ShortcutBackup.init),
            cancelRecorderShortcut: ShortcutStore.shortcut(for: .cancelRecorder).map(ShortcutBackup.init),
            openHistoryWindowShortcut: ShortcutStore.shortcut(for: .openHistoryWindow).map(ShortcutBackup.init),
            quickAddToDictionaryShortcut: ShortcutStore.shortcut(for: .quickAddToDictionary).map(ShortcutBackup.init),
            toggleEnhancementShortcut: ShortcutStore.shortcut(for: .toggleEnhancement).map(ShortcutBackup.init),
            primaryRecordingShortcutRawValue: recordingShortcutManager.primaryRecordingShortcut.rawValue,
            secondaryRecordingShortcutRawValue: recordingShortcutManager.secondaryRecordingShortcut.rawValue,
            primaryRecordingShortcutModeRawValue: recordingShortcutManager.primaryRecordingShortcutMode.rawValue,
            secondaryRecordingShortcutModeRawValue: recordingShortcutManager.secondaryRecordingShortcutMode.rawValue,
            isMiddleClickToggleEnabled: recordingShortcutManager.isMiddleClickToggleEnabled,
            middleClickActivationDelay: recordingShortcutManager.middleClickActivationDelay,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            isMenuBarOnly: menuBarManager.isMenuBarOnly,
            recorderType: recorderUIManager.recorderType,
            isTranscriptionCleanupEnabled: UserDefaults.standard.bool(forKey: keyIsTranscriptionCleanupEnabled),
            transcriptionRetentionMinutes: UserDefaults.standard.integer(forKey: keyTranscriptionRetentionMinutes),
            isAudioCleanupEnabled: UserDefaults.standard.bool(forKey: keyIsAudioCleanupEnabled),
            audioRetentionPeriod: UserDefaults.standard.integer(forKey: keyAudioRetentionPeriod),

            isSoundFeedbackEnabled: soundManager.isEnabled,
            isSystemMuteEnabled: mediaController.isSystemMuteEnabled,
            isPauseMediaEnabled: playbackController.isPauseMediaEnabled,
            audioResumptionDelay: mediaController.audioResumptionDelay,
            isTextFormattingEnabled: UserDefaults.standard.bool(forKey: keyIsTextFormattingEnabled),
            removePunctuation: UserDefaults.standard.bool(forKey: keyRemovePunctuation),
            lowercaseTranscription: UserDefaults.standard.bool(forKey: keyLowercaseTranscription),
            isExperimentalFeaturesEnabled: UserDefaults.standard.bool(forKey: "isExperimentalFeaturesEnabled"),
            restoreClipboardAfterPaste: UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste"),
            clipboardRestoreDelay: UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            useAppleScriptPaste: UserDefaults.standard.bool(forKey: "useAppleScriptPaste")
        )

        let exportedSettings = BackupFile(
            version: currentSettingsVersion,
            customPrompts: exportablePrompts,
            powerModeConfigs: powerConfigs,
            powerModeShortcuts: powerModeShortcuts.isEmpty ? nil : powerModeShortcuts,
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
    func importSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import VoiceInk Settings"
        openPanel.message = "Choose a settings backup, then select what you want to import."

        guard openPanel.runModal() == .OK else {
            showAlert(title: "Import Canceled", message: "The settings import operation was canceled.")
            return
        }

        guard let url = openPanel.url else {
            showAlert(title: "Import Error", message: "Could not get the file URL from the open panel.")
            return
        }

        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let backup = try decoder.decode(BackupFile.self, from: jsonData)

            if backup.version != currentSettingsVersion {
                showAlert(title: "Version Mismatch", message: "The imported settings file (version \(backup.version)) is from a different version than your application (version \(currentSettingsVersion)). Proceeding with import, but be aware of potential incompatibilities.")
            }

            guard let selectedCategories = presentImportSelectionDialog() else {
                showAlert(title: "Import Canceled", message: "No settings were imported.")
                return
            }

            guard !selectedCategories.isEmpty else {
                showAlert(title: "Import Error", message: "Select at least one category to import.")
                return
            }

            try BackupImporter.apply(
                backup,
                categories: selectedCategories,
                enhancementService: enhancementService,
                recordingShortcutManager: recordingShortcutManager,
                menuBarManager: menuBarManager,
                mediaController: mediaController,
                playbackController: playbackController,
                soundManager: soundManager,
                recorderUIManager: recorderUIManager,
                modelContext: modelContext,
                transcriptionModelManager: transcriptionModelManager
            )

            showImportSuccessAlert(
                message: "Settings imported successfully from \(url.lastPathComponent).\n\nImported: \(categorySummary(for: selectedCategories)).",
                needsAPIKeyReminder: needsAPIKeyReminder(for: selectedCategories)
            )
        } catch {
            showAlert(title: "Import Error", message: "Error importing settings: \(error.localizedDescription). The file might be corrupted or not in the correct format.")
        }
    }

    private func presentImportSelectionDialog() -> Set<BackupCategory>? {
        let accessory = BackupOptions()
        let alert = NSAlert()
        alert.messageText = "Import Settings"
        alert.informativeText = "Choose what to import from this backup."
        alert.alertStyle = .informational
        alert.accessoryView = accessory.view
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return accessory.selectedCategories
    }

    private func categorySummary(for categories: Set<BackupCategory>) -> String {
        if categories == Set(BackupCategory.allCases) {
            return "All settings"
        }

        return BackupCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    private func needsAPIKeyReminder(for categories: Set<BackupCategory>) -> Bool {
        !categories.isDisjoint(with: [.prompts, .powerMode, .customModels])
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

    private func showImportSuccessAlert(message: String, needsAPIKeyReminder: Bool) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Import Successful"
            var informativeText = message
            if needsAPIKeyReminder {
                informativeText += "\n\nIMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section."
            }
            informativeText += "\n\nIt is recommended to restart VoiceInk for all changes to take full effect."
            alert.informativeText = informativeText
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            if needsAPIKeyReminder {
                alert.addButton(withTitle: "Configure API Keys")
            }
            
            let response = alert.runModal()
            if needsAPIKeyReminder && response == .alertSecondButtonReturn {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Enhancement"]
                )
            }
        }
    }
}
