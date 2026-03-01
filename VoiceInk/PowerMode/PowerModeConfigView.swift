import SwiftUI
import KeyboardShortcuts

struct ConfigurationView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var isNameFieldFocused: Bool
    
    // State for configuration
    @State private var configName: String = "New Power Mode"
    @State private var selectedEmoji: String = "💼"
    @State private var isShowingEmojiPicker = false
    @State private var isShowingAppPicker = false
    @State private var isAIEnhancementEnabled: Bool
    @State private var selectedPromptId: UUID?
    @State private var selectedTranscriptionModelName: String?
    @State private var selectedLanguage: String?
    @State private var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State private var searchText = ""
    
    // Validation state
    @State private var validationErrors: [PowerModeValidationError] = []
    @State private var showValidationAlert = false
    
    // New state for AI provider and model
    @State private var selectedAIProvider: String?
    @State private var selectedAIModel: String?
    
    // App and Website configurations
    @State private var selectedAppConfigs: [AppConfig] = []
    @State private var websiteConfigs: [URLConfig] = []
    @State private var newWebsiteURL: String = ""
    
    // New state for screen capture toggle
    @State private var useScreenCapture = false
    @State private var isAutoSendEnabled = false
    @State private var isDefault = false
    
    @State private var isShowingDeleteConfirmation = false

    // PowerMode hotkey configuration
    @State private var powerModeConfigId: UUID = UUID()

    private func languageSelectionDisabled() -> Bool {
        guard let selectedModelName = effectiveModelName,
              let model = engine.allAvailableModels.first(where: { $0.name == selectedModelName })
        else {
            return false
        }
        return model.provider == .parakeet || model.provider == .gemini
    }
    
    // Whisper state for model selection
    @EnvironmentObject private var engine: VoiceInkEngine
    
    // Computed property to check if current config is the default
    private var isCurrentConfigDefault: Bool {
        if case .edit(let config) = mode {
            return config.isDefault
        }
        return false
    }
    
    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Simplified computed property for effective model name
    private var effectiveModelName: String? {
        if let model = selectedTranscriptionModelName {
            return model
        }
        return engine.currentTranscriptionModel?.name
    }
    
    init(mode: ConfigurationMode, powerModeManager: PowerModeManager) {
        self.mode = mode
        self.powerModeManager = powerModeManager

        // Always fetch the most current configuration data
        switch mode {
        case .add:
            let newId = UUID()
            _powerModeConfigId = State(initialValue: newId)
            _isAIEnhancementEnabled = State(initialValue: false)
            _selectedPromptId = State(initialValue: nil)
            _selectedTranscriptionModelName = State(initialValue: nil)
            _selectedLanguage = State(initialValue: nil)
            _configName = State(initialValue: "")
            _selectedEmoji = State(initialValue: "✏️")
            _useScreenCapture = State(initialValue: false)
            _isAutoSendEnabled = State(initialValue: false)
            _isDefault = State(initialValue: false)
            // Default to current global AI provider/model for new configurations - use UserDefaults only
            _selectedAIProvider = State(initialValue: UserDefaults.standard.string(forKey: "selectedAIProvider"))
            _selectedAIModel = State(initialValue: nil) // Initialize to nil and set it after view appears
        case .edit(let config):
            // Get the latest version of this config from PowerModeManager
            let latestConfig = powerModeManager.getConfiguration(with: config.id) ?? config
            _powerModeConfigId = State(initialValue: latestConfig.id)
            _isAIEnhancementEnabled = State(initialValue: latestConfig.isAIEnhancementEnabled)
            _selectedPromptId = State(initialValue: latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) })
            _selectedTranscriptionModelName = State(initialValue: latestConfig.selectedTranscriptionModelName)
            _selectedLanguage = State(initialValue: latestConfig.selectedLanguage)
            _configName = State(initialValue: latestConfig.name)
            _selectedEmoji = State(initialValue: latestConfig.emoji)
            _selectedAppConfigs = State(initialValue: latestConfig.appConfigs ?? [])
            _websiteConfigs = State(initialValue: latestConfig.urlConfigs ?? [])
            _useScreenCapture = State(initialValue: latestConfig.useScreenCapture)
            _isAutoSendEnabled = State(initialValue: latestConfig.isAutoSendEnabled)
            _isDefault = State(initialValue: latestConfig.isDefault)
            _selectedAIProvider = State(initialValue: latestConfig.selectedAIProvider)
            _selectedAIModel = State(initialValue: latestConfig.selectedAIModel)
        }
    }
    
    var body: some View {
        Form {
            Section("General") {
                HStack(spacing: 12) {
                    Button {
                        isShowingEmojiPicker.toggle()
                    } label: {
                        Text(selectedEmoji)
                            .font(.system(size: 22))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingEmojiPicker, arrowEdge: .bottom) {
                        EmojiPickerView(
                            selectedEmoji: $selectedEmoji,
                            isPresented: $isShowingEmojiPicker
                        )
                    }

                    TextField("Name", text: $configName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                }
            }

            Section("Trigger Scenarios") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Applications")
                        Spacer()
                        AddIconButton(helpText: "Add application") {
                            loadInstalledApps()
                            isShowingAppPicker = true
                        }
                    }

                    if selectedAppConfigs.isEmpty {
                        Text("No applications added")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)], spacing: 10) {
                            ForEach(selectedAppConfigs) { appConfig in
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
                                        selectedAppConfigs.removeAll(where: { $0.id == appConfig.id })
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
                    Text("Websites")

                    HStack {
                        TextField("Enter website URL (e.g., google.com)", text: $newWebsiteURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWebsite() }

                        AddIconButton(helpText: "Add website", isDisabled: newWebsiteURL.isEmpty) {
                            addWebsite()
                        }
                    }

                    if websiteConfigs.isEmpty {
                        Text("No websites added")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                            ForEach(websiteConfigs) { urlConfig in
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .foregroundColor(.secondary)
                                    Text(urlConfig.url)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button {
                                        websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
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

            Section("Transcription") {
                if engine.usableModels.isEmpty {
                    Text("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab.")
                        .foregroundColor(.secondary)
                } else {
                    let modelBinding = Binding<String?>(
                        get: { selectedTranscriptionModelName ?? engine.currentTranscriptionModel?.name },
                        set: { selectedTranscriptionModelName = $0 }
                    )

                    Picker("Model", selection: modelBinding) {
                        ForEach(engine.usableModels, id: \.name) { model in
                            Text(model.displayName).tag(model.name as String?)
                        }
                    }
                    .onChange(of: selectedTranscriptionModelName) { _, newModelName in
                        // Auto-set language to "auto" for models that only support auto-detection
                        if let modelName = newModelName ?? engine.currentTranscriptionModel?.name,
                           let model = engine.allAvailableModels.first(where: { $0.name == modelName }),
                           model.provider == .parakeet || model.provider == .gemini {
                            selectedLanguage = "auto"
                        }
                    }
                }

                if languageSelectionDisabled() {
                    LabeledContent("Language") {
                        Text("Autodetected")
                            .foregroundColor(.secondary)
                    }
                    .onAppear {
                        selectedLanguage = "auto"
                    }
                } else if let selectedModel = effectiveModelName,
                          let modelInfo = engine.allAvailableModels.first(where: { $0.name == selectedModel }),
                          modelInfo.isMultilingualModel {
                    let languageBinding = Binding<String?>(
                        get: { selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto" },
                        set: { selectedLanguage = $0 }
                    )

                    Picker("Language", selection: languageBinding) {
                        ForEach(modelInfo.supportedLanguages.sorted(by: {
                            if $0.key == "auto" { return true }
                            if $1.key == "auto" { return false }
                            return $0.value < $1.value
                        }), id: \.key) { key, value in
                            Text(value).tag(key as String?)
                        }
                    }
                } else if let selectedModel = effectiveModelName,
                          let modelInfo = engine.allAvailableModels.first(where: { $0.name == selectedModel }),
                          !modelInfo.isMultilingualModel {
                    EmptyView()
                        .onAppear {
                            if selectedLanguage == nil {
                                selectedLanguage = "en"
                            }
                        }
                }
            }

            Section("AI Enhancement") {
                Toggle("Enable AI Enhancement", isOn: $isAIEnhancementEnabled)
                    .onChange(of: isAIEnhancementEnabled) { _, newValue in
                        if newValue {
                            if selectedAIProvider == nil {
                                selectedAIProvider = aiService.selectedProvider.rawValue
                            }
                            if selectedAIModel == nil {
                                selectedAIModel = aiService.currentModel
                            }
                            if selectedPromptId == nil {
                                selectedPromptId = enhancementService.allPrompts.first?.id
                            }
                        }
                    }

                let providerBinding = Binding<AIProvider>(
                    get: {
                        if let providerName = selectedAIProvider,
                           let provider = AIProvider(rawValue: providerName) {
                            return provider
                        }
                        return aiService.selectedProvider
                    },
                    set: { newValue in
                        selectedAIProvider = newValue.rawValue
                        aiService.selectedProvider = newValue
                        selectedAIModel = nil
                    }
                )

                if isAIEnhancementEnabled {
                    if aiService.connectedProviders.isEmpty {
                        LabeledContent("AI Provider") {
                            Text("No providers connected")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    } else {
                        Picker("AI Provider", selection: providerBinding) {
                            ForEach(aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .onChange(of: selectedAIProvider) { _, newValue in
                            if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                                selectedAIModel = provider.defaultModel
                            }
                        }
                    }

                    let providerName = selectedAIProvider ?? aiService.selectedProvider.rawValue
                    if let provider = AIProvider(rawValue: providerName),
                       provider != .custom {
                        if aiService.availableModels.isEmpty {
                            LabeledContent("AI Model") {
                                Text(provider == .openRouter ? "No models loaded" : "No models available")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            let modelBinding = Binding<String>(
                                get: {
                                    if let model = selectedAIModel, !model.isEmpty { return model }
                                    return aiService.currentModel
                                },
                                set: { newModelValue in
                                    selectedAIModel = newModelValue
                                    aiService.selectModel(newModelValue)
                                }
                            )

                            let models = provider == .openRouter ? aiService.availableModels : (provider == .ollama ? aiService.availableModels : provider.availableModels)

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

                    if enhancementService.allPrompts.isEmpty {
                        LabeledContent("Enhancement Prompt") {
                            Text("No prompts available")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Enhancement Prompt", selection: $selectedPromptId) {
                            ForEach(enhancementService.allPrompts) { prompt in
                                Text(prompt.title).tag(prompt.id as UUID?)
                            }
                        }
                    }

                    Toggle("Context Awareness", isOn: $useScreenCapture)
                }
            }

            Section("Advanced") {
                Toggle(isOn: $isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default power mode is used when no specific app or website matches are found.")
                    }
                }

                Toggle(isOn: $isAutoSendEnabled) {
                    HStack(spacing: 6) {
                        Text("Auto Send")
                        InfoTip("Automatically presses the Return/Enter key after pasting text. Useful for chat applications or forms.")
                    }
                }

                HStack {
                    Text("Keyboard Shortcut")
                    InfoTip("Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording.")

                    Spacer()

                    KeyboardShortcuts.Recorder(for: .powerMode(id: powerModeConfigId))
                        .controlSize(.regular)
                        .frame(minHeight: 28)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveConfiguration()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.horizontal, 4)
            }

            if case .edit = mode {
                ToolbarItem {
                    Button("Delete", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.horizontal, 4)
                }
            }
        }
        .confirmationDialog(
            "Delete Power Mode?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if case .edit(let config) = mode {
                Button("Delete", role: .destructive) {
                    powerModeManager.removeConfiguration(with: config.id)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if case .edit(let config) = mode {
                Text("Are you sure you want to delete the '\(config.name)' power mode? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerSheet(
                installedApps: filteredApps,
                selectedAppConfigs: $selectedAppConfigs,
                searchText: $searchText,
                onDismiss: { isShowingAppPicker = false }
            )
        }
        .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
        .onAppear {
            // Set AI provider and model for new power modes after environment objects are available
            if case .add = mode {
                if selectedAIProvider == nil {
                    selectedAIProvider = aiService.selectedProvider.rawValue
                }
                if selectedAIModel == nil || selectedAIModel?.isEmpty == true {
                    selectedAIModel = aiService.currentModel
                }
            }
            
            // Select first prompt if AI enhancement is enabled and no prompt is selected
            if isAIEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }

            // Focus the name field for faster keyboard-driven setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
    }
    
    private var canSave: Bool {
        return !configName.isEmpty
    }
    
    private func addWebsite() {
        guard !newWebsiteURL.isEmpty else { return }
        
        let cleanedURL = powerModeManager.cleanURL(newWebsiteURL)
        let urlConfig = URLConfig(url: cleanedURL)
        websiteConfigs.append(urlConfig)
        newWebsiteURL = ""
    }
    
    private func toggleAppSelection(_ app: (url: URL, name: String, bundleId: String, icon: NSImage)) {
        if let index = selectedAppConfigs.firstIndex(where: { $0.bundleIdentifier == app.bundleId }) {
            selectedAppConfigs.remove(at: index)
        } else {
            let appConfig = AppConfig(bundleIdentifier: app.bundleId, appName: app.name)
            selectedAppConfigs.append(appConfig)
        }
    }
    
    private func getConfigForForm() -> PowerModeConfig {
        let shortcut = KeyboardShortcuts.getShortcut(for: .powerMode(id: powerModeConfigId))
        let hotkeyString = shortcut != nil ? "configured" : nil

        switch mode {
        case .add:
                return PowerModeConfig(
                id: powerModeConfigId,
                name: configName,
                emoji: selectedEmoji,
                appConfigs: selectedAppConfigs.isEmpty ? nil : selectedAppConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    selectedPrompt: selectedPromptId?.uuidString,
                    selectedTranscriptionModelName: selectedTranscriptionModelName,
                    selectedLanguage: selectedLanguage,
                    useScreenCapture: useScreenCapture,
                    selectedAIProvider: selectedAIProvider,
                    selectedAIModel: selectedAIModel,
                    isAutoSendEnabled: isAutoSendEnabled,
                    isDefault: isDefault,
                    hotkeyShortcut: hotkeyString
                )
        case .edit(let config):
            var updatedConfig = config
            updatedConfig.name = configName
            updatedConfig.emoji = selectedEmoji
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = selectedTranscriptionModelName
            updatedConfig.selectedLanguage = selectedLanguage
            updatedConfig.appConfigs = selectedAppConfigs.isEmpty ? nil : selectedAppConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.useScreenCapture = useScreenCapture
            updatedConfig.isAutoSendEnabled = isAutoSendEnabled
            updatedConfig.selectedAIProvider = selectedAIProvider
            updatedConfig.selectedAIModel = selectedAIModel
            updatedConfig.isDefault = isDefault
            updatedConfig.hotkeyShortcut = hotkeyString
            return updatedConfig
        }
    }
    
    private func loadInstalledApps() {
        // Get both user-installed and system applications
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        let localAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + localAppURLs + systemAppURLs
        
        var allApps: [URL] = []
        
        func scanDirectory(_ baseURL: URL, depth: Int = 0) {
            // Prevent infinite recursion in case of circular symlinks
            guard depth < 5 else { return }
            
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            for item in enumerator {
                guard let url = item as? URL else { continue }
                
                let resolvedURL = url.resolvingSymlinksInPath()
                
                // If it's an app, add it and skip descending into it
                if resolvedURL.pathExtension == "app" {
                    allApps.append(resolvedURL)
                    enumerator.skipDescendants()
                    continue
                }
                
                // Check if this is a symlinked directory we should traverse manually
                var isDirectory: ObjCBool = false
                if url != resolvedURL && 
                   FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) && 
                   isDirectory.boolValue {
                    // This is a symlinked directory - traverse it manually
                    enumerator.skipDescendants()
                    scanDirectory(resolvedURL, depth: depth + 1)
                }
            }
        }
        
        // Scan all app directories
        for baseURL in allAppURLs {
            scanDirectory(baseURL)
        }
        
        installedApps = allApps.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func saveConfiguration() {
        
        
        let config = getConfigForForm()
        
        // Only validate when the user explicitly tries to save
        let validator = PowerModeValidator(powerModeManager: powerModeManager)
        validationErrors = validator.validateForSave(config: config, mode: mode)
        
        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }
        
        if isDefault {
            powerModeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            powerModeManager.addConfiguration(config)
        case .edit:
            powerModeManager.updateConfiguration(config)
        }

        presentationMode.wrappedValue.dismiss()
    }
}
