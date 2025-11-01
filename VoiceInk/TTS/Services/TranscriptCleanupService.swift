import Foundation

@MainActor
protocol TranscriptCleanupServicing {
    func clean(transcript: String, instruction: String, label: String?) async throws -> TranscriptCleanupResult
}

@MainActor
final class TranscriptCleanupService: TranscriptCleanupServicing {
    private let session: URLSession
    private let keychain: KeychainManager
    private let managedProvisioningClient: ManagedProvisioningClient
    private var activeManagedCredential: ManagedCredential?
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o-mini"

    init(session: URLSession = SecureURLSession.makeEphemeral(),
         keychain: KeychainManager = KeychainManager(),
         managedProvisioningClient: ManagedProvisioningClient = .shared) {
        self.session = session
        self.keychain = keychain
        self.managedProvisioningClient = managedProvisioningClient
    }

    func clean(transcript: String, instruction: String, label: String?) async throws -> TranscriptCleanupResult {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw TTSError.apiError("Cleanup instruction cannot be empty")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.timeoutInterval = 45

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.cleanupSystemPrompt),
                .init(role: "user", content: Self.cleanupUserPrompt(instruction: trimmedInstruction, transcript: transcript))
            ],
            temperature: 0.3
        )

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                guard let output = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !output.isEmpty else {
                    throw TTSError.apiError("Cleanup response missing content")
                }
                return TranscriptCleanupResult(instruction: trimmedInstruction, label: label, output: output)
            case 401:
                if authorization.usedManagedCredential {
                    managedProvisioningClient.invalidateCredential(for: .openAI)
                    activeManagedCredential = nil
                }
                throw TTSError.invalidAPIKey
            case 429:
                throw TTSError.quotaExceeded
            case 400...499:
                throw TTSError.apiError("Cleanup request failed (\(httpResponse.statusCode))")
            case 500...599:
                throw TTSError.apiError("Cleanup service unavailable (\(httpResponse.statusCode))")
            default:
                throw TTSError.apiError("Unexpected response: \(httpResponse.statusCode)")
            }
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private extension TranscriptCleanupService {
    struct AuthorizationHeader {
        let header: String
        let value: String
        let usedManagedCredential: Bool
    }

    func authorizationHeader() async throws -> AuthorizationHeader {
        if let key = keychain.getAPIKey(for: "OpenAI"), !key.isEmpty {
            return AuthorizationHeader(header: "Authorization", value: "Bearer \(key)", usedManagedCredential: false)
        }

        guard let credential = try await managedProvisioningClient.credential(for: .openAI) else {
            throw TTSError.invalidAPIKey
        }
        activeManagedCredential = credential
        return AuthorizationHeader(header: "Authorization", value: "Bearer \(credential.token)", usedManagedCredential: true)
    }

    struct ChatCompletionRequest: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Codable {
            let type: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
        }
    }

    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    static let cleanupSystemPrompt = "You rewrite transcripts according to the provided instructions. Return the cleaned transcript only, ready for narration."

    static func cleanupUserPrompt(instruction: String, transcript: String) -> String {
        "Instruction:\n\(instruction)\n\nTranscript:\n\(transcript)"
    }
}
