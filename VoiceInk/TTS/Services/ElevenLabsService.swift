import Foundation

@MainActor
class ElevenLabsService: TTSProvider {
    // MARK: - Properties
    var name: String { "ElevenLabs" }
    private var apiKey: String?
    private let baseURL = "https://api.elevenlabs.io/v1"
    private let session: URLSession
    private let managedProvisioningClient: ManagedProvisioningClient
    private var activeManagedCredential: ManagedCredential?
    private var voicesByModel: [String: [Voice]] = [:]
    private var fallbackVoices: [Voice] = Voice.elevenLabsVoices

    // MARK: - Default Voice
    var defaultVoice: Voice {
        Voice(
            id: "21m00Tcm4TlvDq8ikWAM",
            name: "Rachel",
            language: "en-US",
            gender: .female,
            provider: .elevenLabs,
            previewURL: nil
        )
    }
    
    // MARK: - Available Voices
    var availableVoices: [Voice] {
        if let cached = voicesByModel[ElevenLabsModel.defaultSelection.rawValue], !cached.isEmpty {
            return cached
        }
        return fallbackVoices
    }

    var styleControls: [ProviderStyleControl] {
        [
            ProviderStyleControl(
                id: "elevenLabs.stability",
                label: "Stability",
                range: 0...1,
                defaultValue: 0.5,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Higher values keep the delivery consistent; lower values allow more variation."
            ),
            ProviderStyleControl(
                id: "elevenLabs.similarityBoost",
                label: "Similarity Boost",
                range: 0...1,
                defaultValue: 0.75,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Increase to match the reference voice closely, decrease for a looser interpretation."
            ),
            ProviderStyleControl(
                id: "elevenLabs.style",
                label: "Style",
                range: 0...1,
                defaultValue: 0.0,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Dial up for more expressive, emotive speech."
            )
        ]
    }
    
    // MARK: - Initialization
    init(session: URLSession = SecureURLSession.makeEphemeral(),
         managedProvisioningClient: ManagedProvisioningClient = .shared) {
        self.session = session
        self.managedProvisioningClient = managedProvisioningClient
        // Load API key from keychain if available
        self.apiKey = KeychainManager().getAPIKey(for: "ElevenLabs")
    }
    
    // MARK: - API Key Management
    func updateAPIKey(_ key: String) {
        self.apiKey = key
        voicesByModel.removeAll()
        fallbackVoices = Voice.elevenLabsVoices
    }
    
    func hasValidAPIKey() -> Bool {
        if let key = apiKey, !key.isEmpty { return true }
        return managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }

    func cachedVoices(for modelID: String) -> [Voice]? {
        voicesByModel[modelID]
    }

    func voices(for modelID: String) async throws -> [Voice] {
        if let cached = voicesByModel[modelID], !cached.isEmpty {
            return cached
        }

        if voicesByModel[modelID] == nil {
            try await refreshVoiceCache()
        }

        if let cached = voicesByModel[modelID], !cached.isEmpty {
            return cached
        }

        if let model = ElevenLabsModel(rawValue: modelID),
           let fallbackModel = model.fallback,
           let fallback = voicesByModel[fallbackModel.rawValue],
           !fallback.isEmpty {
            return fallback
        }

        return fallbackVoices
    }
    
    // MARK: - Speech Synthesis
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard text.count <= 5000 else {
            throw TTSError.textTooLong(5000)
        }
        
        // Prepare URL
        guard let url = URL(string: "\(baseURL)/text-to-speech/\(voice.id)") else {
            throw TTSError.networkError("Invalid API endpoint")
        }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45
        
        // Prepare request body
        let controlsByID = Dictionary(uniqueKeysWithValues: styleControls.map { ($0.id, $0) })
        let stability = controlsByID["elevenLabs.stability"].map { settings.styleValue(for: $0) } ?? 0.5
        let similarityBoost = controlsByID["elevenLabs.similarityBoost"].map { settings.styleValue(for: $0) } ?? 0.75
        let style = controlsByID["elevenLabs.style"].map { settings.styleValue(for: $0) } ?? 0.0

        let modelID = settings.providerOption(for: ElevenLabsProviderOptionKey.modelID) ?? "eleven_monolingual_v1"

        let requestBody = ElevenLabsRequest(
            text: text,
            model_id: modelID,
            voice_settings: VoiceSettings(
                stability: stability,
                similarity_boost: similarityBoost,
                style: style,
                use_speaker_boost: true
            )
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
                        managedProvisioningClient.invalidateCredential(for: .elevenLabs)
                        activeManagedCredential = nil
                    }
                    throw TTSError.invalidAPIKey
                case 422:
                    if let errorData = try? JSONDecoder().decode(ElevenLabsError.self, from: data) {
                        throw TTSError.apiError(errorData.detail.message)
                    }
                    throw TTSError.apiError("Invalid request")
                case 429:
                    throw TTSError.quotaExceeded
                case 400...499:
                    if let errorData = try? JSONDecoder().decode(ElevenLabsError.self, from: data) {
                        throw TTSError.apiError(errorData.detail.message)
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
    
    // MARK: - Fetch Available Voices
    private func refreshVoiceCache() async throws {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw TTSError.invalidAPIKey
        }

        guard let url = URL(string: "\(baseURL)/voices") else {
            throw TTSError.networkError("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 45

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.networkError("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw TTSError.invalidAPIKey
                }
                throw TTSError.apiError("Failed to fetch voices")
            }

            let voicesResponse = try JSONDecoder().decode(VoicesResponse.self, from: data)

            var groupedByModel: [String: [Voice]] = [:]
            var fallback: [Voice] = []

            for voiceData in voicesResponse.voices {
                let voice = Voice(
                    id: voiceData.voice_id,
                    name: voiceData.name,
                    language: voiceData.labels?.language ?? "en-US",
                    gender: parseGender(voiceData.labels?.gender),
                    provider: .elevenLabs,
                    previewURL: voiceData.preview_url
                )

                let models = voiceData.available_models ?? []
                if models.isEmpty {
                    fallback.append(voice)
                } else {
                    for model in models {
                        groupedByModel[model, default: []].append(voice)
                    }
                }
            }

            if groupedByModel.isEmpty {
                groupedByModel[ElevenLabsModel.defaultSelection.rawValue] = fallback.isEmpty ? Voice.elevenLabsVoices : fallback
            }

            voicesByModel = groupedByModel
            if !fallback.isEmpty {
                fallbackVoices = fallback
            }
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
    
    private func parseGender(_ gender: String?) -> Voice.Gender {
        switch gender?.lowercased() {
        case "male":
            return .male
        case "female":
            return .female
        default:
            return .neutral
        }
    }
}

private extension ElevenLabsService {
    struct AuthorizationHeader {
        let header: String
        let value: String
        let usedManagedCredential: Bool
    }

    func authorizationHeader() async throws -> AuthorizationHeader {
        if let key = apiKey, !key.isEmpty {
            return AuthorizationHeader(header: "xi-api-key", value: key, usedManagedCredential: false)
        }

        guard let credential = try await managedProvisioningClient.credential(for: .elevenLabs) else {
            throw TTSError.invalidAPIKey
        }

        activeManagedCredential = credential
        return AuthorizationHeader(header: "xi-api-key", value: credential.token, usedManagedCredential: true)
    }
}

// MARK: - Request/Response Models
private struct ElevenLabsRequest: Codable {
    let text: String
    let model_id: String
    let voice_settings: VoiceSettings
}

private struct VoiceSettings: Codable {
    let stability: Double
    let similarity_boost: Double
    let style: Double
    let use_speaker_boost: Bool
}

private struct ElevenLabsError: Codable {
    let detail: ErrorDetail
}

private struct ErrorDetail: Codable {
    let message: String
    let status: String?
}

private struct VoicesResponse: Codable {
    let voices: [VoiceData]
}

private struct VoiceData: Codable {
    let voice_id: String
    let name: String
    let preview_url: String?
    let available_models: [String]?
    let labels: VoiceLabels?
}

private struct VoiceLabels: Codable {
    let language: String?
    let gender: String?
    let age: String?
    let accent: String?
    let description: String?
    let use_case: String?
}

// MARK: - Voice Extensions
extension Voice {
    static var elevenLabsVoices: [Voice] {
        return [
            Voice(
                id: "21m00Tcm4TlvDq8ikWAM",
                name: "Rachel",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "AZnzlk1XvdvUeBnXmlld",
                name: "Domi",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "EXAVITQu4vr4xnSDxMaL",
                name: "Bella",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "ErXwobaYiN019PkySvjV",
                name: "Antoni",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "MF3mGyEYCl7XYWbV9V6O",
                name: "Elli",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "TxGEqnHWrfWFTfGW9XjX",
                name: "Josh",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "VR6AewLTigWG4xSOukaG",
                name: "Arnold",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "pNInz6obpgDQGcFmaJgB",
                name: "Adam",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "yoZ06aMxZJJ28mfd3POQ",
                name: "Sam",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            )
        ]
    }
}
