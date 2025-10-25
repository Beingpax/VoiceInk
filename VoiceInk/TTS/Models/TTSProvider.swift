import Foundation

// MARK: - TTS Provider Protocol
@MainActor
protocol TTSProvider {
    var name: String { get }
    var availableVoices: [Voice] { get }
    var defaultVoice: Voice { get }
    var styleControls: [ProviderStyleControl] { get }
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data
    func hasValidAPIKey() -> Bool
}

extension TTSProvider {
    var styleControls: [ProviderStyleControl] { [] }
}

// MARK: - Voice Model
struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let gender: Gender
    let provider: ProviderType
    let previewURL: String?
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        case neutral = "Neutral"
    }
    
    enum ProviderType: String {
        case elevenLabs = "ElevenLabs"
        case openAI = "OpenAI"
        case google = "Google"
        case tightAss = "Tight Ass Mode"
    }
}

// MARK: - Provider Style Control
struct ProviderStyleControl: Identifiable, Hashable {
    enum ValueFormat: Hashable {
        case percentage
        case decimal(places: Int)
    }

    let id: String
    let label: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double?
    let valueFormat: ValueFormat
    let helpText: String?

    init(id: String,
         label: String,
         range: ClosedRange<Double>,
         defaultValue: Double,
         step: Double? = nil,
         valueFormat: ValueFormat = .decimal(places: 2),
         helpText: String? = nil) {
        self.id = id
        self.label = label
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.valueFormat = valueFormat
        self.helpText = helpText
    }

    func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func formattedValue(for value: Double) -> String {
        let clampedValue = clamp(value)
        switch valueFormat {
        case .percentage:
            return "\(Int(round(clampedValue * 100)))%"
        case .decimal(let places):
            let decimals = max(0, places)
            return String(format: "%.*f", decimals, clampedValue)
        }
    }
}

// MARK: - Audio Settings
struct AudioSettings {
    var speed: Double = 1.0      // 0.5 to 2.0
    var pitch: Double = 1.0      // 0.5 to 2.0
    var volume: Double = 1.0     // 0.0 to 1.0
    var format: AudioFormat = .mp3
    var sampleRate: Int = 22050
    var styleValues: [String: Double] = [:]
    var providerOptions: [String: String] = [:]
    
    enum AudioFormat: String, CaseIterable {
        case mp3 = "mp3"
        case wav = "wav"
        case aac = "aac"
        case flac = "flac"
        case opus = "opus"
    }
}

extension AudioSettings {
    func styleValue(for control: ProviderStyleControl) -> Double {
        let value = styleValues[control.id] ?? control.defaultValue
        return control.clamp(value)
    }

    func styleValue(for controlID: String,
                    default defaultValue: Double,
                    clampedTo range: ClosedRange<Double>) -> Double {
        let value = styleValues[controlID] ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }

    func providerOption(for key: String) -> String? {
        providerOptions[key]
    }
}

// MARK: - Speech Request
struct SpeechRequest {
    let text: String
    let voice: Voice
    let settings: AudioSettings
    let timestamp: Date = Date()
}

// MARK: - API Error
enum TTSError: LocalizedError {
    case invalidAPIKey
    case networkError(String)
    case quotaExceeded
    case invalidVoice
    case textTooLong(Int)
    case unsupportedFormat
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .networkError(let message):
            return "Network error: \(message)"
        case .quotaExceeded:
            return "API quota exceeded. Please check your usage limits."
        case .invalidVoice:
            return "Selected voice is not available."
        case .textTooLong(let limit):
            return "Text exceeds maximum length of \(limit) characters."
        case .unsupportedFormat:
            return "Selected audio format is not supported."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
