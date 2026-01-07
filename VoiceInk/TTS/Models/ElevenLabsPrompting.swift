import Foundation

enum ElevenLabsProviderOptionKey {
    static let modelID = "elevenLabs.model_id"
    static let optimizeStreamingLatency = "elevenLabs.optimize_streaming_latency"
    static let outputFormat = "elevenLabs.output_format"
}

struct ElevenLabsModelIdentifier: Hashable, Codable {
    let rawValue: String
    
    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    init(from model: ElevenLabsModel) {
        self.rawValue = model.rawValue
    }
    
    var knownModel: ElevenLabsModel? {
        ElevenLabsModel(rawValue: rawValue)
    }
}

enum ElevenLabsModel: String, CaseIterable, Identifiable {
    case flashV2_5 = "eleven_flash_v2_5"
    case turboV2_5 = "eleven_turbo_v2_5"
    case turboV3 = "eleven_turbo_v3"
    case multilingualV3 = "eleven_multilingual_v3"
    case turboV2 = "eleven_turbo_v2"
    case multilingualV2 = "eleven_multilingual_v2"
    case monolingualV1 = "eleven_monolingual_v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flashV2_5:
            return "Flash v2.5"
        case .turboV2_5:
            return "Turbo v2.5"
        case .turboV3:
            return "Turbo v3"
        case .multilingualV3:
            return "Multilingual v3"
        case .turboV2:
            return "Turbo v2"
        case .multilingualV2:
            return "Multilingual v2"
        case .monolingualV1:
            return "Monolingual v1"
        }
    }

    var detail: String {
        switch self {
        case .flashV2_5:
            return "Ultra-low latency model optimized for real-time streaming. Best for conversational use."
        case .turboV2_5:
            return "Balanced speed and quality with improved naturalness. Recommended for most use cases."
        case .turboV3:
            return "Fastest v3 model with expressive prompting and tagging support."
        case .multilingualV3:
            return "V3 multilingual stack tuned for richer prompting cues."
        case .turboV2:
            return "Legacy turbo voice with limited tag coverage."
        case .multilingualV2:
            return "Stable multilingual model without advanced prompting."
        case .monolingualV1:
            return "Fallback English-only model for maximal compatibility."
        }
    }

    var fallback: ElevenLabsModel? {
        switch self {
        case .flashV2_5:
            return .turboV2_5
        case .turboV2_5:
            return .turboV2
        case .turboV3:
            return .turboV2
        case .multilingualV3:
            return .multilingualV2
        default:
            return nil
        }
    }

    var supportsStreaming: Bool {
        switch self {
        case .flashV2_5, .turboV2_5, .turboV3, .multilingualV3, .turboV2, .multilingualV2:
            return true
        case .monolingualV1:
            return false
        }
    }
    
    var supportsAdvancedPrompting: Bool {
        switch self {
        case .flashV2_5, .turboV2_5, .turboV3, .multilingualV3:
            return true
        default:
            return false
        }
    }

    var requiresEarlyAccess: Bool { false }

    static var defaultSelection: ElevenLabsModel { .turboV2_5 }
    
    static var streamingRecommended: ElevenLabsModel { .flashV2_5 }
}

struct ElevenLabsVoiceTag: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case pacing = "Pacing"
        case emotion = "Emotion"
        case delivery = "Delivery"
        case breathing = "Breath"
        case scene = "Scene"
    }

    let id: String
    let token: String
    let summary: String
    let category: Category

    init(token: String, summary: String, category: Category) {
        self.id = token
        self.token = token
        self.summary = summary
        self.category = category
    }
}

extension ElevenLabsVoiceTag {
    static let defaultCatalog: [ElevenLabsVoiceTag] = [
        ElevenLabsVoiceTag(token: "[pause_short]", summary: "Insert a brief ~0.5s pause.", category: .pacing),
        ElevenLabsVoiceTag(token: "[pause_long]", summary: "Insert a longer ~1.5s pause for dramatic beats.", category: .pacing),
        ElevenLabsVoiceTag(token: "[pause_medium]", summary: "Insert a ~1s pause for natural breaks.", category: .pacing),
        ElevenLabsVoiceTag(token: "[whisper]", summary: "Drop to a whisper for the next utterance.", category: .delivery),
        ElevenLabsVoiceTag(token: "[shout]", summary: "Deliver the next phrase with higher energy.", category: .delivery),
        ElevenLabsVoiceTag(token: "[soft]", summary: "Speak softly with a gentle tone.", category: .delivery),
        ElevenLabsVoiceTag(token: "[emphatic]", summary: "Add emphasis to the next phrase.", category: .delivery),
        ElevenLabsVoiceTag(token: "[laugh]", summary: "Adds a short laugh before continuing.", category: .emotion),
        ElevenLabsVoiceTag(token: "[soft_laugh]", summary: "Adds a softer laugh for playful beats.", category: .emotion),
        ElevenLabsVoiceTag(token: "[chuckle]", summary: "A brief chuckle for light amusement.", category: .emotion),
        ElevenLabsVoiceTag(token: "[sigh]", summary: "Produces an audible sigh.", category: .emotion),
        ElevenLabsVoiceTag(token: "[gasp]", summary: "Quick inhale to express surprise or shock.", category: .emotion),
        ElevenLabsVoiceTag(token: "[breath_in]", summary: "Audible inhale before the next line.", category: .breathing),
        ElevenLabsVoiceTag(token: "[breath_out]", summary: "Audible exhale to release tension.", category: .breathing),
        ElevenLabsVoiceTag(token: "[smile]", summary: "Adds a slight smile to the delivery.", category: .emotion),
        ElevenLabsVoiceTag(token: "[excited]", summary: "Convey excitement in the delivery.", category: .emotion),
        ElevenLabsVoiceTag(token: "[sad]", summary: "Convey sadness in the delivery.", category: .emotion),
        ElevenLabsVoiceTag(token: "[narration_scene_change]", summary: "Signals a new scene or location shift.", category: .scene),
        ElevenLabsVoiceTag(token: "[narration_dialogue]", summary: "Switch to dialogue narration style.", category: .scene),
        ElevenLabsVoiceTag(token: "[narration_internal]", summary: "Internal monologue or thought style.", category: .scene)
    ]

    static var defaultTokens: [String] {
        defaultCatalog.map { $0.token }
    }
}
