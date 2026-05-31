import Foundation
import SwiftData
import LLMkit

enum CloudTranscriptionError: Error, LocalizedError {
    case unsupportedProvider
    case missingAPIKey
    case invalidAPIKey
    case audioFileNotFound
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned
    case dataEncodingError
    /// Every configured API key for the provider failed with a key-level error.
    case allKeysExhausted(provider: String, lastReason: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .invalidAPIKey:
            return "The provided API key is invalid."
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return "The API returned an empty or invalid response."
        case .dataEncodingError:
            return "Failed to encode the request body."
        case .allKeysExhausted(let provider, let lastReason):
            return "All configured \(provider) API keys failed. Last error: \(lastReason)"
        }
    }
}

class CloudTranscriptionService: TranscriptionService {
    private let modelContext: ModelContext
    private lazy var openAICompatibleService = OpenAICompatibleTranscriptionService()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let audioData = try loadAudioData(from: audioURL)
        let fileName = audioURL.lastPathComponent
        let language = selectedLanguage()

        do {
            if model.provider == .custom {
                guard let customModel = model as? CustomCloudModel else {
                    throw CloudTranscriptionError.unsupportedProvider
                }
                return try await openAICompatibleService.transcribe(audioURL: audioURL, model: customModel)
            }

            guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider) else {
                throw CloudTranscriptionError.unsupportedProvider
            }

            // ElevenLabs uses multi-key rotation
            if model.provider == .elevenLabs {
                return try await transcribeWithKeyRotation(
                    provider: cloudProvider,
                    providerKey: cloudProvider.providerKey,
                    audioData: audioData,
                    fileName: fileName,
                    model: model,
                    language: language
                )
            }

            let apiKey = try requireAPIKey(forProvider: cloudProvider.providerKey)
            return try await cloudProvider.transcribe(
                audioData: audioData,
                fileName: fileName,
                apiKey: apiKey,
                model: model.name,
                language: language,
                prompt: transcriptionPrompt(),
                customVocabulary: getCustomDictionaryTerms()
            )
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch {
            throw CloudTranscriptionError.networkError(error)
        }
    }

    // MARK: - Key Rotation

    /// Transcribes via a cloud provider, auto-rotating through configured API keys
    /// on key-level failures (HTTP 401/403/429). Transient failures surface immediately.
    private func transcribeWithKeyRotation(
        provider: any CloudProvider,
        providerKey: String,
        audioData: Data,
        fileName: String,
        model: any TranscriptionModel,
        language: String?
    ) async throws -> String {
        let keys = APIKeyManager.shared.getAPIKeys(forProvider: providerKey)
        let enabledKeys = keys.filter { !$0.disabled && !$0.key.isEmpty }

        guard !enabledKeys.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        let firstActive = APIKeyManager.shared.activeAPIKey(forProvider: providerKey)
        var attemptOrder: [APIKeyEntry] = []
        var seen = Set<UUID>()
        if let firstActive, !firstActive.disabled {
            attemptOrder.append(firstActive)
            seen.insert(firstActive.id)
        }
        for entry in enabledKeys where !seen.contains(entry.id) {
            attemptOrder.append(entry)
            seen.insert(entry.id)
        }

        var lastReason = "unknown"
        for entry in attemptOrder {
            do {
                let result = try await provider.transcribe(
                    audioData: audioData,
                    fileName: fileName,
                    apiKey: entry.key,
                    model: model.name,
                    language: language,
                    prompt: transcriptionPrompt(),
                    customVocabulary: getCustomDictionaryTerms()
                )
                APIKeyManager.shared.setActiveKey(id: entry.id, forProvider: providerKey)
                APIKeyManager.shared.updateAPIKey(
                    id: entry.id,
                    clearFailure: true,
                    forProvider: providerKey
                )
                return result
            } catch let error as LLMKitError {
                let classification = classifyLLMKitError(error)
                switch classification {
                case .keyLevel(let reason):
                    lastReason = reason
                    APIKeyManager.shared.markKeyFailed(
                        id: entry.id,
                        reason: reason,
                        forProvider: providerKey
                    )
                    continue
                case .transient:
                    throw mapLLMKitError(error)
                }
            } catch {
                throw CloudTranscriptionError.networkError(error)
            }
        }

        throw CloudTranscriptionError.allKeysExhausted(
            provider: providerKey,
            lastReason: lastReason
        )
    }

    private func classifyLLMKitError(_ error: LLMKitError) -> APIKeyFailureClass {
        switch error {
        case .missingAPIKey:
            return .keyLevel(reason: "missing API key")
        case .httpError(let statusCode, let message):
            return APIKeyFailureClass.classifyHTTP(statusCode: statusCode, message: message)
        case .networkError(let detail):
            return .transient(reason: detail)
        case .timeout:
            return .transient(reason: "timeout")
        case .invalidURL, .decodingError, .encodingError, .noResultReturned:
            return .transient(reason: error.errorDescription ?? "unknown")
        }
    }

    // MARK: - Helpers

    private func loadAudioData(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        return try Data(contentsOf: url)
    }

    private func requireAPIKey(forProvider provider: String) throws -> String {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: provider), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }

    private func selectedLanguage() -> String? {
        let lang = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return (lang == "auto" || lang.isEmpty) ? nil : lang
    }

    private func transcriptionPrompt() -> String? {
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        return prompt.isEmpty ? nil : prompt
    }

    private func getCustomDictionaryTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }
        var seen = Set<String>()
        var unique: [String] = []
        for word in vocabularyWords {
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(trimmed)
            }
        }
        return unique
    }

    private func mapLLMKitError(_ error: LLMKitError) -> CloudTranscriptionError {
        switch error {
        case .missingAPIKey:
            return .missingAPIKey
        case .httpError(let statusCode, let message):
            return .apiRequestFailed(statusCode: statusCode, message: message)
        case .noResultReturned:
            return .noTranscriptionReturned
        case .encodingError:
            return .dataEncodingError
        case .networkError(let detail):
            return .networkError(NSError(domain: "LLMkit", code: -1, userInfo: [NSLocalizedDescriptionKey: detail]))
        case .invalidURL, .decodingError, .timeout:
            return .networkError(error)
        }
    }
}
