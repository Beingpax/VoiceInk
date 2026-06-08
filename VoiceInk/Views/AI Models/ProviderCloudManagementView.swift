import SwiftUI
import AppKit

struct CloudProviderManagementView: View {
    let selectedProviderID: String?
    let onSelectProvider: (ProviderDescriptor) -> Void

    private var providerDescriptors: [ProviderDescriptor] {
        let enhancementProviders: [AIProvider] = [
            .openAI,
            .openRouter,
            .anthropic,
            .gemini,
            .groq,
            .mistral,
            .cerebras
        ]

        var descriptors = enhancementProviders.map { aiProvider in
            ProviderDescriptor(
                displayName: aiProvider.rawValue,
                providerKey: aiProvider.rawValue,
                aiProvider: aiProvider,
                cloudProvider: matchingCloudProvider(for: aiProvider)
            )
        }

        for cloudProvider in CloudProviderRegistry.allProviders {
            let alreadyIncluded = descriptors.contains {
                $0.providerKey.caseInsensitiveCompare(cloudProvider.providerKey) == .orderedSame
            }
            guard !alreadyIncluded else { continue }

            descriptors.append(
                ProviderDescriptor(
                    displayName: cloudProvider.providerKey,
                    providerKey: cloudProvider.providerKey,
                    aiProvider: nil,
                    cloudProvider: cloudProvider
                )
            )
        }

        let preferredOrder = [
            "Groq", "Cerebras", "Gemini", "OpenAI", "OpenRouter", "Anthropic", "Mistral",
            "Deepgram", "ElevenLabs", "Soniox", "Speechmatics", "AssemblyAI", "xAI", "Cartesia"
        ]

        return descriptors.sorted { first, second in
            let firstIndex = preferredOrder.firstIndex(of: first.displayName) ?? Int.max
            let secondIndex = preferredOrder.firstIndex(of: second.displayName) ?? Int.max
            if firstIndex != secondIndex { return firstIndex < secondIndex }
            return first.displayName < second.displayName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderSectionHeader(
                title: "Cloud Providers",
                subtitle: "Connect providers here, then choose models inside Modes."
            )

            ForEach(providerDescriptors) { descriptor in
                ProviderListRow(
                    descriptor: descriptor,
                    isSelected: selectedProviderID == descriptor.id,
                    onSelect: {
                        onSelectProvider(descriptor)
                    }
                )
            }
        }
    }

    private func matchingCloudProvider(for aiProvider: AIProvider) -> (any CloudProvider)? {
        CloudProviderRegistry.allProviders.first {
            $0.providerKey.caseInsensitiveCompare(aiProvider.rawValue) == .orderedSame
        }
    }
}

struct ProviderDescriptor: Identifiable {
    let displayName: String
    let providerKey: String
    let aiProvider: AIProvider?
    let cloudProvider: (any CloudProvider)?

    var id: String { providerKey }

    var transcriptionModels: [CloudModel] {
        cloudProvider?.models ?? []
    }

    var hasTranscription: Bool {
        !transcriptionModels.isEmpty
    }

    var hasEnhancement: Bool {
        aiProvider != nil
    }

    var brandAssetName: String? {
        switch providerKey.lowercased() {
        case "openai":
            return "provider-openai"
        case "openrouter":
            return "provider-openrouter"
        case "anthropic":
            return "provider-anthropic"
        case "gemini":
            return "provider-gemini"
        case "groq":
            return "provider-groq"
        case "mistral":
            return "provider-mistral"
        case "cerebras":
            return "provider-cerebras"
        case "deepgram":
            return "provider-deepgram"
        case "elevenlabs":
            return "provider-elevenlabs"
        case "soniox":
            return "provider-soniox"
        case "speechmatics":
            return "provider-speechmatics"
        case "assemblyai":
            return "provider-assemblyai"
        case "xai":
            return "provider-xai"
        case "cartesia":
            return "provider-cartesia"
        default:
            return nil
        }
    }

    var apiConsoleURL: URL? {
        switch providerKey.lowercased() {
        case "groq":
            return URL(string: "https://console.groq.com/keys")
        case "cerebras":
            return URL(string: "https://cloud.cerebras.ai/platform")
        case "gemini":
            return URL(string: "https://aistudio.google.com/app/apikey")
        case "openai":
            return URL(string: "https://platform.openai.com/api-keys")
        case "openrouter":
            return URL(string: "https://openrouter.ai/keys")
        case "anthropic":
            return URL(string: "https://console.anthropic.com/settings/keys")
        case "mistral":
            return URL(string: "https://console.mistral.ai/api-keys/")
        case "deepgram":
            return URL(string: "https://console.deepgram.com/project/keys")
        case "elevenlabs":
            return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case "soniox":
            return URL(string: "https://console.soniox.com/api-keys")
        case "speechmatics":
            return URL(string: "https://console.speechmatics.com/")
        case "assemblyai":
            return URL(string: "https://www.assemblyai.com/dashboard/signup")
        case "xai":
            return URL(string: "https://console.x.ai/")
        case "cartesia":
            return URL(string: "https://play.cartesia.ai/keys")
        default:
            return nil
        }
    }
}

private struct ProviderListRow: View {
    @EnvironmentObject private var aiService: AIService

    let descriptor: ProviderDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var statusText: String {
        isConfigured ? "Connected" : "Not connected"
    }

    private var statusColor: Color {
        isConfigured ? AppTheme.Status.positive : .secondary
    }

    private var iconName: String {
        if descriptor.hasTranscription && descriptor.hasEnhancement { return "rectangle.2.swap" }
        if descriptor.hasTranscription { return "captions.bubble.fill" }
        return "sparkles"
    }

    private var capabilitySummary: String {
        var parts: [String] = []

        let transcriptionCount = descriptor.transcriptionModels.count
        if transcriptionCount > 0 {
            parts.append(modelCountText(transcriptionCount, title: "Transcription"))
        }

        if let provider = descriptor.aiProvider {
            let enhancementCount = aiService.availableModels(for: provider).count
            parts.append(modelCountText(enhancementCount, title: "Enhancement"))
        }

        return parts.joined(separator: " · ")
    }

    private func modelCountText(_ count: Int, title: String) -> String {
        "\(count) \(title) \(count == 1 ? "model" : "models")"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ProviderBrandIcon(
                    descriptor: descriptor,
                    fallbackSystemImage: iconName,
                    isSelected: isSelected,
                    size: 28,
                    iconSize: 15
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(capabilitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                ProviderStatusBadge(title: statusText, color: statusColor)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(14)
        }
        .buttonStyle(.plain)
        .background(ProviderSurface(isActive: isSelected, cornerRadius: 10))
    }

}
