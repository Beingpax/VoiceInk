import Foundation
import LLMkit

struct OpenRouterRequestPolicy {
    let model: String
    let temperature: Double?
    let reasoning: OpenRouterReasoning?
    let provider: OpenRouterProviderPreferences

    static func lowLatency(
        modelName: String,
        modelMetadata: OpenRouterModel?
    ) -> OpenRouterRequestPolicy {
        let supportedParameters = Set(modelMetadata?.supportedParameters ?? [])

        return OpenRouterRequestPolicy(
            model: nitroVariant(of: modelName),
            temperature: supportedParameters.contains("temperature") ? 0.3 : nil,
            reasoning: reasoningConfiguration(
                capabilities: modelMetadata?.reasoning,
                supportsReasoningParameter: supportedParameters.contains("reasoning")
            ),
            provider: OpenRouterProviderPreferences(
                sort: .throughput,
                preferredMaxLatency: OpenRouterPercentileThresholds(p90: 2.5),
                requireParameters: true,
                allowFallbacks: true
            )
        )
    }

    private static func nitroVariant(of modelName: String) -> String {
        guard let finalComponent = modelName.split(separator: "/").last,
              !finalComponent.contains(":") else {
            return modelName
        }
        return "\(modelName):nitro"
    }

    private static func reasoningConfiguration(
        capabilities: OpenRouterReasoningCapabilities?,
        supportsReasoningParameter: Bool
    ) -> OpenRouterReasoning? {
        guard supportsReasoningParameter, let capabilities else {
            return nil
        }

        if capabilities.mandatory {
            let minimumEffort = capabilities.supportedEfforts.last
            return OpenRouterReasoning(effort: minimumEffort, exclude: true)
        }

        if capabilities.supportedEfforts.contains("none") {
            return OpenRouterReasoning(effort: "none", exclude: true)
        }

        return OpenRouterReasoning(enabled: false, exclude: true)
    }

    static func outputWasTruncated(finishReason: String?) -> Bool {
        guard let finishReason else { return false }
        return ["length", "max_tokens", "max_output_tokens"].contains(finishReason.lowercased())
    }
}
