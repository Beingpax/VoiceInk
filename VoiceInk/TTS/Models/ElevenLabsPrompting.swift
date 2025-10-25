import Foundation

enum ElevenLabsProviderOptionKey {
    static let modelID = "elevenLabs.model_id"
}

enum ElevenLabsModel: String, CaseIterable, Identifiable {
    case turboV3 = "eleven_turbo_v3"
    case multilingualV3 = "eleven_multilingual_v3"
    case turboV2 = "eleven_turbo_v2"
    case multilingualV2 = "eleven_multilingual_v2"
    case monolingualV1 = "eleven_monolingual_v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turboV3:
            return "Turbo v3 (alpha)"
        case .multilingualV3:
            return "Multilingual v3 (alpha)"
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
        case .turboV3:
            return "Fastest v3 model with expressive prompting and tagging support. Requires early access."
        case .multilingualV3:
            return "V3 multilingual stack tuned for richer prompting cues. Requires early access."
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
        case .turboV3:
            return .turboV2
        case .multilingualV3:
            return .multilingualV2
        default:
            return nil
        }
    }

    var requiresEarlyAccess: Bool { fallback != nil }

    static var defaultSelection: ElevenLabsModel { .multilingualV2 }
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
        ElevenLabsVoiceTag(token: "[whisper]", summary: "Drop to a whisper for the next utterance.", category: .delivery),
        ElevenLabsVoiceTag(token: "[shout]", summary: "Deliver the next phrase with higher energy.", category: .delivery),
        ElevenLabsVoiceTag(token: "[laugh]", summary: "Adds a short laugh before continuing.", category: .emotion),
        ElevenLabsVoiceTag(token: "[soft_laugh]", summary: "Adds a softer laugh for playful beats.", category: .emotion),
        ElevenLabsVoiceTag(token: "[sigh]", summary: "Produces an audible sigh.", category: .emotion),
        ElevenLabsVoiceTag(token: "[gasp]", summary: "Quick inhale to express surprise or shock.", category: .emotion),
        ElevenLabsVoiceTag(token: "[breath_in]", summary: "Audible inhale before the next line.", category: .breathing),
        ElevenLabsVoiceTag(token: "[breath_out]", summary: "Audible exhale to release tension.", category: .breathing),
        ElevenLabsVoiceTag(token: "[smile]", summary: "Adds a slight smile to the delivery.", category: .emotion),
        ElevenLabsVoiceTag(token: "[narration_scene_change]", summary: "Signals a new scene or location shift.", category: .scene)
    ]

    static var defaultTokens: [String] {
        defaultCatalog.map { $0.token }
    }
}
