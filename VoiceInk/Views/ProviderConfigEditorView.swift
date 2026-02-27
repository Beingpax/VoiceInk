import SwiftUI
import LLMkit

struct ProviderConfigEditorView: View {
    enum Mode {
        case add
        case edit(AIProviderConfiguration)
    }

    let mode: Mode
    @EnvironmentObject private var aiService: AIService
    var onDismiss: (() -> Void)?

    @State private var name: String
    @State private var selectedProvider: AIProvider
    @State private var selectedModel: String
    @State private var customBaseURL: String
    @State private var customModel: String
    @State private var apiKey: String = ""
    @State private var isVerifying = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var ollamaModels: [OllamaModel] = []
    @State private var isCheckingOllama = false

    private static let enhancementProviders: [AIProvider] = AIProvider.allCases.filter {
        $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox
    }

    init(mode: Mode, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _selectedProvider = State(initialValue: .gemini)
            _selectedModel = State(initialValue: AIProvider.gemini.defaultModel)
            _customBaseURL = State(initialValue: "")
            _customModel = State(initialValue: "")
        case .edit(let config):
            _name = State(initialValue: config.name)
            _selectedProvider = State(initialValue: config.provider)
            _selectedModel = State(initialValue: config.model)
            _customBaseURL = State(initialValue: config.customBaseURL ?? "")
            _customModel = State(initialValue: config.customModel ?? "")
        }
    }

    private var hasAPIKeySet: Bool {
        if !selectedProvider.requiresAPIKey { return true }
        return APIKeyManager.shared.hasAPIKey(forProvider: selectedProvider.rawValue)
    }

    private var availableModels: [String] {
        if selectedProvider == .ollama {
            return ollamaModels.map { $0.name }
        }
        if selectedProvider == .openRouter {
            return aiService.openRouterModels
        }
        return selectedProvider.availableModels
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if selectedProvider == .custom {
            return !customBaseURL.isEmpty && !customModel.isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(mode.isAdd ? "New Provider" : "Edit Provider")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { onDismiss?() }) {
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
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Claude for Emails", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                            )
                    }

                    // Provider
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Provider", selection: $selectedProvider) {
                            ForEach(Self.enhancementProviders, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.automatic)
                        .onChange(of: selectedProvider) { _, newValue in
                            selectedModel = newValue.defaultModel
                            if newValue == .ollama {
                                checkOllamaConnection()
                            }
                        }
                    }

                    // Model
                    if selectedProvider == .ollama {
                        ollamaSection
                    } else if selectedProvider == .custom {
                        customProviderSection
                    } else {
                        modelPickerSection
                    }

                    Divider().padding(.vertical, 4)

                    // API Key
                    if selectedProvider.requiresAPIKey {
                        apiKeySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }

            // Footer
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Cancel") { onDismiss?() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        save()
                        onDismiss?()
                    } label: {
                        Text("Save")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if selectedProvider == .ollama {
                checkOllamaConnection()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if selectedProvider == .openRouter {
                if availableModels.isEmpty {
                    HStack {
                        Text("No models loaded")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            Task { await aiService.fetchOpenRouterModels() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    HStack {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await aiService.fetchOpenRouterModels() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            } else if !availableModels.isEmpty {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("http://localhost:11434", text: $customBaseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                    )
            }

            if isCheckingOllama {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking connection...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !ollamaModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Model", selection: $selectedModel) {
                        ForEach(ollamaModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Not connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        checkOllamaConnection()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var customProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Endpoint URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("https://api.example.com/v1/chat/completions", text: $customBaseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("model-name", text: $customModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                    )
            }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if hasAPIKeySet {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("API key is set for \(selectedProvider.rawValue)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        APIKeyManager.shared.deleteAPIKey(forProvider: selectedProvider.rawValue)
                        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                        // Force view update
                        apiKey = ""
                    }
                    .controlSize(.small)
                }
            } else {
                SecureField("Enter API Key", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                    )

                HStack {
                    if let url = getAPIKeyURL(for: selectedProvider) {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("Get API Key")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        isVerifying = true
                        aiService.saveAPIKeyForProvider(apiKey, provider: selectedProvider, model: selectedModel) { success, errorMessage in
                            isVerifying = false
                            if success {
                                apiKey = ""
                            } else {
                                alertMessage = errorMessage ?? "Verification failed"
                                showAlert = true
                            }
                        }
                    } label: {
                        HStack {
                            if isVerifying {
                                ProgressView().controlSize(.small)
                            }
                            Text("Verify and Save")
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }
            }

            Text("API keys are shared across all configurations using the same provider.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBaseURL: String? = (selectedProvider == .ollama || selectedProvider == .custom) ? customBaseURL : nil
        let effectiveCustomModel: String? = selectedProvider == .custom ? customModel : nil

        switch mode {
        case .add:
            let config = AIProviderConfiguration(
                name: trimmedName,
                provider: selectedProvider,
                model: selectedModel,
                customBaseURL: effectiveBaseURL,
                customModel: effectiveCustomModel
            )
            aiService.addProviderConfiguration(config)
        case .edit(let existing):
            let config = AIProviderConfiguration(
                id: existing.id,
                name: trimmedName,
                provider: selectedProvider,
                model: selectedModel,
                customBaseURL: effectiveBaseURL,
                customModel: effectiveCustomModel
            )
            aiService.updateProviderConfiguration(config)
        }
    }

    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    ollamaModels = await aiService.fetchOllamaModels()
                    isCheckingOllama = false
                    if !ollamaModels.isEmpty && selectedModel.isEmpty {
                        selectedModel = ollamaModels.first?.name ?? ""
                    }
                }
            } else {
                ollamaModels = []
                isCheckingOllama = false
            }
        }
    }
}

extension ProviderConfigEditorView.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
