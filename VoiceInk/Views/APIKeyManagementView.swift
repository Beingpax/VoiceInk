import SwiftUI

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL: String = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var ollamaModels: [OllamaService.OllamaModel] = []
    @State private var selectedOllamaModel: String = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enhance your transcriptions with AI")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if aiService.isAPIKeyValid && aiService.selectedProvider != .ollama {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected to")
                            .font(.caption)
                        Text(aiService.selectedProvider.rawValue)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
                }
            }
            
            // Provider Selection
            Picker("AI Provider", selection: $aiService.selectedProvider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            
            .onChange(of: aiService.selectedProvider) { _ in
                if aiService.selectedProvider == .ollama {
                    checkOllamaConnection()
                }
            }
            
            if aiService.selectedProvider == .ollama {
                // Ollama Configuration
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Label("Ollama Configuration", systemImage: "server.rack")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Connection Status Indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isCheckingOllama ? Color.orange : (ollamaModels.isEmpty ? Color.red : Color.green))
                                .frame(width: 8, height: 8)
                            Text(isCheckingOllama ? "Checking..." : (ollamaModels.isEmpty ? "Disconnected" : "Connected"))
                                .font(.caption)
                        .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Base URL Configuration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Server URL", systemImage: "link")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            if isEditingURL {
                        TextField("Base URL", text: $ollamaBaseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button(action: {
                                    aiService.updateOllamaBaseURL(ollamaBaseURL)
                                    checkOllamaConnection()
                                    isEditingURL = false
                                }) {
                                    Text("Save")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text(ollamaBaseURL)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    isEditingURL = true
                                }) {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                
                                Button(action: {
                                    ollamaBaseURL = "http://localhost:11434"
                                    aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Model Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Model Selection", systemImage: "cpu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if ollamaModels.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            Text("No models available")
                                .foregroundColor(.secondary)
                                .italic()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                ForEach(ollamaModels) { model in
                                        VStack(alignment: .leading, spacing: 6) {
                                            // Model Name and Status
                                            HStack {
                                                Text(model.name)
                                                    .font(.subheadline)
                                                    .bold()
                                                
                                                if model.name == selectedOllamaModel {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                }
                                            }
                                            
                                            // Model Details
                                            VStack(alignment: .leading, spacing: 4) {
                                                // Parameters
                                                HStack(spacing: 4) {
                                                    Image(systemName: "cpu.fill")
                                                        .font(.caption2)
                                                    Text(model.details.parameter_size)
                                                        .font(.caption2)
                                                }
                                                .foregroundColor(.secondary)
                                                
                                                // Size
                                                HStack(spacing: 4) {
                                                    Image(systemName: "externaldrive.fill")
                                                        .font(.caption2)
                                                    Text(formatSize(model.size))
                                                        .font(.caption2)
                                                }
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(12)
                                        .frame(minWidth: 140)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(model.name == selectedOllamaModel ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(model.name == selectedOllamaModel ? Color.accentColor : Color.clear, lineWidth: 1)
                                                )
                                        )
                                        .onTapGesture {
                                            selectedOllamaModel = model.name
                                            aiService.updateSelectedOllamaModel(model.name)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)  // Add padding for the first and last items
                                .padding(.vertical, 4)
                            }
                        }
                        
                        // Refresh Button
                        Button(action: {
                            checkOllamaConnection()
                        }) {
                            Label(isCheckingOllama ? "Refreshing..." : "Refresh Models", systemImage: isCheckingOllama ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.caption)
                        }
                        .disabled(isCheckingOllama)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Help Text
                    if ollamaModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting")
                                .font(.subheadline)
                                .bold()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                bulletPoint("Ensure Ollama is installed and running")
                                bulletPoint("Check if the server URL is correct")
                                bulletPoint("Verify you have at least one model pulled")
                            }
                            
                            Button("Learn More") {
                                NSWorkspace.shared.open(URL(string: "https://ollama.ai/download")!)
                            }
                            .font(.caption)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    // Ollama Information
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            // Important Warning about Model Size
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .frame(width: 20)
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Important: Model Selection")
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
                                    Text("Smaller models (< 7B parameters) significantly impact transcription enhancement quality. For optimal results, use models with 14B+ parameters. Also reasoning models don't work with transcript enhancement. So avoid them.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)

                            // Local Processing
                            HStack(alignment: .top) {
                                Image(systemName: "cpu")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Local Processing")
                                        .font(.subheadline)
                                        .bold()
                                    Text("Ollama runs entirely on your system, processing all text locally without sending data to external servers.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // System Requirements
                            HStack(alignment: .top) {
                                Image(systemName: "memorychip")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("System Requirements")
                                        .font(.subheadline)
                                        .bold()
                                    Text("Local processing requires significant system resources. Larger, more capable models need more RAM (32GB+ recommended for optimal performance).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Use Cases
                            HStack(alignment: .top) {
                                Image(systemName: "checkmark.shield")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Best For")
                                        .font(.subheadline)
                                        .bold()
                                    Text("• Privacy-focused users who need data to stay local\n• Systems with powerful hardware\n• Users who can prioritize quality over processing speed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Recommendation Note
                            HStack(alignment: .top) {
                                Image(systemName: "lightbulb")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recommendation")
                                        .font(.subheadline)
                                        .bold()
                                    Text("For optimal transcription enhancement, either use cloud providers or ensure you're using a larger local model (14B+ parameters). Smaller models may produce poor or inconsistent results.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                }
                            }
                        }
                    } label: {
                        Label("Important Information About Local AI", systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding(16)
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(12)
            } else if aiService.selectedProvider == .custom {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Provider Configuration")
                            .font(.headline)
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Requires OpenAI-compatible API endpoint")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Configuration Fields
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Base URL (e.g., https://api.example.com/v1/chat/completions)", text: $aiService.customBaseURL)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Model Name (e.g., gpt-4o-mini, claude-3-5-sonnet-20240620)", text: $aiService.customModel)
                            .textFieldStyle(.roundedBorder)
                        
                        if aiService.isAPIKeyValid {
                            // Show masked API key when valid
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(String(repeating: "•", count: 40))
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                                
                                Button(action: {
                                    aiService.clearAPIKey()
                                }) {
                                    Label("Remove Key", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            // Show API key input when not valid
                            Text("Enter your API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            HStack {
                                Button(action: {
                                    isVerifying = true
                                    aiService.saveAPIKey(apiKey) { success in
                                        isVerifying = false
                                        if !success {
                                            alertMessage = "Invalid API key. Please check and try again."
                                            showAlert = true
                                        }
                                        apiKey = ""
                                    }
                                }) {
                                    HStack {
                                        if isVerifying {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                        Text("Verify and Save")
                                    }
                                }
                                .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)
                                
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(12)
            } else if aiService.isAPIKeyValid {
                // API Key Display for other providers
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(String(repeating: "•", count: 40))
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                        
                        Button(action: {
                            aiService.clearAPIKey()
                        }) {
                            Label("Remove Key", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                // API Key Input for other providers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your API Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                    
                    HStack {
                        Button(action: {
                            isVerifying = true
                            aiService.saveAPIKey(apiKey) { success in
                                isVerifying = false
                                if !success {
                                    alertMessage = "Invalid API key. Please check and try again."
                                    showAlert = true
                                }
                                apiKey = ""
                            }
                        }) {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text("Verify and Save")
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text(aiService.selectedProvider == .groq || aiService.selectedProvider == .gemini ? "Free" : "Paid")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                            
                            if aiService.selectedProvider != .ollama && aiService.selectedProvider != .custom {
                                Button {
                                    let url = switch aiService.selectedProvider {
                                    case .groq:
                                        URL(string: "https://console.groq.com/keys")!
                                    case .openAI:
                                        URL(string: "https://platform.openai.com/api-keys")!
                                    case .deepSeek:
                                        URL(string: "https://platform.deepseek.com/api-keys")!
                                    case .gemini:
                                        URL(string: "https://makersuite.google.com/app/apikey")!
                                    case .anthropic:
                                        URL(string: "https://console.anthropic.com/settings/keys")!
                                    case .mistral:
                                        URL(string: "https://console.mistral.ai/api-keys")!
                                    case .ollama, .custom:
                                        URL(string: "")! // This case should never be reached
                                    
                                    }
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Get API Key")
                                            .foregroundColor(.accentColor)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if aiService.selectedProvider == .ollama {
                checkOllamaConnection()
            }
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
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•")
            Text(text)
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gigabytes)
    }
}

#Preview {
    APIKeyManagementView()
        .environmentObject(AIService())
}



