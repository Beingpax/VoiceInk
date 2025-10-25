import Foundation

@MainActor
class GoogleTTSService: TTSProvider {
    // MARK: - Properties
    var name: String { "Google Cloud TTS" }
    private var apiKey: String?
    private let baseURL = "https://texttospeech.googleapis.com/v1/text:synthesize"
    private let session: URLSession
    private let managedProvisioningClient: ManagedProvisioningClient
    private var activeManagedCredential: ManagedCredential?
    
    // MARK: - Default Voice
    var defaultVoice: Voice {
        Voice(
            id: "en-US-Neural2-F",
            name: "Neural2 Female",
            language: "en-US",
            gender: .female,
            provider: .google,
            previewURL: nil
        )
    }
    
    // MARK: - Available Voices
    var availableVoices: [Voice] {
        // Google Cloud TTS has many voices, these are some popular ones
        // In production, you would fetch these from the API
        return [
            // Neural2 voices (highest quality)
            Voice(id: "en-US-Neural2-A", name: "Neural2 Male A", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-C", name: "Neural2 Female C", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-D", name: "Neural2 Male D", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-E", name: "Neural2 Female E", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-F", name: "Neural2 Female F", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-G", name: "Neural2 Female G", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-H", name: "Neural2 Female H", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-I", name: "Neural2 Male I", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Neural2-J", name: "Neural2 Male J", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            
            // WaveNet voices (high quality)
            Voice(id: "en-US-Wavenet-A", name: "WaveNet Male A", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Wavenet-B", name: "WaveNet Male B", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Wavenet-C", name: "WaveNet Female C", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Wavenet-D", name: "WaveNet Male D", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Wavenet-E", name: "WaveNet Female E", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Wavenet-F", name: "WaveNet Female F", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            
            // Standard voices (lower cost)
            Voice(id: "en-US-Standard-A", name: "Standard Male A", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Standard-B", name: "Standard Male B", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Standard-C", name: "Standard Female C", language: "en-US", gender: .female, provider: .google, previewURL: nil),
            Voice(id: "en-US-Standard-D", name: "Standard Male D", language: "en-US", gender: .male, provider: .google, previewURL: nil),
            Voice(id: "en-US-Standard-E", name: "Standard Female E", language: "en-US", gender: .female, provider: .google, previewURL: nil)
        ]
    }
    
    var styleControls: [ProviderStyleControl] {
        [
            ProviderStyleControl(
                id: "google.briskness",
                label: "Briskness",
                range: 0...1,
                defaultValue: 0.5,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Increase for faster deliveries; decrease for a relaxed cadence."
            ),
            ProviderStyleControl(
                id: "google.intonation",
                label: "Intonation",
                range: 0...1,
                defaultValue: 0.5,
                step: 0.05,
                valueFormat: .percentage,
                helpText: "Blend in additional pitch variation to emphasize key phrases."
            )
        ]
    }
    
    // MARK: - Initialization
    init(session: URLSession = SecureURLSession.makeEphemeral(),
         managedProvisioningClient: ManagedProvisioningClient = .shared) {
        self.session = session
        self.managedProvisioningClient = managedProvisioningClient
        // Load API key from keychain if available
        self.apiKey = KeychainManager().getAPIKey(for: "Google")
    }
    
    // MARK: - API Key Management
    func updateAPIKey(_ key: String) {
        self.apiKey = key
    }
    
    func hasValidAPIKey() -> Bool {
        if let key = apiKey, !key.isEmpty { return true }
        return managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }
    
    // MARK: - Speech Synthesis
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard text.count <= 5000 else {
            throw TTSError.textTooLong(5000)
        }
        
        guard let url = URL(string: baseURL) else {
            throw TTSError.networkError("Invalid URL")
        }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.timeoutInterval = 45

        // Parse voice ID to get language code and name
        let voiceComponents = voice.id.split(separator: "-")
        let languageCode = voiceComponents.prefix(2).joined(separator: "-")
        
        // Determine SSML gender
        let ssmlGender: String
        switch voice.gender {
        case .male:
            ssmlGender = "MALE"
        case .female:
            ssmlGender = "FEMALE"
        default:
            ssmlGender = "NEUTRAL"
        }
        
        // Prepare request body
        let controlLookup = Dictionary(uniqueKeysWithValues: styleControls.map { ($0.id, $0) })
        let briskness = controlLookup["google.briskness"].map { settings.styleValue(for: $0) } ?? 0.5
        let intonation = controlLookup["google.intonation"].map { settings.styleValue(for: $0) } ?? 0.5

        let tuning = tuningParameters(for: voice.id)

        let sliderRateMultiplier = tuning.rateBaseline + briskness * tuning.rateSpread
        let speakingRate = clamp(
            value: settings.speed * sliderRateMultiplier,
            lower: tuning.minRate,
            upper: tuning.maxRate
        )

        let basePitchOffset = (settings.pitch - 1.0) * tuning.basePitchScale
        let sliderPitchOffset = tuning.pitchBaseline + (intonation - 0.5) * tuning.pitchSpread
        let pitch = clamp(value: basePitchOffset + sliderPitchOffset, lower: tuning.minPitch, upper: tuning.maxPitch)

        let requestBody = GoogleTTSRequest(
            input: InputText(text: text),
            voice: VoiceSelection(
                languageCode: languageCode,
                name: voice.id,
                ssmlGender: ssmlGender
            ),
            audioConfig: AudioConfig(
                audioEncoding: settings.format.googleFormat,
                speakingRate: speakingRate,
                pitch: pitch,
                volumeGainDb: convertVolumeToDb(settings.volume),
                sampleRateHertz: settings.sampleRate
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
                    // Parse response to get audio content
                    let ttsResponse = try JSONDecoder().decode(GoogleTTSResponse.self, from: data)
                    
                    // Decode base64 audio content
                    guard let audioData = Data(base64Encoded: ttsResponse.audioContent) else {
                        throw TTSError.apiError("Failed to decode audio content")
                    }
                    
                    return audioData
                case 400:
                    if let errorData = try? JSONDecoder().decode(GoogleError.self, from: data) {
                        throw TTSError.apiError(errorData.error.message)
                    }
                    throw TTSError.apiError("Bad request")
                case 401, 403:
                    if authorization.usedManagedCredential {
                        managedProvisioningClient.invalidateCredential(for: .google)
                        activeManagedCredential = nil
                    }
                    throw TTSError.invalidAPIKey
                case 429:
                    throw TTSError.quotaExceeded
                case 400...499:
                    if let errorData = try? JSONDecoder().decode(GoogleError.self, from: data) {
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
    
    // MARK: - Helper Methods
    private func convertVolumeToDb(_ volume: Double) -> Double {
        // Convert 0-1 volume to -96 to 16 dB range
        // 0.5 = 0 dB (normal volume)
        if volume <= 0 {
            return -96.0
        } else if volume >= 1 {
            return 16.0
        } else {
            // Logarithmic scale conversion
            let db = 20 * log10(volume * 2)
            return max(-96, min(16, db))
        }
    }
}

// MARK: - Request/Response Models
private struct GoogleTTSRequest: Codable {
    let input: InputText
    let voice: VoiceSelection
    let audioConfig: AudioConfig
}

private struct InputText: Codable {
    let text: String
}

private struct VoiceSelection: Codable {
    let languageCode: String
    let name: String
    let ssmlGender: String
}

private struct AudioConfig: Codable {
    let audioEncoding: String
    let speakingRate: Double
    let pitch: Double
    let volumeGainDb: Double
    let sampleRateHertz: Int
}

private struct GoogleTTSResponse: Codable {
    let audioContent: String
}

// MARK: - Helpers
private func clamp(value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

struct VoiceStyleTuning {
    let rateBaseline: Double
    let rateSpread: Double
    let minRate: Double
    let maxRate: Double
    let basePitchScale: Double
    let pitchBaseline: Double
    let pitchSpread: Double
    let minPitch: Double
    let maxPitch: Double
}

extension GoogleTTSService {
    func tuningParameters(for voiceID: String) -> VoiceStyleTuning {
        if voiceID.lowercased().contains("neural") {
            return VoiceStyleTuning(
                rateBaseline: 0.95,
                rateSpread: 0.35,
                minRate: 0.5,
                maxRate: 2.3,
                basePitchScale: 5.0,
                pitchBaseline: 0.0,
                pitchSpread: 10.0,
                minPitch: -10.0,
                maxPitch: 12.0
            )
        }

        if voiceID.lowercased().contains("wavenet") {
            return VoiceStyleTuning(
                rateBaseline: 0.9,
                rateSpread: 0.45,
                minRate: 0.4,
                maxRate: 2.6,
                basePitchScale: 6.0,
                pitchBaseline: 0.0,
                pitchSpread: 12.0,
                minPitch: -12.0,
                maxPitch: 12.0
            )
        }

        return VoiceStyleTuning(
            rateBaseline: 0.8,
            rateSpread: 0.6,
            minRate: 0.3,
            maxRate: 3.0,
            basePitchScale: 7.0,
            pitchBaseline: -1.5,
            pitchSpread: 14.0,
            minPitch: -14.0,
            maxPitch: 14.0
        )
    }
}

private struct GoogleError: Codable {
    let error: GoogleErrorDetail
}

private struct GoogleErrorDetail: Codable {
    let code: Int
    let message: String
    let status: String?
}

private extension GoogleTTSService {
    struct AuthorizationHeader {
        let header: String
        let value: String
        let usedManagedCredential: Bool
    }

    func authorizationHeader() async throws -> AuthorizationHeader {
        if let key = apiKey, !key.isEmpty {
            return AuthorizationHeader(header: "X-Goog-Api-Key", value: key, usedManagedCredential: false)
        }

        guard let credential = try await managedProvisioningClient.credential(for: .google) else {
            throw TTSError.invalidAPIKey
        }

        activeManagedCredential = credential
        return AuthorizationHeader(header: "X-Goog-Api-Key", value: credential.token, usedManagedCredential: true)
    }
}

// MARK: - Format Extensions
private extension AudioSettings.AudioFormat {
    var googleFormat: String {
        switch self {
        case .mp3:
            return "MP3"
        case .wav:
            return "LINEAR16"
        case .opus:
            return "OGG_OPUS"
        case .aac:
            return "MP3"  // Google doesn't support AAC directly, use MP3
        case .flac:
            return "MP3"  // Google doesn't support FLAC directly, use MP3
        }
    }
}

// MARK: - Voice Extensions
extension Voice {
    static var googleVoices: [Voice] {
        return [
            // Neural2 voices
            Voice(
                id: "en-US-Neural2-A",
                name: "Neural2 Male A",
                language: "en-US",
                gender: .male,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Neural2-C",
                name: "Neural2 Female C",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Neural2-D",
                name: "Neural2 Male D",
                language: "en-US",
                gender: .male,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Neural2-E",
                name: "Neural2 Female E",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Neural2-F",
                name: "Neural2 Female F",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            ),
            
            // WaveNet voices
            Voice(
                id: "en-US-Wavenet-A",
                name: "WaveNet Male A",
                language: "en-US",
                gender: .male,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Wavenet-C",
                name: "WaveNet Female C",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Wavenet-D",
                name: "WaveNet Male D",
                language: "en-US",
                gender: .male,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Wavenet-E",
                name: "WaveNet Female E",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            ),
            Voice(
                id: "en-US-Wavenet-F",
                name: "WaveNet Female F",
                language: "en-US",
                gender: .female,
                provider: .google,
                previewURL: nil
            )
        ]
    }
}
