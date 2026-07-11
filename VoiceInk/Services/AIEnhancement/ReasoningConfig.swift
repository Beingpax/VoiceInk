import Foundation

struct ReasoningConfig {
    static let geminiNoneReasoningModels: Set<String> = []

    // Gemini 3.1 Pro maps "minimal" to "low"; send "low" directly.
    static let geminiLowReasoningModels: Set<String> = [
        "gemini-3.1-pro-preview"
    ]

    // These Gemini models only go down to "minimal".
    static let geminiMinimalReasoningModels: Set<String> = [
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
    ]

    // OpenAI GPT-5 models support explicit "none"; GPT-4.1 models need no param.
    static let openAINoneReasoningModels: Set<String> = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
    ]

    // Cerebras GPT-OSS has no true "none"; use lowest effort.
    static let cerebrasGPTOSSMinimumReasoningModels: Set<String> = [
        "gpt-oss-120b"
    ]

    // Groq GPT-OSS has no true "none"; use lowest effort.
    static let groqGPTOSSMinimumReasoningModels: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
    ]

    // Cerebras GLM supports "none".
    static let cerebrasNoneReasoningModels: Set<String> = [
        "zai-glm-4.7"
    ]

    static func getReasoningParameter(for provider: AIProvider, modelName: String) -> String? {
        switch provider {
        case .gemini:
            if geminiNoneReasoningModels.contains(modelName) {
                return "none"
            } else if geminiLowReasoningModels.contains(modelName) {
                return "low"
            } else if geminiMinimalReasoningModels.contains(modelName) {
                return "minimal"
            }
        case .openAI:
            if openAINoneReasoningModels.contains(modelName) { return "none" }
        case .cerebras:
            if cerebrasGPTOSSMinimumReasoningModels.contains(modelName) {
                return "low"
            } else if cerebrasNoneReasoningModels.contains(modelName) {
                return "none"
            }
        case .groq:
            if groqGPTOSSMinimumReasoningModels.contains(modelName) { return "low" }
        default:
            return nil
        }
        return nil
    }

    // Provider-specific body params for hiding reasoning.
    static func getExtraBodyParameters(for provider: AIProvider, modelName: String) -> [String: Any]? {
        if provider == .cerebras && modelName == "gpt-oss-120b" {
            return ["reasoning_format": "hidden"]
        } else if provider == .groq && (modelName == "openai/gpt-oss-120b" || modelName == "openai/gpt-oss-20b") {
            return ["include_reasoning": false]
        }
        return nil
    }
}
