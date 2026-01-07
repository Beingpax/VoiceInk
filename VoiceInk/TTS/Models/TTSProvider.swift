import Foundation

// MARK: - TTS Provider Protocols
@MainActor
protocol SpeechSynthesizing {
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data
}

@MainActor
protocol StreamingSpeechSynthesizing {
    func synthesizeSpeechStream(
        text: String,
        voice: Voice,
        settings: AudioSettings,
        onChunk: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws
}

@MainActor
protocol VoiceProviding {
    var availableVoices: [Voice] { get }
    var defaultVoice: Voice { get }
}

@MainActor
protocol StyleCustomizable {
    var styleControls: [ProviderStyleControl] { get }
}

@MainActor
protocol APIKeyValidating {
    func hasValidAPIKey() -> Bool
}

@MainActor
protocol TTSProvider: SpeechSynthesizing, VoiceProviding, StyleCustomizable, APIKeyValidating {
    var name: String { get }
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

// MARK: - Pronunciation Override
struct PronunciationOverride: Codable, Hashable {
    enum OverrideType: String, Codable {
        case ipa
        case arpabet
        case literal
    }
    
    let word: String
    let replacement: String
    let type: OverrideType
    
    init(word: String, replacement: String, type: OverrideType = .literal) {
        self.word = word
        self.replacement = replacement
        self.type = type
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
    var extras: [String: AnyCodable] = [:]
    var pronunciationOverrides: [PronunciationOverride] = []
    var pronunciationDictionaryID: String?
    
    enum AudioFormat: String, CaseIterable {
        case mp3 = "mp3"
        case wav = "wav"
        case aac = "aac"
        case flac = "flac"
        case opus = "opus"
    }
}

struct AnyCodable: Codable, Hashable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
    
    private var typeIdentifier: String {
        switch value {
        case is Bool: return "bool"
        case is Int: return "int"
        case is Double: return "double"
        case is String: return "string"
        case is [Any]: return "array"
        case is [String: Any]: return "dict"
        case is NSNull: return "null"
        default: return "unknown"
        }
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        guard lhs.typeIdentifier == rhs.typeIdentifier else { return false }
        
        switch (lhs.value, rhs.value) {
        case let (l as Bool, r as Bool): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as String, r as String): return l == r
        case (is NSNull, is NSNull): return true
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count else { return false }
            return l.keys.allSatisfy { key in
                guard let lv = l[key], let rv = r[key] else { return false }
                return AnyCodable(lv) == AnyCodable(rv)
            }
        default: return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(typeIdentifier)
        switch value {
        case let bool as Bool: hasher.combine(bool)
        case let int as Int: hasher.combine(int)
        case let double as Double: hasher.combine(double)
        case let string as String: hasher.combine(string)
        case is NSNull: hasher.combine(0)
        case let array as [Any]:
            hasher.combine(array.count)
            for (index, item) in array.prefix(5).enumerated() {
                hasher.combine(index)
                AnyCodable(item).hash(into: &hasher)
            }
        case let dict as [String: Any]:
            hasher.combine(dict.count)
            for key in dict.keys.sorted().prefix(5) {
                hasher.combine(key)
                if let v = dict[key] {
                    AnyCodable(v).hash(into: &hasher)
                }
            }
        default: break
        }
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
    case streamingError(String)
    
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
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
}
