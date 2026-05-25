import SwiftUI

struct PowerModeConfigEditorView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    let onDismiss: () -> Void

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    @State private var draft: PowerModeConfigDraft
    @State private var validationErrors: [PowerModeValidationError] = []
    @State private var showValidationAlert = false
    @State private var promptEditorMode: PromptEditorView.Mode?
    @State private var promptEditorID = UUID()
    @State private var didSaveConfiguration = false

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        self.onDismiss = onDismiss
        _draft = State(initialValue: PowerModeConfigDraft(mode: mode, powerModeManager: powerModeManager))
    }

    var body: some View {
        Group {
            if let promptEditorMode {
                PromptEditorView(
                    mode: promptEditorMode,
                    onDismiss: closePromptEditor,
                    onSave: handlePromptSaved,
                    onDelete: handlePromptDeleted
                )
                .environmentObject(enhancementService)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(promptEditorID)
            } else {
                PowerModeConfigFormView(
                    mode: mode,
                    powerModeManager: powerModeManager,
                    draft: $draft,
                    validationErrors: $validationErrors,
                    showValidationAlert: $showValidationAlert,
                    onDismiss: onDismiss,
                    onSave: saveConfiguration,
                    onDelete: deleteConfiguration,
                    openPromptEditor: openPromptEditor
                )
            }
        }
        .onAppear(perform: prepareView)
        .onDisappear(perform: cleanupUnsavedShortcutIfNeeded)
        .onExitCommand(perform: handleExitCommand)
    }

    private func openPromptEditor(mode: PromptEditorView.Mode) {
        promptEditorID = UUID()
        promptEditorMode = mode
    }

    private func closePromptEditor() {
        promptEditorMode = nil
    }

    private func handlePromptSaved(_ prompt: CustomPrompt) {
        draft.selectedPromptId = prompt.id
        closePromptEditor()
    }

    private func handlePromptDeleted(_ prompt: CustomPrompt) {
        enhancementService.deletePrompt(prompt)
        if draft.selectedPromptId == prompt.id {
            draft.selectedPromptId = enhancementService.allPrompts.first?.id
        }
    }

    private func handleExitCommand() {
        if promptEditorMode != nil {
            closePromptEditor()
        } else {
            onDismiss()
        }
    }

    private func prepareView() {
        if case .add = mode {
            draft.applyAddModeDefaults(aiService: aiService)
        }

        draft.ensurePromptSelection(firstPromptId: enhancementService.allPrompts.first?.id)

        if let selectedModelName = draft.effectiveModelName(
            fallback: transcriptionModelManager.currentTranscriptionModel?.name
        ),
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModelName }),
           model.provider != .gemini {
            draft.useCompatibleLanguage(for: model)
        }
    }

    private func saveConfiguration() {
        let config = draft.makeConfig(mode: mode)
        let validator = PowerModeValidator(powerModeManager: powerModeManager)
        validationErrors = validator.validateForSave(config: config, mode: mode)

        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }

        if draft.isDefault {
            powerModeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            powerModeManager.addConfiguration(config)
        case .edit:
            powerModeManager.updateConfiguration(config)
        }

        didSaveConfiguration = true
        onDismiss()
    }

    private func deleteConfiguration() {
        powerModeManager.removeConfiguration(with: draft.id)
        onDismiss()
    }

    private func cleanupUnsavedShortcutIfNeeded() {
        guard case .add = mode, !didSaveConfiguration else {
            return
        }

        ShortcutStore.removeShortcutStorage(for: .powerMode(draft.id))
    }
}
