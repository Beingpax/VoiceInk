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
        }
    }
}

class CloudTranscriptionService: TranscriptionService {
    private let modelContext: ModelContext
    private lazy var openAICompatibleService = OpenAICompatibleTranscriptionService()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        let audioData = try loadAudioData(from: audioURL)
        let fileName = audioURL.lastPathComponent
        let language = selectedLanguage(from: context)

        do {
            if model.provider == .custom {
                guard let customModel = model as? CustomCloudModel else {
                    throw CloudTranscriptionError.unsupportedProvider
                }
                return try await openAICompatibleService.transcribe(audioURL: audioURL, model: customModel, context: context)
            }

            guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider) else {
                throw CloudTranscriptionError.unsupportedProvider
            }
            let apiKey = try requireAPIKey(forProvider: cloudProvider.providerKey)
            return try await cloudProvider.transcribe(
                audioData: audioData,
                fileName: fileName,
                apiKey: apiKey,
                model: model.name,
                language: language,
                prompt: transcriptionPrompt(from: context),
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

    private func selectedLanguage(from context: TranscriptionRequestContext) -> String? {
        let lang = context.language ?? "auto"
        return (lang == "auto" || lang.isEmpty) ? nil : lang
    }

    private func transcriptionPrompt(from context: TranscriptionRequestContext) -> String? {
        let prompt = context.prompt ?? ""
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
