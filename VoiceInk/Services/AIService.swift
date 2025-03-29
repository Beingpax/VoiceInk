import Foundation

enum AIProvider: String, CaseIterable {
    case groq = "GROQ"
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case mistral = "Mistral"
    case ollama = "Ollama"
    case custom = "Custom"
    
    var baseURL: String {
        switch self {
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .deepSeek:
            return "https://api.deepseek.com/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        }
    }
    
    var defaultModel: String {
        switch self {
        case .groq:
            return "llama-3.3-70b-versatile"
        case .openAI:
            return "gpt-4o-mini-2024-07-18"
        case .deepSeek:
            return "deepseek-chat"
        case .gemini:
            return "gemini-2.0-flash"
        case .anthropic:
            return "claude-3-5-sonnet-20241022"
        case .mistral:
            return "mistral-large-2411"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderModel") ?? ""
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        default:
            return true
        }
    }
}

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? "" {
        didSet {
            userDefaults.set(customBaseURL, forKey: "customProviderBaseURL")
        }
    }
    @Published var customModel: String = UserDefaults.standard.string(forKey: "customProviderModel") ?? "" {
        didSet {
            userDefaults.set(customModel, forKey: "customProviderModel")
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            // Load API key for the selected provider if it requires one
            if selectedProvider.requiresAPIKey {
                if let savedKey = userDefaults.string(forKey: "\(selectedProvider.rawValue)APIKey") {
                    self.apiKey = savedKey
                    self.isAPIKeyValid = true
                } else {
                    self.apiKey = ""
                    self.isAPIKeyValid = false
                }
            } else {
                // For providers that don't require API key (like Ollama)
                self.apiKey = ""
                self.isAPIKeyValid = true
                // Check Ollama connection
                if selectedProvider == .ollama {
                    Task {
                        await ollamaService.checkConnection()
                        await ollamaService.refreshModels()
                    }
                }
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let ollamaService = OllamaService()
    
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider.requiresAPIKey {
                return userDefaults.string(forKey: "\(provider.rawValue)APIKey") != nil
            }
            return false
        }
    }
    
    init() {
        // Load selected provider
        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini // Default to Gemini
        }
        
        // Load API key for the current provider if it requires one
        if selectedProvider.requiresAPIKey {
            if let savedKey = userDefaults.string(forKey: "\(selectedProvider.rawValue)APIKey") {
                self.apiKey = savedKey
                self.isAPIKeyValid = true
            }
        } else {
            // For providers that don't require API key
            self.isAPIKeyValid = true
            // Check Ollama connection if it's the selected provider
            if selectedProvider == .ollama {
                Task {
                    await ollamaService.checkConnection()
                    await ollamaService.refreshModels()
                }
            }
        }
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        // Skip verification for providers that don't require API key
        guard selectedProvider.requiresAPIKey else {
            print("📝 [\(selectedProvider.rawValue)] API key not required, skipping verification")
            completion(true)
            return
        }
        
        print("🔑 [\(selectedProvider.rawValue)] Starting API key verification...")
        // Verify the API key before saving
        verifyAPIKey(key) { [weak self] isValid in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isValid {
                    print("✅ [\(self.selectedProvider.rawValue)] API key verified successfully")
                    self.apiKey = key
                    self.isAPIKeyValid = true
                    self.userDefaults.set(key, forKey: "\(self.selectedProvider.rawValue)APIKey")
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    print("❌ [\(self.selectedProvider.rawValue)] API key verification failed")
                    self.isAPIKeyValid = false
                }
                completion(isValid)
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        // Skip verification for providers that don't require API key
        guard selectedProvider.requiresAPIKey else {
            print("📝 [\(selectedProvider.rawValue)] API key verification skipped - not required")
            completion(true)
            return
        }
        
        print("🔍 [\(selectedProvider.rawValue)] Verifying API key...")
        print("🌐 Using base URL: \(selectedProvider.baseURL)")
        print("🤖 Using model: \(selectedProvider.defaultModel)")
        
        // Special handling for different providers
        switch selectedProvider {
        case .gemini:
            verifyGeminiAPIKey(key, completion: completion)
        case .anthropic:
            verifyAnthropicAPIKey(key, completion: completion)
        default:
            verifyOpenAICompatibleAPIKey(key, completion: completion)
        }
    }
    
    private func verifyOpenAICompatibleAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        let url = URL(string: selectedProvider.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let testBody: [String: Any] = [
            "model": selectedProvider.defaultModel,
            "messages": [
                ["role": "user", "content": "test"]
            ],
            "max_tokens": 1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        
        print("📤 Sending verification request...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error during verification: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Received response with status code: \(httpResponse.statusCode)")
                completion(httpResponse.statusCode == 200)
            } else {
                print("❌ Invalid response received")
                completion(false)
            }
        }.resume()
    }
    
    private func verifyAnthropicAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        let url = URL(string: selectedProvider.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let testBody: [String: Any] = [
            "model": selectedProvider.defaultModel,
            "max_tokens": 1024,
            "system": "You are a test system.",
            "messages": [
                ["role": "user", "content": "test"]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        
        print("📤 Sending Anthropic verification request...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error during Anthropic verification: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Received Anthropic response with status code: \(httpResponse.statusCode)")
                completion(httpResponse.statusCode == 200)
            } else {
                print("❌ Invalid Anthropic response received")
                completion(false)
            }
        }.resume()
    }
    
    private func verifyGeminiAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        var urlComponents = URLComponents(string: selectedProvider.baseURL)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: key)]
        
        guard let url = urlComponents.url else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let testBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "test"]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        
        print("📤 Sending Gemini verification request...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error during Gemini verification: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Received Gemini response with status code: \(httpResponse.statusCode)")
                completion(httpResponse.statusCode == 200)
            } else {
                print("❌ Invalid Gemini response received")
                completion(false)
            }
        }.resume()
    }
    
    func clearAPIKey() {
        // Skip for providers that don't require API key
        guard selectedProvider.requiresAPIKey else { return }
        
        apiKey = ""
        isAPIKeyValid = false
        userDefaults.removeObject(forKey: "\(selectedProvider.rawValue)APIKey")
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }
    
    // Add method to check Ollama connection
    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.ollamaService.checkConnection()
            DispatchQueue.main.async {
                completion(self.ollamaService.isConnected)
            }
        }
    }
    
    // Add method to get available Ollama models
    func fetchOllamaModels() async -> [OllamaService.OllamaModel] {
        await ollamaService.refreshModels()
        return ollamaService.availableModels
    }
    
    // Add method to enhance text using Ollama
    func enhanceWithOllama(text: String, systemPrompt: String) async throws -> String {
        return try await ollamaService.enhance(text, withSystemPrompt: systemPrompt)
    }
    
    // Add method to update Ollama base URL
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }
    
    // Add method to update selected Ollama model
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
    }
}

// Add extension for notification name
extension Notification.Name {
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
} 
