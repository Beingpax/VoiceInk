import SwiftUI

struct ModeConfigFormView: View {
    let mode: ConfigurationMode
    let modeManager: ModeManager
    @Binding var draft: ModeConfigDraft
    @Binding var validationErrors: [ModeValidationError]
    @Binding var showValidationAlert: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let openPromptEditor: (PromptEditorView.Mode) -> Void

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var modeWarmupStore: ModeFormWarmupStore
    @FocusState private var isNameFieldFocused: Bool

    @State private var isShowingIconPicker = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isContextAwarenessExpanded = false

    private var effectiveModelName: String? {
        draft.selectedTranscriptionModelName
    }

    private var warmupSnapshot: ModeFormWarmupSnapshot {
        modeWarmupStore.snapshot
    }

    private var selectedTranscriptionModel: (any TranscriptionModel)? {
        warmupSnapshot.transcriptionModel(named: effectiveModelName)
    }

    private var selectedPrompt: CustomPrompt? {
        guard let selectedPromptId = draft.selectedPromptId else { return nil }
        return warmupSnapshot.prompts.first { $0.id == selectedPromptId }
    }

    private var aiProviderOptions: [AIProvider] {
        warmupSnapshot.connectedAIProviders
    }

    private var configuredSelectedAIProvider: AIProvider? {
        let selectedProvider: AIProvider?
        if let providerName = draft.selectedAIProvider {
            selectedProvider = AIProvider(rawValue: providerName)
        } else {
            selectedProvider = aiProviderOptions.first
        }

        guard let selectedProvider,
              selectedProvider.supportsEnhancement,
              aiProviderOptions.contains(selectedProvider) else { return nil }

        return selectedProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            formContent

            footer
        }
        .onAppear {
            applyOutputRules()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
        .onChange(of: draft.isAIEnhancementEnabled) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedPromptId) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedAIProvider) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedAIModel) { _, _ in
            applyOutputRules()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                isShowingIconPicker.toggle()
            } label: {
                ModeIconView(icon: draft.icon, size: draft.icon.kind == .emoji ? 22 : 18)
                    .frame(width: 36, height: 36)
                    .background(
                        AppCardBackground(isSelected: false, cornerRadius: 18)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingIconPicker, arrowEdge: .bottom) {
                ModeIconPickerView(
                    selectedIcon: $draft.icon,
                    isPresented: $isShowingIconPicker
                )
            }

            TextField("Mode name", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .focused($isNameFieldFocused)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var formContent: some View {
        Form {
            ModeTriggerSection(
                appConfigs: $draft.appConfigs,
                websiteConfigs: $draft.websiteConfigs,
                triggerGroups: $draft.triggerGroups,
                modeId: draft.id,
                cleanURL: modeManager.cleanURL
            )
            transcriptionSection
            aiEnhancementSection
            advancedSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete Mode?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if case .edit = mode {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(draft.name)'? This action cannot be undone.")
        }
        .modeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
            if warmupSnapshot.usableTranscriptionModels.isEmpty {
                Text("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab.")
                    .foregroundColor(.secondary)
            } else {
                let modelBinding = Binding<String?>(
                    get: { draft.selectedTranscriptionModelName },
                    set: { draft.selectedTranscriptionModelName = $0 }
                )

                Picker("Model", selection: modelBinding) {
                    ForEach(warmupSnapshot.usableTranscriptionModels, id: \.name) { model in
                        Text(model.displayName).tag(model.name as String?)
                    }
                }
                .onChange(of: draft.selectedTranscriptionModelName) { _, newModelName in
                    if let modelName = newModelName,
                       let model = warmupSnapshot.transcriptionModel(named: modelName) {
                        draft.isRealtimeTranscriptionEnabled = TranscriptionRealtimeSupport.isAvailable(for: model)
                        if model.provider == .gemini {
                            draft.selectedLanguage = "auto"
                        } else {
                            draft.useCompatibleLanguage(for: model)
                        }
                    }
                }

                realtimeToggle
            }

            languagePicker

            ExpandableSettingsRow(
                title: "Transcription Formatting",
                isExpanded: $draft.isTranscriptionFormattingExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $draft.isTextFormattingEnabled) {
                        HStack(spacing: 4) {
                            Text("Paragraph breaks")
                            InfoTip("Apply intelligent text formatting to break large block of text into paragraphs.")
                        }
                    }

                    Picker(selection: $draft.punctuationCleanupMode) {
                        ForEach(PunctuationCleanupMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Punctuation")
                            InfoTip("Keep preserves punctuation as transcribed. Remove all strips punctuation marks from the transcribed text. Remove trailing period only removes a final period from the transcribed text.")
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle(isOn: $draft.lowercaseTranscription) {
                        HStack(spacing: 4) {
                            Text("Lowercase output")
                            InfoTip("Convert transcription output to lowercase.")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var realtimeToggle: some View {
        if let model = selectedTranscriptionModel,
           TranscriptionRealtimeSupport.isAvailable(for: model) {
            Toggle("Real-time", isOn: $draft.isRealtimeTranscriptionEnabled)
                .disabled(TranscriptionRealtimeSupport.isRequired(for: model))
                .onAppear {
                    if TranscriptionRealtimeSupport.isRequired(for: model) {
                        draft.isRealtimeTranscriptionEnabled = true
                    }
                }
                .onChange(of: draft.isRealtimeTranscriptionEnabled) { _, _ in
                    draft.useCompatibleLanguage(for: model)
                }
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        if languageSelectionDisabled() {
            LabeledContent("Language") {
                Text("Autodetected")
                    .foregroundColor(.secondary)
            }
            .onAppear {
                draft.selectedLanguage = "auto"
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = warmupSnapshot.transcriptionModel(named: selectedModel),
                  modelInfo.isMultilingualModel {
            let languageBinding = Binding<String?>(
                get: { effectiveLanguage(for: modelInfo) },
                set: { draft.selectedLanguage = $0 }
            )

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Language")
                }

                Spacer(minLength: 12)

                if modelInfo.provider == .nativeApple {
                    NativeAppleLanguageAssetControl(
                        localeIdentifier: effectiveLanguage(for: modelInfo),
                        isVisible: true,
                        startsDownloadAutomatically: true,
                        allowsReservationReplacement: true
                    )
                    .layoutPriority(1)
                    .frame(width: 28, height: 24)
                }

                Picker("", selection: languageBinding) {
                    ForEach(availableLanguages(for: modelInfo).sorted(by: {
                        if $0.key == "auto" { return true }
                        if $1.key == "auto" { return false }
                        return $0.value < $1.value
                    }), id: \.key) { key, value in
                        Text(value).tag(key as String?)
                    }
                }
                .labelsHidden()
            }
            .onAppear {
                draft.selectedLanguage = effectiveLanguage(for: modelInfo)
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = warmupSnapshot.transcriptionModel(named: selectedModel),
                  !modelInfo.isMultilingualModel {
            EmptyView()
                .onAppear {
                    if draft.selectedLanguage == nil {
                        draft.selectedLanguage = "en"
                    }
                }
        }
    }

    private var aiEnhancementSection: some View {
        Section("AI Enhancement") {
            Toggle("AI Enhancement", isOn: $draft.isAIEnhancementEnabled)
                .onChange(of: draft.isAIEnhancementEnabled) { _, newValue in
                    if newValue {
                        if configuredSelectedAIProvider == nil {
                            draft.selectedAIProvider = aiProviderOptions.first?.rawValue
                            draft.selectedAIModel = nil
                        }
                        if draft.selectedAIModel == nil,
                           let provider = configuredSelectedAIProvider,
                           provider != .localCLI {
                            draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                        }
                        if draft.selectedPromptId == nil {
                            draft.selectedPromptId = warmupSnapshot.firstPromptId
                        }
                        if configuredSelectedAIProvider == .ollama {
                            aiService.refreshOllamaAvailabilityInBackground()
                        }
                    }
                }

            let providerBinding = Binding<AIProvider>(
                get: {
                    configuredSelectedAIProvider ?? aiProviderOptions.first ?? .gemini
                },
                set: { newValue in
                    draft.selectedAIProvider = newValue.rawValue
                    draft.selectedAIModel = nil
                }
            )

            if draft.isAIEnhancementEnabled {
                let providerOptions = aiProviderOptions

                if providerOptions.isEmpty {
                    LabeledContent("AI Provider") {
                        Text("No providers connected")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    Picker("AI Provider", selection: providerBinding) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: draft.selectedAIProvider) { _, newValue in
                        if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                            switch provider {
                            case .localCLI:
                                draft.selectedAIModel = nil
                            case .ollama:
                                if draft.selectedAIModel == nil || draft.selectedAIModel?.isEmpty == true {
                                    draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                                }
                                aiService.refreshOllamaAvailabilityInBackground()
                            default:
                                draft.selectedAIModel = provider.defaultModel
                            }
                        }
                    }
                }

                if let provider = configuredSelectedAIProvider {
                    aiModelPicker(for: provider)
                    promptPicker
                    contextAwarenessRow
                }
            }
        }
    }

    @ViewBuilder
    private func aiModelPicker(for provider: AIProvider) -> some View {
        if provider == .localCLI {
            LabeledContent("AI Model") {
                Text("Default")
                    .foregroundColor(.secondary)
            }
            .onAppear {
                draft.selectedAIModel = nil
            }
        } else {
            let models = aiModelOptions(for: provider)
            if models.isEmpty {
                LabeledContent("AI Model") {
                    Text(provider == .openRouter ? "No models loaded" : "No models available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                let modelBinding = Binding<String>(
                    get: {
                        if let model = draft.selectedAIModel, !model.isEmpty { return model }
                        return warmupSnapshot.selectedModel(for: provider)
                    },
                    set: { newModelValue in
                        draft.selectedAIModel = newModelValue
                    }
                )

                Picker("AI Model", selection: modelBinding) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                if provider == .openRouter {
                    Button("Refresh Models") {
                        Task { await aiService.fetchOpenRouterModels() }
                    }
                    .help("Refresh models")
                }
            }
        }
    }

    private func aiModelOptions(for provider: AIProvider) -> [String] {
        var models = warmupSnapshot.availableModels(for: provider)

        if let selectedModel = draft.selectedAIModel,
           !selectedModel.isEmpty,
           !models.contains(selectedModel) {
            models.insert(selectedModel, at: 0)
        }

        return models
    }

    private var promptPicker: some View {
        HStack(spacing: 8) {
            Text("Prompt")

            Spacer(minLength: 12)

            if warmupSnapshot.prompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Picker("", selection: $draft.selectedPromptId) {
                    ForEach(warmupSnapshot.prompts) { prompt in
                        Text(prompt.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(prompt.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if let selectedPrompt {
                Button {
                    openPromptEditor(.edit(selectedPrompt))
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }

            AddIconButton(helpText: "Add prompt") {
                openPromptEditor(.add)
            }
        }
    }

    private var contextAwarenessRow: some View {
        ExpandableSettingsRow(
            title: "Context Awareness",
            isExpanded: $isContextAwarenessExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                contextToggles
            }
        }
    }

    private var contextToggles: some View {
        Group {
            Toggle(isOn: $draft.useSelectedTextContext) {
                HStack(spacing: 4) {
                    Text("Selected Text")
                    InfoTip("Use selected text from the active app as context for this mode.")
                }
            }

            Toggle(isOn: $draft.useClipboardContext) {
                HStack(spacing: 4) {
                    Text("Clipboard")
                    InfoTip("Use clipboard text as context for this mode.")
                }
            }

            Toggle(isOn: $draft.useScreenCapture) {
                HStack(spacing: 4) {
                    Text("Screen")
                    InfoTip("Use captured on-screen text as context for this mode.")
                }
            }
        }
    }

    private var outputChoices: [ModeOutputMode] {
        ModeOutputMode.choices(canRespond: canRespond)
    }

    private var canRespond: Bool {
        draft.isAIEnhancementEnabled &&
            selectedPrompt != nil &&
            configuredSelectedAIProvider != nil
    }

    private func applyOutputRules() {
        draft.applyOutputRules(canRespond: canRespond)
    }

    private var advancedSection: some View {
        Section("Advanced") {
            if canRespond {
                Picker("Output", selection: $draft.outputMode) {
                    ForEach(outputChoices, id: \.self) { outputMode in
                        Label(outputMode.displayName, systemImage: outputMode.iconName)
                            .tag(outputMode)
                    }
                }
                .onChange(of: draft.outputMode) { _, _ in
                    applyOutputRules()
                }
            }

            if draft.outputMode.usesPasteOptions {
                Toggle(isOn: $draft.isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default mode is used when no specific app or website matches are found.")
                    }
                }

                Picker(selection: $draft.autoSendKey) {
                    ForEach(AutoSendKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Auto Send")
                        InfoTip("Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts.")
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                if case .edit = mode {
                    Button("Delete", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Cancel") { onDismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    onSave()
                } label: {
                    Text("Save Changes")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func languageSelectionDisabled() -> Bool {
        guard let selectedModelName = effectiveModelName,
              let model = warmupSnapshot.transcriptionModel(named: selectedModelName)
        else { return false }
        return model.provider == .gemini
    }

    private func availableLanguages(for model: any TranscriptionModel) -> [String: String] {
        TranscriptionLanguageSupport.languages(for: model, realtimeEnabled: draft.isRealtimeTranscriptionEnabled)
    }

    private func effectiveLanguage(for model: any TranscriptionModel) -> String {
        TranscriptionLanguageSupport.validLanguageOrFallback(
            draft.selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage"),
            for: model,
            realtimeEnabled: draft.isRealtimeTranscriptionEnabled
        )
    }

}
