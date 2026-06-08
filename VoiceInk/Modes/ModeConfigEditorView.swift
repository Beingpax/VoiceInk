import SwiftUI

struct ModeConfigEditorView: View {
    let mode: ConfigurationMode
    let modeManager: ModeManager
    let onDismiss: () -> Void

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var modeWarmupStore: ModeFormWarmupStore

    @State private var draft: ModeConfigDraft
    @State private var validationErrors: [ModeValidationError] = []
    @State private var showValidationAlert = false
    @State private var promptEditorMode: PromptEditorView.Mode?
    @State private var promptEditorID = UUID()
    @State private var didSaveConfiguration = false

    init(mode: ConfigurationMode, modeManager: ModeManager, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.modeManager = modeManager
        self.onDismiss = onDismiss
        _draft = State(initialValue: ModeConfigDraft(mode: mode, modeManager: modeManager))
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
                ModeConfigFormView(
                    mode: mode,
                    modeManager: modeManager,
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
        modeWarmupStore.configure(
            aiService: aiService,
            enhancementService: enhancementService,
            transcriptionModelManager: transcriptionModelManager
        )

        let snapshot = modeWarmupStore.snapshot

        if case .add = mode {
            draft.applyAddModeDefaults(snapshot: snapshot)
            draft.inheritUsableTranscriptionModelSelection(from: snapshot)
        } else {
            draft.ensureTranscriptionModelSelection(
                fallback: snapshot.usableTranscriptionModels.first?.name
            )
        }

        draft.ensurePromptSelection(firstPromptId: snapshot.firstPromptId)

        if let selectedModelName = draft.selectedTranscriptionModelName,
           let model = snapshot.transcriptionModel(named: selectedModelName),
           model.provider != .gemini {
            draft.useCompatibleLanguage(for: model)
        }
    }

    private func saveConfiguration() {
        let config = draft.makeConfig(mode: mode)
        let validator = ModeValidator(modeManager: modeManager)
        validationErrors = validator.validateForSave(config: config, mode: mode)

        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }

        if draft.isDefault {
            modeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            modeManager.addConfiguration(config)
        case .edit:
            modeManager.updateConfiguration(config)
        }

        didSaveConfiguration = true
        onDismiss()
    }

    private func deleteConfiguration() {
        modeManager.removeConfiguration(with: draft.id)
        onDismiss()
    }

    private func cleanupUnsavedShortcutIfNeeded() {
        guard case .add = mode, !didSaveConfiguration else {
            return
        }

        ShortcutStore.removeShortcutStorage(for: .mode(draft.id))
    }
}
