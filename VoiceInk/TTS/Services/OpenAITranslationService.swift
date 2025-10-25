import Foundation

@MainActor
final class OpenAITranslationService: TextTranslationService {
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

    func hasCredentials() -> Bool {
        if let key = keychain.getAPIKey(for: "OpenAI"), !key.isEmpty {
            return true
        }
        return managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }

    func translate(text: String, targetLanguageCode: String) async throws -> TranslationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.timeoutInterval = 45

        let prompt = """
        You are a translation engine. Detect the language of the user's text and translate it into the language specified as TARGET. Respond only with JSON using the shape {"sourceLanguage":"<ISO 639-1>","translatedText":"<text>"}.
        TARGET: \(targetLanguageCode)
        TEXT: \(text)
        """

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You translate text and respond strictly with the requested JSON."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object")
        )

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                guard let content = decoded.choices.first?.message.content,
                      let payloadData = content.data(using: .utf8) else {
                    throw TTSError.apiError("Translation response missing content")
                }

                let payload = try JSONDecoder().decode(TranslationPayload.self, from: payloadData)

                return TranslationResult(
                    originalText: text,
                    translatedText: payload.translatedText,
                    detectedLanguageCode: payload.sourceLanguage.lowercased(),
                    targetLanguageCode: targetLanguageCode.lowercased()
                )
            case 401:
                if authorization.usedManagedCredential {
                    managedProvisioningClient.invalidateCredential(for: .openAI)
                    activeManagedCredential = nil
                }
                throw TTSError.invalidAPIKey
            case 429:
                throw TTSError.quotaExceeded
            case 400...499:
                throw TTSError.apiError("Translation request failed (\(httpResponse.statusCode))")
            case 500...599:
                throw TTSError.apiError("Translation service unavailable (\(httpResponse.statusCode))")
            default:
                throw TTSError.apiError("Unexpected translation response: \(httpResponse.statusCode)")
            }
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Codable {
        let type: String

        enum CodingKeys: String, CodingKey {
            case type
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        let message: ChatCompletionRequest.ChatMessage
    }

    let choices: [Choice]
}

private struct TranslationPayload: Codable {
    let sourceLanguage: String
    let translatedText: String
}

private extension OpenAITranslationService {
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
}
