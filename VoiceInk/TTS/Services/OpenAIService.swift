import Foundation

@MainActor
class OpenAIService: TTSProvider {
    // MARK: - Properties
    var name: String { "OpenAI" }
    private var apiKey: String?
    private let baseURL = "https://api.openai.com/v1/audio/speech"
    private let session: URLSession
    private let managedProvisioningClient: ManagedProvisioningClient
    private var activeManagedCredential: ManagedCredential?
    
    // MARK: - Default Voice
    var defaultVoice: Voice {
        Voice(
            id: "nova",
            name: "Nova",
            language: "en-US",
            gender: .female,
            provider: .openAI,
            previewURL: nil
        )
    }
    
    // MARK: - Available Voices
    var availableVoices: [Voice] {
        return [
            Voice(id: "alloy", name: "Alloy", language: "en-US", gender: .neutral, provider: .openAI, previewURL: nil),
            Voice(id: "echo", name: "Echo", language: "en-US", gender: .male, provider: .openAI, previewURL: nil),
            Voice(id: "fable", name: "Fable", language: "en-US", gender: .neutral, provider: .openAI, previewURL: nil),
            Voice(id: "onyx", name: "Onyx", language: "en-US", gender: .male, provider: .openAI, previewURL: nil),
            Voice(id: "nova", name: "Nova", language: "en-US", gender: .female, provider: .openAI, previewURL: nil),
            Voice(id: "shimmer", name: "Shimmer", language: "en-US", gender: .female, provider: .openAI, previewURL: nil)
        ]
    }

    var styleControls: [ProviderStyleControl] {
        [
            ProviderStyleControl(
                id: "openAI.expressiveness",
                label: "Expressiveness",
                range: 0...1,
                defaultValue: 0.6,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Higher values add more dynamic emphasis across phrases."
            ),
            ProviderStyleControl(
                id: "openAI.warmth",
                label: "Warmth",
                range: 0...1,
                defaultValue: 0.5,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Blend in softer articulation for a friendlier tone."
            )
        ]
    }
    
    // MARK: - Initialization
    init(session: URLSession = SecureURLSession.makeEphemeral(),
         managedProvisioningClient: ManagedProvisioningClient = .shared) {
        self.session = session
        self.managedProvisioningClient = managedProvisioningClient
        // Load API key from keychain if available
        self.apiKey = KeychainManager().getAPIKey(for: "OpenAI")
    }
    
    // MARK: - API Key Management
    func updateAPIKey(_ key: String) {
        self.apiKey = key
    }
    
    func hasValidAPIKey() -> Bool {
        if let key = apiKey, !key.isEmpty {
            return true
        }
        return managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }
    
    // MARK: - Speech Synthesis
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard text.count <= 4096 else {
            throw TTSError.textTooLong(4096)
        }

        // Prepare request
        guard let url = URL(string: baseURL) else {
            throw TTSError.networkError("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        
        // Prepare request body
        let controlsByID = Dictionary(uniqueKeysWithValues: styleControls.map { ($0.id, $0) })
        let expressiveness = controlsByID["openAI.expressiveness"].map { settings.styleValue(for: $0) } ?? 0.6
        let warmth = controlsByID["openAI.warmth"].map { settings.styleValue(for: $0) } ?? 0.5

        let requestBody = OpenAIRequest(
            model: "tts-1",  // Use "tts-1-hd" for higher quality
            input: text,
            voice: voice.id,
            response_format: settings.format.openAIFormat,
            speed: settings.speed,
            style: .init(expressiveness: expressiveness, warmth: warmth)
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        // Make request
        do {
            let (data, response) = try await session.data(for: request)
            
            // Check response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    return data
                case 401:
                    if authorization.usedManagedCredential {
                        managedProvisioningClient.invalidateCredential(for: .openAI)
                        activeManagedCredential = nil
                    }
                    throw TTSError.invalidAPIKey
                case 429:
                    throw TTSError.quotaExceeded
                case 400...499:
                    if let errorData = try? JSONDecoder().decode(OpenAIError.self, from: data) {
                        throw TTSError.apiError(errorData.error.message)
                    }
                    throw TTSError.apiError("Client error: \(httpResponse.statusCode)")
                case 500...599:
                    throw TTSError.apiError("Server error: \(httpResponse.statusCode)")
                default:
                    throw TTSError.apiError("Unexpected response: \(httpResponse.statusCode)")
                }
            }
            
            throw TTSError.networkError("Invalid response")
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private extension OpenAIService {
    struct AuthorizationHeader {
        let header: String
        let value: String
        let usedManagedCredential: Bool
    }

    func authorizationHeader() async throws -> AuthorizationHeader {
        if let key = apiKey, !key.isEmpty {
            return AuthorizationHeader(header: "Authorization", value: "Bearer \(key)", usedManagedCredential: false)
        }

        guard let credential = try await managedProvisioningClient.credential(for: .openAI) else {
            throw TTSError.invalidAPIKey
        }

        activeManagedCredential = credential
        return AuthorizationHeader(header: "Authorization", value: "Bearer \(credential.token)", usedManagedCredential: true)
    }
}

// MARK: - Request/Response Models
private struct OpenAIRequest: Codable {
    let model: String
    let input: String
    let voice: String
    let response_format: String
    let speed: Double
    let style: StyleParameters

    struct StyleParameters: Codable {
        let expressiveness: Double
        let warmth: Double
    }
}

private struct OpenAIError: Codable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String?
    let code: String?
}

// MARK: - Format Extensions
private extension AudioSettings.AudioFormat {
    var openAIFormat: String {
        switch self {
        case .mp3:
            return "mp3"
        case .opus:
            return "opus"
        case .aac:
            return "aac"
        case .flac:
            return "flac"
        case .wav:
            return "wav"
        }
    }
}

// MARK: - Voice Extensions
extension Voice {
    static var openAIVoices: [Voice] {
        return [
            Voice(
                id: "alloy",
                name: "Alloy",
                language: "en-US",
                gender: .neutral,
                provider: .openAI,
                previewURL: nil
            ),
            Voice(
                id: "echo",
                name: "Echo",
                language: "en-US",
                gender: .male,
                provider: .openAI,
                previewURL: nil
            ),
            Voice(
                id: "fable",
                name: "Fable",
                language: "en-US",
                gender: .neutral,
                provider: .openAI,
                previewURL: nil
            ),
            Voice(
                id: "onyx",
                name: "Onyx",
                language: "en-US",
                gender: .male,
                provider: .openAI,
                previewURL: nil
            ),
            Voice(
                id: "nova",
                name: "Nova",
                language: "en-US",
                gender: .female,
                provider: .openAI,
                previewURL: nil
            ),
            Voice(
                id: "shimmer",
                name: "Shimmer",
                language: "en-US",
                gender: .female,
                provider: .openAI,
                previewURL: nil
            )
        ]
    }
}
