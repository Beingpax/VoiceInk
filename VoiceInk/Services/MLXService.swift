import Foundation
import LLMkit
import SwiftUI

class MLXService: ObservableObject {
    static let defaultBaseURL = "http://localhost:8080"

    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "mlxBaseURL")
        }
    }

    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "mlxSelectedModel")
        }
    }

    @Published var availableModels: [MLXModel] = []
    @Published var isConnected: Bool = false
    @Published var isLoadingModels: Bool = false

    private let defaultTemperature: Double = 0.3

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "mlxBaseURL") ?? Self.defaultBaseURL
        self.selectedModel = UserDefaults.standard.string(forKey: "mlxSelectedModel") ?? ""
    }

    private var baseURLValue: URL? {
        URL(string: baseURL)
    }

    @MainActor
    func refreshConnectionAndModels() async -> Result<[MLXModel], Error> {
        isLoadingModels = true
        defer { isLoadingModels = false }

        guard let url = baseURLValue else {
            isConnected = false
            availableModels = []
            return .failure(MLXError.invalidURL)
        }

        do {
            let models = try await MLXClient.fetchModels(baseURL: url)
            isConnected = true
            availableModels = models

            if !models.contains(where: { $0.id == selectedModel }) && !models.isEmpty {
                selectedModel = models[0].id
            }

            return .success(models)
        } catch {
            isConnected = false
            availableModels = []
            return .failure(error)
        }
    }

    func enhance(
        _ text: String, withSystemPrompt systemPrompt: String? = nil, model: String? = nil, timeout: TimeInterval = 30
    ) async throws -> String {
        guard let systemPrompt = systemPrompt else {
            throw MLXError.invalidRequest
        }

        guard let url = baseURLValue else {
            throw MLXError.invalidURL
        }

        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestModel = (trimmedModel?.isEmpty == false ? trimmedModel : nil) ?? selectedModel

        do {
            return try await MLXClient.generate(
                baseURL: url,
                model: requestModel,
                prompt: text,
                systemPrompt: systemPrompt,
                temperature: defaultTemperature,
                timeout: timeout
            )
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        }
    }

    private func mapLLMKitError(_ error: LLMKitError) -> MLXError {
        switch error {
        case .invalidURL:
            return .invalidURL
        case .httpError(let statusCode, _):
            if statusCode == 404 { return .modelNotFound }
            if statusCode == 500 { return .serverError }
            return .invalidResponse
        case .networkError:
            return .serviceUnavailable
        case .noResultReturned, .decodingError:
            return .invalidResponse
        case .encodingError:
            return .invalidRequest
        case .missingAPIKey:
            return .invalidResponse
        case .timeout:
            return .timeout
        }
    }
}
