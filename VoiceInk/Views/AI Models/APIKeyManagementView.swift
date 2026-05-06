import SwiftUI
import LLMkit

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL: String = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedOllamaModel: String = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false
    @State private var localCLICommandTemplate: String = ""
    @State private var localCLITimeoutSeconds: Double = LocalCLIService.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false
    
    var body: some View {
        Section("AI Provider Integration") {
            HStack {
                Picker("Provider", selection: $aiService.selectedProvider) {
                    ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox && $0 != .speechmatics && $0 != .assemblyAI }, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.automatic)
                .tint(.blue)
                
                if aiService.isAPIKeyValid && aiService.selectedProvider != .ollama {
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if aiService.selectedProvider == .ollama {
                    Spacer()
                    if isCheckingOllama {
                        ProgressView()
                            .controlSize(.small)
                    } else if !ollamaModels.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Disconnected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: aiService.selectedProvider) { oldValue, newValue in
                if aiService.selectedProvider == .ollama {
                    checkOllamaConnection()
                }
                if aiService.selectedProvider == .localCLI {
                    syncLocalCLIStateFromService()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Model Selection
                if aiService.selectedProvider == .openRouter {
                    if aiService.availableModels.isEmpty {
                        HStack {
                            Text("No models loaded")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    } else {
                        HStack {
                            Picker("Model", selection: Binding(
                                get: { aiService.currentModel },
                                set: { aiService.selectModel($0) }
                            )) {
                                ForEach(aiService.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    
                } else if !aiService.availableModels.isEmpty &&
                            aiService.selectedProvider != .ollama &&
                            aiService.selectedProvider != .custom {
                    Picker("Model", selection: Binding(
                        get: { aiService.currentModel },
                        set: { aiService.selectModel($0) }
                    )) {
                        ForEach(aiService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if aiService.selectedProvider == .ollama {
                    if isEditingURL {
                        HStack {
                            TextField("Base URL", text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                                isEditingURL = false
                            }
                        }
                    } else {
                        HStack {
                            Text("Server: \(ollamaBaseURL)")
                            Spacer()
                            Button("Edit") { isEditingURL = true }
                            Button(action: {
                                ollamaBaseURL = "http://localhost:11434"
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("Reset to default")
                        }
                    }

                    if !ollamaModels.isEmpty {
                        Divider()

                        Picker("Model", selection: $selectedOllamaModel) {
                            ForEach(ollamaModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .onChange(of: selectedOllamaModel) { oldValue, newValue in
                            aiService.updateSelectedOllamaModel(newValue)
                        }
                    }

                } else if aiService.selectedProvider == .localCLI {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Command")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Menu("Load Template") {
                                ForEach(LocalCLITemplate.allCases) { template in
                                    Button(template.displayName) {
                                        aiService.loadLocalCLITemplate(template)
                                        syncLocalCLIStateFromService()
                                    }
                                }
                            }
                        }

                        TextEditor(text: $localCLICommandTemplate)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .onChange(of: localCLICommandTemplate) { _, newValue in
                                guard !isSyncingLocalCLIState else { return }
                                if newValue != aiService.localCLICommandTemplate {
                                    aiService.updateLocalCLICommandTemplate(newValue)
                                }
                            }
                    }

                    Picker("Timeout", selection: $localCLITimeoutSeconds) {
                        Text("15s").tag(15.0)
                        Text("30s").tag(30.0)
                        Text("45s").tag(45.0)
                        Text("60s").tag(60.0)
                        Text("90s").tag(90.0)
                        Text("120s").tag(120.0)
                        Text("180s").tag(180.0)
                        Text("300s").tag(300.0)
                    }
                    .onChange(of: localCLITimeoutSeconds) { _, newValue in
                        aiService.updateLocalCLITimeoutSeconds(newValue)
                    }

                    Text("Environment variables available: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT. VoiceInk also writes VOICEINK_FULL_PROMPT to stdin for every command.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !aiService.isAPIKeyValid {
                        Text("Load a template or enter a command to enable Local CLI enhancement.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                } else if aiService.selectedProvider == .custom {
                    TextField("API Endpoint URL", text: $aiService.customBaseURL, prompt: Text("e.g. https://api.openai.com/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    TextField("Model Name", text: $aiService.customModel, prompt: Text("e.g. gemini-3.1-pro-preview, gpt-5.5"))
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    if aiService.isAPIKeyValid {
                        HStack {
                            Text("API Key Set")
                            Spacer()
                            Button("Remove Key", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Verify and Save") {
                            isVerifying = true
                            aiService.saveAPIKey(apiKey) { success, errorMessage in
                                isVerifying = false
                                if !success {
                                    alertMessage = errorMessage ?? "Verification failed"
                                    showAlert = true
                                }
                                apiKey = ""
                            }
                        }
                        .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)
                    }
                    
                } else {
                    if aiService.isAPIKeyValid {
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("••••••••")
                                .foregroundColor(.secondary)
                            Button("Remove", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if let url = getAPIKeyURL() {
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

                            Button(action: {
                                isVerifying = true
                                aiService.saveAPIKey(apiKey) { success, errorMessage in
                                    isVerifying = false
                                    if !success {
                                        alertMessage = errorMessage ?? "Verification failed"
                                        showAlert = true
                                    }
                                    apiKey = ""
                                }
                            }) {
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
                }
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if aiService.selectedProvider == .ollama {
                checkOllamaConnection()
            }
            if aiService.selectedProvider == .localCLI {
                syncLocalCLIStateFromService()
            }
        }
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }
    
    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    ollamaModels = await aiService.fetchOllamaModels()
                    isCheckingOllama = false
                }
            } else {
                ollamaModels = []
                isCheckingOllama = false
                alertMessage = "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct."
                showAlert = true
            }
        }
    }
    
    private func getAPIKeyURL() -> URL? {
        switch aiService.selectedProvider {
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs: return URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram: return URL(string: "https://console.deepgram.com/api-keys")
        case .soniox: return URL(string: "https://console.soniox.com/")
        case .speechmatics: return URL(string: "https://portal.speechmatics.com/manage-access/")
        case .assemblyAI: return URL(string: "https://www.assemblyai.com/dashboard/api-keys")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai/")
        default: return nil
        }
    }
}
