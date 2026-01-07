import Foundation

@MainActor
class ElevenLabsTTSService: TTSProvider, StreamingSpeechSynthesizing {
    // MARK: - Properties
    var name: String { "ElevenLabs" }
    private var apiKey: String?
    private let baseURL = "https://api.elevenlabs.io/v1"
    private let session: URLSession
    private let authorizationService: AuthorizationService
    private var activeManagedCredential: ManagedCredential?
    private var voicesByModel: [String: [Voice]] = [:]
    private var fallbackVoices: [Voice] = Voice.elevenLabsVoices
    private var activeStreamingTask: Task<Void, Never>?

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
         authorizationService: AuthorizationService? = nil) {
        self.session = session
        self.authorizationService = authorizationService ?? AuthorizationService()
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
        return authorizationService.hasManagedProvisioningConfiguration
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
        
        let processedText = applyPronunciationOverrides(to: text, overrides: settings.pronunciationOverrides)
        
        let outputFormat = settings.providerOption(for: ElevenLabsProviderOptionKey.outputFormat) ?? "mp3_44100_128"
        
        var urlComponents = URLComponents(string: "\(baseURL)/text-to-speech/\(voice.id)")
        urlComponents?.queryItems = [
            URLQueryItem(name: "output_format", value: outputFormat)
        ]
        
        guard let url = urlComponents?.url else {
            throw TTSError.networkError("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let authorization = try await authorizationService.authorizationHeader(for: "ElevenLabs", headerType: HeaderType.elevenLabs)
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        
        let controlsByID = Dictionary(uniqueKeysWithValues: styleControls.map { ($0.id, $0) })
        let stability = controlsByID["elevenLabs.stability"].map { settings.styleValue(for: $0) } ?? 0.5
        let similarityBoost = controlsByID["elevenLabs.similarityBoost"].map { settings.styleValue(for: $0) } ?? 0.75
        let style = controlsByID["elevenLabs.style"].map { settings.styleValue(for: $0) } ?? 0.0

        let modelID = settings.providerOption(for: ElevenLabsProviderOptionKey.modelID) ?? ElevenLabsModel.defaultSelection.rawValue

        let requestBody = buildRequestBody(
            text: processedText,
            modelID: modelID,
            stability: stability,
            similarityBoost: similarityBoost,
            style: style,
            pronunciationDictionaryID: settings.pronunciationDictionaryID
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let (data, response) = try await session.data(for: request)

            return try HTTPResponseHandler.handleResponse(
                response,
                data: data,
                onUnauthorized: {
                    if authorization.usedManagedCredential {
                        self.authorizationService.invalidateManagedCredential(for: .elevenLabs)
                        self.activeManagedCredential = nil
                    }
                },
                errorOverrides: [
                    422: { data in
                        if let errorData = try? JSONDecoder().decode(ElevenLabsError.self, from: data) {
                            return TTSError.apiError(errorData.detail.message)
                        }
                        return TTSError.apiError("Invalid request")
                    }
                ],
                errorMessageDecoder: { data in
                    (try? JSONDecoder().decode(ElevenLabsError.self, from: data))?.detail.message
                }
            )
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Streaming Speech Synthesis
    func synthesizeSpeechStream(
        text: String,
        voice: Voice,
        settings: AudioSettings,
        onChunk: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard text.count <= 5000 else {
            throw TTSError.textTooLong(5000)
        }
        
        let processedText = applyPronunciationOverrides(to: text, overrides: settings.pronunciationOverrides)
        
        let latencyOptimization = settings.providerOption(for: ElevenLabsProviderOptionKey.optimizeStreamingLatency) ?? "3"
        let outputFormat = settings.providerOption(for: ElevenLabsProviderOptionKey.outputFormat) ?? "mp3_44100_128"
        
        var urlComponents = URLComponents(string: "\(baseURL)/text-to-speech/\(voice.id)/stream")
        urlComponents?.queryItems = [
            URLQueryItem(name: "optimize_streaming_latency", value: latencyOptimization),
            URLQueryItem(name: "output_format", value: outputFormat)
        ]
        
        guard let url = urlComponents?.url else {
            throw TTSError.networkError("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let authorization = try await authorizationService.authorizationHeader(for: "ElevenLabs", headerType: HeaderType.elevenLabs)
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let controlsByID = Dictionary(uniqueKeysWithValues: styleControls.map { ($0.id, $0) })
        let stability = controlsByID["elevenLabs.stability"].map { settings.styleValue(for: $0) } ?? 0.5
        let similarityBoost = controlsByID["elevenLabs.similarityBoost"].map { settings.styleValue(for: $0) } ?? 0.75
        let style = controlsByID["elevenLabs.style"].map { settings.styleValue(for: $0) } ?? 0.0

        let modelID = settings.providerOption(for: ElevenLabsProviderOptionKey.modelID) ?? ElevenLabsModel.streamingRecommended.rawValue

        let requestBody = buildRequestBody(
            text: processedText,
            modelID: modelID,
            stability: stability,
            similarityBoost: similarityBoost,
            style: style,
            pronunciationDictionaryID: settings.pronunciationDictionaryID
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        activeStreamingTask?.cancel()
        
        let sessionCopy = session
        let authCopy = authorization
        let authServiceRef = authorizationService
        let chunkBufferSize = 8192
        
        activeStreamingTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.activeStreamingTask = nil
                }
            }
            
            do {
                let (bytes, response) = try await sessionCopy.bytes(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    onError(TTSError.networkError("Invalid response"))
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 401 {
                        if authCopy.usedManagedCredential {
                            await MainActor.run {
                                authServiceRef.invalidateManagedCredential(for: .elevenLabs)
                                self?.activeManagedCredential = nil
                            }
                        }
                        onError(TTSError.invalidAPIKey)
                    } else if httpResponse.statusCode == 422 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 4096 { break }
                        }
                        if let elevenLabsError = try? JSONDecoder().decode(ElevenLabsError.self, from: errorData) {
                            onError(TTSError.apiError(elevenLabsError.detail.message))
                        } else {
                            onError(TTSError.apiError("Invalid request"))
                        }
                    } else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 4096 { break }
                        }
                        if let elevenLabsError = try? JSONDecoder().decode(ElevenLabsError.self, from: errorData) {
                            onError(TTSError.streamingError(elevenLabsError.detail.message))
                        } else {
                            onError(TTSError.streamingError("HTTP \(httpResponse.statusCode)"))
                        }
                    }
                    return
                }
                
                var buffer = Data()
                buffer.reserveCapacity(chunkBufferSize)
                
                for try await byte in bytes {
                    if Task.isCancelled { break }
                    buffer.append(byte)
                    
                    if buffer.count >= chunkBufferSize {
                        onChunk(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                
                if !Task.isCancelled {
                    if !buffer.isEmpty {
                        onChunk(buffer)
                    }
                    onComplete()
                }
            } catch {
                if !Task.isCancelled {
                    onError(TTSError.streamingError(error.localizedDescription))
                }
            }
        }
    }
    
    func cancelStreaming() {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
    }
    
    // MARK: - Text Processing
    private func applyPronunciationOverrides(to text: String, overrides: [PronunciationOverride]) -> String {
        guard !overrides.isEmpty else { return text }
        
        var result = text
        for override in overrides {
            let escapedWord = NSRegularExpression.escapedPattern(for: override.word)
            let pattern = "\\b\(escapedWord)\\b"
            
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: override.replacement)
        }
        return result
    }
    
    // MARK: - Request Building
    private func buildRequestBody(
        text: String,
        modelID: String,
        stability: Double,
        similarityBoost: Double,
        style: Double,
        pronunciationDictionaryID: String?
    ) -> ElevenLabsRequest {
        var pronunciationDictionaryLocators: [[String: String]]?
        if let dictID = pronunciationDictionaryID, !dictID.isEmpty {
            pronunciationDictionaryLocators = [["pronunciation_dictionary_id": dictID]]
        }
        
        return ElevenLabsRequest(
            text: text,
            model_id: modelID,
            voice_settings: VoiceSettings(
                stability: stability,
                similarity_boost: similarityBoost,
                style: style,
                use_speaker_boost: true
            ),
            pronunciation_dictionary_locators: pronunciationDictionaryLocators
        )
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


// MARK: - Request/Response Models
private struct ElevenLabsRequest: Encodable {
    let text: String
    let model_id: String
    let voice_settings: VoiceSettings
    let pronunciation_dictionary_locators: [[String: String]]?
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
