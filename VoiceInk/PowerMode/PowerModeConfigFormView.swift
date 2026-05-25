import SwiftUI

struct PowerModeConfigFormView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    @Binding var draft: PowerModeConfigDraft
    @Binding var validationErrors: [PowerModeValidationError]
    @Binding var showValidationAlert: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let openPromptEditor: (PromptEditorView.Mode) -> Void

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @FocusState private var isNameFieldFocused: Bool

    @State private var isShowingEmojiPicker = false
    @State private var isShowingAppPicker = false
    @State private var isShowingWebsitePicker = false
    @State private var installedApps: [InstalledAppInfo] = []
    @State private var searchText = ""
    @State private var newWebsiteURL = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var isContextAwarenessExpanded = false

    private var effectiveModelName: String? {
        draft.effectiveModelName(fallback: transcriptionModelManager.currentTranscriptionModel?.name)
    }

    private var filteredApps: [InstalledAppInfo] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedPrompt: CustomPrompt? {
        guard let selectedPromptId = draft.selectedPromptId else { return nil }
        return enhancementService.allPrompts.first { $0.id == selectedPromptId }
    }

    private var aiProviderOptions: [AIProvider] {
        aiService.connectedProviders
    }

    private var configuredSelectedAIProvider: AIProvider? {
        let selectedProvider: AIProvider?
        if let providerName = draft.selectedAIProvider {
            selectedProvider = AIProvider(rawValue: providerName)
        } else {
            selectedProvider = aiService.selectedProvider
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                isShowingEmojiPicker.toggle()
            } label: {
                Text(draft.emoji)
                    .font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingEmojiPicker, arrowEdge: .bottom) {
                EmojiPickerView(
                    selectedEmoji: $draft.emoji,
                    isPresented: $isShowingEmojiPicker
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
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var formContent: some View {
        Form {
            triggerScenariosSection
            transcriptionSection
            aiEnhancementSection
            advancedSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
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
        .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
    }

    private var triggerScenariosSection: some View {
        Section("Trigger Scenarios") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Applications")
                    Spacer()
                    AddIconButton(helpText: "Add application") {
                        installedApps = InstalledApps.load()
                        isShowingAppPicker = true
                    }
                    .popover(isPresented: $isShowingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(
                            installedApps: filteredApps,
                            selectedAppConfigs: $draft.appConfigs,
                            searchText: $searchText
                        )
                    }
                }

                if !draft.appConfigs.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)], spacing: 10) {
                        ForEach(draft.appConfigs) { appConfig in
                            ZStack(alignment: .topTrailing) {
                                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 26, height: 26)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(NSColor.controlBackgroundColor))
                                        )
                                }

                                Button {
                                    draft.appConfigs.removeAll(where: { $0.id == appConfig.id })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Websites")
                    Spacer()
                    AddIconButton(helpText: "Add website") {
                        isShowingWebsitePicker = true
                    }
                    .popover(isPresented: $isShowingWebsitePicker, arrowEdge: .bottom) {
                        WebsitePickerPopover(
                            websiteURL: $newWebsiteURL,
                            onAdd: addWebsite
                        )
                    }
                }

                if !draft.websiteConfigs.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                        ForEach(draft.websiteConfigs) { urlConfig in
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .foregroundColor(.secondary)
                                Text(urlConfig.url)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    draft.websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
            if transcriptionModelManager.usableModels.isEmpty {
                Text("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab.")
                    .foregroundColor(.secondary)
            } else {
                let modelBinding = Binding<String?>(
                    get: { draft.selectedTranscriptionModelName ?? transcriptionModelManager.currentTranscriptionModel?.name },
                    set: { draft.selectedTranscriptionModelName = $0 }
                )

                Picker("Model", selection: modelBinding) {
                    ForEach(transcriptionModelManager.usableModels, id: \.name) { model in
                        Text(model.displayName).tag(model.name as String?)
                    }
                }
                .onChange(of: draft.selectedTranscriptionModelName) { _, newModelName in
                    if let modelName = newModelName ?? transcriptionModelManager.currentTranscriptionModel?.name,
                       let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }) {
                        if model.provider == .gemini {
                            draft.selectedLanguage = "auto"
                        } else {
                            draft.useCompatibleLanguage(for: model)
                        }
                    }
                }
            }

            languagePicker

            ExpandableSettingsRow(
                title: "Transcript Formatting",
                isExpanded: $draft.isTranscriptFormattingExpanded
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
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
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
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
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
                            draft.selectedAIModel = aiService.selectedModel(for: provider)
                        }
                        if draft.selectedPromptId == nil {
                            draft.selectedPromptId = enhancementService.allPrompts.first?.id
                        }
                        if configuredSelectedAIProvider == .ollama {
                            aiService.refreshOllamaAvailabilityInBackground()
                        }
                    }
                }

            let providerBinding = Binding<AIProvider>(
                get: {
                    configuredSelectedAIProvider ?? aiProviderOptions.first ?? aiService.selectedProvider
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
                                    draft.selectedAIModel = aiService.selectedModel(for: provider)
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
                        return aiService.selectedModel(for: provider)
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
        var models = aiService.availableModels(for: provider)

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

            if enhancementService.allPrompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Picker("", selection: $draft.selectedPromptId) {
                    ForEach(enhancementService.allPrompts) { prompt in
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

    private var advancedSection: some View {
        Section("Advanced") {
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

            HStack {
                Text("Keyboard Shortcut")
                InfoTip("Assign a unique keyboard shortcut to instantly activate this mode and start recording.")

                Spacer()

                ShortcutRecorder(action: .powerMode(draft.id))
                    .frame(minHeight: 28)
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
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func languageSelectionDisabled() -> Bool {
        guard let selectedModelName = effectiveModelName,
              let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModelName })
        else { return false }
        return model.provider == .gemini
    }

    private func availableLanguages(for model: any TranscriptionModel) -> [String: String] {
        TranscriptionLanguageSupport.languages(for: model)
    }

    private func effectiveLanguage(for model: any TranscriptionModel) -> String {
        TranscriptionLanguageSupport.validLanguageOrFallback(
            draft.selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage"),
            for: model
        )
    }

    private func addWebsite() {
        let trimmedURL = newWebsiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let cleanedURL = powerModeManager.cleanURL(trimmedURL)
        guard !draft.websiteConfigs.contains(where: { $0.url == cleanedURL }) else {
            newWebsiteURL = ""
            return
        }

        draft.websiteConfigs.append(URLConfig(url: cleanedURL))
        newWebsiteURL = ""
    }

}
