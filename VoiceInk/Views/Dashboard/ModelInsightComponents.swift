import Foundation
import SwiftUI

struct ModelDetailActionLabel: View {
    let title: LocalizedStringKey
    var icon: String = "chevron.right"

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)

            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Text.secondary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct InsightPeriodPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: DashboardInsightPeriod

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(DashboardInsightPeriod.allCases) { period in
                Text(period.pickerTitle).tag(period)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

enum ModelLinks {
    static func openRecommendedModels() {
        if let url = URL(string: "https://tryvoiceink.com/docs/recommended-models") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ModelActionLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isPrimary ? Color.white : AppTheme.Text.primary)
        .padding(.horizontal, isPrimary ? 14 : 12)
        .frame(height: 34)
        .background(isPrimary ? AppTheme.Accent.primary : AppTheme.Surface.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isPrimary ? AppTheme.Accent.border.opacity(0.45) : AppTheme.Border.subtle.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.clear, radius: 0)
    }
}

struct InsightEmptyState: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
    }
}

struct ModelProviderIcon: View {
    let modelName: String
    let kind: ModelInsightKind
    var size: CGFloat = 24

    var body: some View {
        let identity = ModelProviderIdentity.resolve(modelName: modelName, kind: kind)

        ProviderBrandIcon(
            descriptor: identity.descriptor,
            fallbackSystemImage: identity.fallbackSystemImage,
            isSelected: false,
            size: size,
            iconSize: max(12, size * 0.54)
        )
        .help(identity.providerName)
    }
}

private struct ModelProviderIdentity {
    let providerName: String
    let descriptor: ProviderDescriptor
    let fallbackSystemImage: String

    static func resolve(modelName: String, kind: ModelInsightKind) -> ModelProviderIdentity {
        switch kind {
        case .transcription:
            return resolveTranscription(modelName)
        case .enhancement:
            return resolveEnhancement(modelName)
        }
    }

    private static func resolveTranscription(_ modelName: String) -> ModelProviderIdentity {
        let trimmedName = normalized(modelName)

        if let model = TranscriptionModelRegistry.models.first(where: { model in
            namesMatch(model.displayName, trimmedName) || namesMatch(model.name, trimmedName)
        }) {
            return identity(for: model.provider)
        }

        if trimmedName.localizedCaseInsensitiveContains("parakeet") ||
            trimmedName.localizedCaseInsensitiveContains("nemotron") {
            return identity(for: .fluidAudio)
        }

        if trimmedName.localizedCaseInsensitiveContains("apple") {
            return identity(for: .nativeApple)
        }

        if trimmedName.localizedCaseInsensitiveContains("whisper") ||
            trimmedName.localizedCaseInsensitiveContains("large") ||
            trimmedName.localizedCaseInsensitiveContains("base") ||
            trimmedName.localizedCaseInsensitiveContains("tiny") {
            return identity(for: .whisper)
        }

        return unknownIdentity(providerName: String(localized: "Transcription Model"), fallbackSystemImage: "captions.bubble.fill")
    }

    private static func resolveEnhancement(_ modelName: String) -> ModelProviderIdentity {
        let trimmedName = normalized(modelName)

        if let customProvider = CustomAIProviderManager.shared.provider(forModel: trimmedName) {
            return ModelProviderIdentity(
                providerName: customProvider.name,
                descriptor: descriptor(displayName: customProvider.name, providerKey: "Custom"),
                fallbackSystemImage: "slider.horizontal.3"
            )
        }

        let matchingProviders = AIProvider.allCases.filter { provider in
            providerMatches(provider, modelName: trimmedName)
        }

        if matchingProviders.count == 1,
           let provider = matchingProviders.first {
            return identity(for: provider)
        }

        if matchingProviders.isEmpty,
           let provider = inferredEnhancementProvider(from: trimmedName) {
            return identity(for: provider)
        }

        return unknownIdentity(providerName: String(localized: "Enhancement Model"), fallbackSystemImage: "cpu")
    }

    private static func identity(for provider: ModelProvider) -> ModelProviderIdentity {
        let cloudProvider = CloudProviderRegistry.provider(for: provider)
        let aiProvider = AIProvider(rawValue: provider.rawValue)
        let displayName: String
        let providerKey: String
        let fallbackSystemImage: String

        switch provider {
        case .whisper:
            displayName = "Whisper"
            providerKey = "Whisper"
            fallbackSystemImage = "captions.bubble.fill"
        case .fluidAudio:
            displayName = "Parakeet"
            providerKey = "Parakeet"
            fallbackSystemImage = "waveform"
        case .nativeApple:
            displayName = "Apple Speech"
            providerKey = "Native Apple"
            fallbackSystemImage = "apple.logo"
        case .custom:
            displayName = "Custom"
            providerKey = "Custom"
            fallbackSystemImage = "slider.horizontal.3"
        default:
            displayName = cloudProvider?.providerKey ?? provider.rawValue
            providerKey = cloudProvider?.providerKey ?? provider.rawValue
            fallbackSystemImage = "cloud.fill"
        }

        return ModelProviderIdentity(
            providerName: displayName,
            descriptor: descriptor(
                displayName: displayName,
                providerKey: providerKey,
                aiProvider: aiProvider,
                cloudProvider: cloudProvider
            ),
            fallbackSystemImage: fallbackSystemImage
        )
    }

    private static func identity(for provider: AIProvider) -> ModelProviderIdentity {
        let cloudProvider = CloudProviderRegistry.allProviders.first {
            $0.providerKey.caseInsensitiveCompare(provider.rawValue) == .orderedSame
        }
        let fallbackSystemImage: String

        switch provider {
        case .ollama:
            fallbackSystemImage = "server.rack"
        case .localCLI:
            fallbackSystemImage = "terminal"
        case .custom:
            fallbackSystemImage = "slider.horizontal.3"
        default:
            fallbackSystemImage = "cloud.fill"
        }

        return ModelProviderIdentity(
            providerName: provider.rawValue,
            descriptor: descriptor(
                displayName: provider.rawValue,
                providerKey: provider.rawValue,
                aiProvider: provider,
                cloudProvider: cloudProvider
            ),
            fallbackSystemImage: fallbackSystemImage
        )
    }

    private static func unknownIdentity(providerName: String, fallbackSystemImage: String) -> ModelProviderIdentity {
        ModelProviderIdentity(
            providerName: providerName,
            descriptor: descriptor(displayName: providerName, providerKey: providerName),
            fallbackSystemImage: fallbackSystemImage
        )
    }

    private static func descriptor(
        displayName: String,
        providerKey: String,
        aiProvider: AIProvider? = nil,
        cloudProvider: (any CloudProvider)? = nil
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            displayName: displayName,
            providerKey: providerKey,
            aiProvider: aiProvider,
            cloudProvider: cloudProvider
        )
    }

    private static func providerMatches(_ provider: AIProvider, modelName: String) -> Bool {
        if namesMatch(provider.defaultModel, modelName) {
            return true
        }

        return provider.availableModels.contains { availableModel in
            namesMatch(availableModel, modelName)
        }
    }

    private static func inferredEnhancementProvider(from modelName: String) -> AIProvider? {
        let lowercaseName = modelName.lowercased()

        if lowercaseName.hasPrefix("gemini-") {
            return .gemini
        }

        if lowercaseName.hasPrefix("claude-") {
            return .anthropic
        }

        if lowercaseName.hasPrefix("mistral-") {
            return .mistral
        }

        if lowercaseName.hasPrefix("zai-") {
            return .cerebras
        }

        if lowercaseName.hasPrefix("gpt-") {
            return .openAI
        }

        return nil
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs).caseInsensitiveCompare(normalized(rhs)) == .orderedSame
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
