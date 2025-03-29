import Foundation
import os
import SwiftData
import AppKit

enum EnhancementMode {
    case transcriptionEnhancement
    case aiAssistant
}

class AIEnhancementService: ObservableObject {
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "aienhancement"
    )
    
    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.isAIEnhancementEnabled = isEnhancementEnabled
            // When enhancement is enabled, ensure a prompt is selected
            if isEnhancementEnabled && selectedPromptId == nil {
                // Select the first prompt (default) if none is selected
                selectedPromptId = customPrompts.first?.id
            }
            
            // Cancel any existing capture task
            currentCaptureTask?.cancel()
            
            // Trigger screen capture when enhancement is enabled and screen capture is on
            if isEnhancementEnabled && useScreenCaptureContext {
                currentCaptureTask = Task {
                    await captureScreenContext()
                }
            }
        }
    }
    
    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.useClipboardContext = useClipboardContext
        }
    }
    
    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.useScreenCaptureContext = useScreenCaptureContext
        }
    }
    
    @Published var assistantTriggerWord: String {
        didSet {
            UserDefaults.standard.assistantTriggerWord = assistantTriggerWord
        }
    }
    
    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.aiEnhancementCustomPrompts = encoded
            }
        }
    }
    
    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.selectedPromptId = selectedPromptId?.uuidString
        }
    }
    
    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }
    
    var allPrompts: [CustomPrompt] {
        // Always include the latest default prompt first, followed by custom prompts
        PredefinedPrompts.createDefaultPrompts() + customPrompts.filter { !$0.isPredefined }
    }
    
    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private var currentCaptureTask: Task<Void, Never>?
    private let maxRetries = 3
    private let baseTimeout: TimeInterval = 4
    private let rateLimitInterval: TimeInterval = 1.0 // 1 request per second
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        
        // Print UserDefaults domain
        if let domain = Bundle.main.bundleIdentifier {
            print("⚙️ UserDefaults domain: \(domain)")
            if let prefsPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first {
                print("⚙️ Preferences directory: \(prefsPath)/Preferences/\(domain).plist")
            }
        }
        
        self.isEnhancementEnabled = UserDefaults.standard.isAIEnhancementEnabled
        self.useClipboardContext = UserDefaults.standard.useClipboardContext
        self.useScreenCaptureContext = UserDefaults.standard.useScreenCaptureContext
        self.assistantTriggerWord = UserDefaults.standard.assistantTriggerWord
        
        // Load only custom prompts (non-predefined ones)
        if let savedPromptsData = UserDefaults.standard.aiEnhancementCustomPrompts,
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }
        
        // Load selected prompt ID
        if let savedPromptId = UserDefaults.standard.selectedPromptId {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }
        
        // Ensure a prompt is selected if enhancement is enabled
        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            // Set first prompt (default) as selected
            self.selectedPromptId = allPrompts.first?.id
        }
        
        // Setup notification observer for API key changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            // Optionally disable enhancement if API key is cleared
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }
    
    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }
    
    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    private func determineMode(text: String) -> EnhancementMode {
        // Only use AI assistant mode if text starts with configured trigger word
        if text.lowercased().hasPrefix(assistantTriggerWord.lowercased()) {
            return .aiAssistant
        }
        return .transcriptionEnhancement
    }
    
    private func getSystemMessage(for mode: EnhancementMode) -> String {
        // Get clipboard context if enabled and available
        let clipboardContext = if useClipboardContext,
                              let clipboardText = NSPasteboard.general.string(forType: .string),
                              !clipboardText.isEmpty {
            """
            
            Available Clipboard Context: \(clipboardText)
            """
        } else {
            ""
        }
        
        // Get screen capture context if enabled and available
        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            """
            
            Active Window Context: \(capturedText)
            """
        } else {
            ""
        }
        
        // Format all context information together with instructions
        let contextSection = if !clipboardContext.isEmpty || !screenCaptureContext.isEmpty {
            """
            
            \(AIPrompts.contextInstructions)
            
            <CONTEXT_INFORMATION>
            \(clipboardContext)
            \(screenCaptureContext)
            </CONTEXT_INFORMATION>
            """
        } else {
            ""
        }
        
        switch mode {
        case .transcriptionEnhancement:
            // Check if the active prompt is the Assistant prompt
            if let activePrompt = activePrompt,
               activePrompt.id == PredefinedPrompts.assistantPromptId {
                // For the Assistant predefined prompt, use the assistant mode prompt directly
                // This ensures proper system message formatting
                return AIPrompts.assistantMode + contextSection
            }
            
            // For all other prompts, use the custom prompt template
            var systemMessage = String(format: AIPrompts.customPromptTemplate, activePrompt!.promptText)
            systemMessage += contextSection
            return systemMessage

        case .aiAssistant:
            // For AI assistant mode, use the assistant mode prompt directly
            return AIPrompts.assistantMode + contextSection
        }
    }
    
    private func makeRequest(text: String, retryCount: Int = 0) async throws -> String {
        guard isConfigured else {
            logger.error("AI Enhancement: API not configured")
            throw EnhancementError.notConfigured
        }
        
        guard !text.isEmpty else {
            logger.error("AI Enhancement: Empty text received")
            throw EnhancementError.emptyText
        }
        
        // Format transcript with boundary markers
        let formattedText = "<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        
        // Determine mode and get system message
        let mode = determineMode(text: text)
        let systemMessage = getSystemMessage(for: mode)
        
        // Handle Ollama requests differently
        if aiService.selectedProvider == .ollama {
            logger.notice("📤 Request to Ollama")
            logger.notice("🤖 System: \(systemMessage, privacy: .public)")
            logger.notice("📝 Sending: \(formattedText, privacy: .public)")
            do {
                let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage)
                logger.notice("✅ Ollama enhancement successful")
                logger.notice("📝 Received: \(result, privacy: .public)")
                return result
            } catch let error as LocalAIError {
                switch error {
                case .serviceUnavailable:
                    logger.error("🔌 Ollama service unavailable")
                    throw EnhancementError.notConfigured
                case .modelNotFound:
                    logger.error("🤖 Ollama model not found")
                    throw EnhancementError.enhancementFailed
                case .serverError:
                    logger.error("🔥 Ollama server error")
                    throw EnhancementError.serverError
                default:
                    logger.error("❌ Ollama enhancement failed")
                    throw EnhancementError.enhancementFailed
                }
            }
        }
        
        // Handle cloud provider requests
        // Wait for rate limit
        try await waitForRateLimit()
        
        // Special handling for Gemini and Anthropic
        switch aiService.selectedProvider {
        case .gemini:
            var urlComponents = URLComponents(string: aiService.selectedProvider.baseURL)!
            urlComponents.queryItems = [URLQueryItem(name: "key", value: aiService.apiKey)]
            
            guard let url = urlComponents.url else {
                throw EnhancementError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let timeout = baseTimeout * pow(2.0, Double(retryCount))
            request.timeoutInterval = timeout
            
            let requestBody: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": systemMessage],
                            ["text": formattedText]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.3,
                ]
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                logger.notice("📤 Request to Gemini")
                logger.notice("🤖 System: \(systemMessage, privacy: .public)")
                logger.notice("📝 Sending: \(formattedText, privacy: .public)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    logger.error("❌ Invalid Gemini response")
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let candidates = jsonResponse["candidates"] as? [[String: Any]],
                          let firstCandidate = candidates.first,
                          let content = firstCandidate["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]],
                          let firstPart = parts.first,
                          let enhancedText = firstPart["text"] as? String else {
                        logger.error("❌ Failed to parse Gemini response")
                        throw EnhancementError.enhancementFailed
                    }
                    
                    let result = enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.notice("✅ Gemini enhancement successful")
                    logger.notice("📝 Received: \(result, privacy: .public)")
                    return result
                    
                case 401:
                    logger.error("🔒 Authentication failed")
                    throw EnhancementError.authenticationFailed
                    
                case 429:
                    logger.error("⏳ Rate limit exceeded")
                    throw EnhancementError.rateLimitExceeded
                    
                case 500...599:
                    logger.error("🔥 Server error (\(httpResponse.statusCode))")
                    throw EnhancementError.serverError
                    
                default:
                    logger.error("❌ Unexpected status (\(httpResponse.statusCode))")
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                logger.error("❌ Network error: \(error.localizedDescription)")
                
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
                }
                
                throw EnhancementError.networkError
            }
            
        case .anthropic:
            let requestBody: [String: Any] = [
                "model": aiService.selectedProvider.defaultModel,
                "max_tokens": 1024,
                "system": systemMessage,
                "messages": [
                    ["role": "user", "content": formattedText]
                ]
            ]
            
            var request = URLRequest(url: URL(string: aiService.selectedProvider.baseURL)!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(aiService.apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
            let timeout = baseTimeout * pow(2.0, Double(retryCount))
            request.timeoutInterval = timeout
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                logger.notice("📤 Request to Anthropic")
                logger.notice("🤖 System: \(systemMessage, privacy: .public)")
                logger.notice("📝 Sending: \(formattedText, privacy: .public)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    logger.error("❌ Invalid Anthropic response")
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let content = jsonResponse["content"] as? [[String: Any]],
                          let firstContent = content.first,
                          let enhancedText = firstContent["text"] as? String else {
                        logger.error("❌ Failed to parse Anthropic response")
                        throw EnhancementError.enhancementFailed
                    }
                    
                    let result = enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.notice("✅ Anthropic enhancement successful")
                    logger.notice("📝 Received: \(result, privacy: .public)")
                    return result
                    
                case 401:
                    logger.error("🔒 Authentication failed")
                    throw EnhancementError.authenticationFailed
                    
                case 429:
                    logger.error("⏳ Rate limit exceeded")
                    throw EnhancementError.rateLimitExceeded
                    
                case 500...599:
                    logger.error("🔥 Server error (\(httpResponse.statusCode))")
                    throw EnhancementError.serverError
                    
                default:
                    logger.error("❌ Unexpected status (\(httpResponse.statusCode))")
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                logger.error("❌ Network error: \(error.localizedDescription)")
                
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
                }
                
                throw EnhancementError.networkError
            }
            
        default:
            // Handle OpenAI compatible providers
            let url = URL(string: aiService.selectedProvider.baseURL)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
            
            // Set timeout based on retry count with exponential backoff
            let timeout = baseTimeout * pow(2.0, Double(retryCount))
            request.timeoutInterval = timeout
            
            logger.debug("Full system message: \(systemMessage)")
            
            let messages: [[String: Any]] = [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": formattedText]
            ]
            
            logger.info("Making request to \(self.aiService.selectedProvider.rawValue) with text length: \(text.count) characters")
            
            let requestBody: [String: Any] = [
                "model": aiService.selectedProvider.defaultModel,
                "messages": messages,
                "temperature": 0.3,
                "frequency_penalty": 0.0,
                "presence_penalty": 0.0,
                "stream": false
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                logger.notice("📤 Request to \(self.aiService.selectedProvider.rawValue, privacy: .public)")
                logger.notice("🤖 System: \(systemMessage, privacy: .public)")
                logger.notice("📝 Sending: \(formattedText, privacy: .public)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    logger.error("❌ Invalid response")
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = jsonResponse["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any],
                          let enhancedText = message["content"] as? String else {
                        logger.error("❌ Failed to parse response")
                        throw EnhancementError.enhancementFailed
                    }
                    
                    let result = enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.notice("✅ Enhancement successful")
                    logger.notice("📝 Received: \(result, privacy: .public)")
                    return result
                    
                case 401:
                    logger.error("🔒 Authentication failed")
                    throw EnhancementError.authenticationFailed
                    
                case 429:
                    logger.error("⏳ Rate limit exceeded")
                    throw EnhancementError.rateLimitExceeded
                    
                case 500...599:
                    logger.error("🔥 Server error (\(httpResponse.statusCode))")
                    throw EnhancementError.serverError
                    
                default:
                    logger.error("❌ Unexpected status (\(httpResponse.statusCode))")
                    throw EnhancementError.apiError
                }
                
            } catch let error as EnhancementError {
                throw error
            } catch {
                logger.error("❌ Network error: \(error.localizedDescription)")
                
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
                }
                
                throw EnhancementError.networkError
            }
        }
    }
    
    func enhance(_ text: String) async throws -> String {
        var retryCount = 0
        while retryCount < maxRetries {
            do {
                return try await makeRequest(text: text, retryCount: retryCount)
            } catch EnhancementError.rateLimitExceeded where retryCount < maxRetries - 1 {
                retryCount += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                continue
            } catch {
                throw error
            }
        }
        throw EnhancementError.maxRetriesExceeded
    }
    
    // Add a new method to capture screen context
    func captureScreenContext() async {
        // Only check for screen capture context toggle
        guard useScreenCaptureContext else { 
            logger.notice("📷 Screen capture context is disabled")
            return 
        }
        
        logger.notice("📷 Initiating screen capture for context")
        // Wait for the screen capture to complete and check result
        if let capturedText = await screenCaptureService.captureAndExtractText() {
            logger.notice("📷 Screen capture successful, got \(capturedText.count, privacy: .public) characters")
            // Ensure we're on the main thread when updating published properties
            await MainActor.run {
                // Manually trigger objectWillChange to ensure UI updates
                self.objectWillChange.send()
            }
        } else {
            logger.notice("📷 Screen capture failed or returned empty result")
        }
    }
    
    // MARK: - Prompt Management
    
    func addPrompt(title: String, promptText: String, icon: PromptIcon = .documentFill, description: String? = nil) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }
    
    func updatePrompt(_ prompt: CustomPrompt) {
        // Don't allow updates to predefined prompts
        if prompt.isPredefined {
            return
        }
        
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }
    
    func deletePrompt(_ prompt: CustomPrompt) {
        // Don't allow deletion of predefined prompts
        if prompt.isPredefined {
            return
        }
        
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }
    
    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }
}

enum EnhancementError: Error {
    case notConfigured
    case emptyText
    case invalidResponse
    case enhancementFailed
    case authenticationFailed
    case rateLimitExceeded
    case serverError
    case apiError
    case networkError
    case maxRetriesExceeded
} 


