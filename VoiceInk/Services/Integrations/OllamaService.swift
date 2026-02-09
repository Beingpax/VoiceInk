import Foundation
import SwiftUI

class OllamaService: ObservableObject {
    static let defaultBaseURL = "http://localhost:11434"
    
    // MARK: - Response Types
    struct OllamaModel: Codable, Identifiable {
        let name: String
        let modified_at: String
        let size: Int64
        let digest: String
        let details: ModelDetails
        
        var id: String { name }
        
        struct ModelDetails: Codable {
            let format: String
            let family: String
            let families: [String]?
            let parameter_size: String
            let quantization_level: String
        }
    }

    struct OllamaModelsResponse: Codable {
        let models: [OllamaModel]
    }

    struct OllamaResponse: Codable {
        let response: String
    }
    
    // MARK: - Published Properties
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "ollamaBaseURL")
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "ollamaSelectedModel")
        }
    }
    
    @Published var availableModels: [OllamaModel] = []
    @Published var isConnected: Bool = false
    @Published var isLoadingModels: Bool = false
    
    private let defaultTemperature: Double = 0.3
    
    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? Self.defaultBaseURL
        self.selectedModel = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "llama2"        
    }
    
    @MainActor
    func checkConnection() async {
        guard let url = URL(string: baseURL) else {
            isConnected = false
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = (200...299).contains(httpResponse.statusCode)
            } else {
                isConnected = false
            }
        } catch {
            isConnected = false
        }
    }
    
    @MainActor
    func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        
        do {
            let models = try await fetchAvailableModels()
            availableModels = models
            
            // If selected model is not in available models, select first available
            if !models.contains(where: { $0.name == selectedModel }) && !models.isEmpty {
                selectedModel = models[0].name
            }
        } catch {
            print("Error fetching models: \(error)")
            availableModels = []
        }
    }
    
    private func fetchAvailableModels() async throws -> [OllamaModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw LocalAIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return response.models
    }
    
    func enhance(_ text: String, withSystemPrompt systemPrompt: String? = nil) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LocalAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let systemPrompt = systemPrompt else {
            throw LocalAIError.invalidRequest
        }

        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": text,
            "system": systemPrompt,
            "temperature": defaultTemperature,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
            return response.response
        case 404:
            throw LocalAIError.modelNotFound
        case 500:
            throw LocalAIError.serverError
        default:
            throw LocalAIError.invalidResponse
        }
    }
}

// MARK: - Error Types
enum LocalAIError: Error, LocalizedError {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Ollama server URL"
        case .serviceUnavailable:
            return "Ollama service is not available"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .modelNotFound:
            return "Selected model not found"
        case .serverError:
            return "Ollama server error"
        case .invalidRequest:
            return "System prompt is required"
        }
    }
} 
