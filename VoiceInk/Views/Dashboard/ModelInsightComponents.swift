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
        Menu {
            ForEach(DashboardInsightPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    HStack {
                        Text(period.pickerTitle)

                        if period == selection {
                            Spacer()

                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary.opacity(0.86))

                Text(selection.pickerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.Text.secondary.opacity(0.70))
            }
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(AppTheme.Surface.subtle.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(AppTheme.Border.subtle.opacity(0.70), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(Text(title))
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
                .stroke(
                    isPrimary ? AppTheme.Accent.border.opacity(0.45) : AppTheme.Border.subtle.opacity(0.65),
                    lineWidth: 1)
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

struct ModelPreviewCardHeader: View {
    let title: LocalizedStringKey
    var infoTip: LocalizedStringKey?
    let viewMoreHelp: String
    let onViewMore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            if let infoTip {
                InfoTip(infoTip)
                    .help(Text(infoTip))
            }

            Spacer(minLength: 0)

            Button(action: onViewMore) {
                ModelDetailActionLabel(title: "View details")
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help(viewMoreHelp)
        }
    }
}

struct ModelPreviewRow: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let value: String
    let sessionCount: Int

    var kindTitle: String {
        kind == .transcription ? String(localized: "Transcription") : String(localized: "Enhancement")
    }
}

extension Array where Element == ModelPreviewRow {
    func sortedByUsagePriority() -> [ModelPreviewRow] {
        sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount {
                return lhs.sessionCount > rhs.sessionCount
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct ModelPreviewColumnsRow: View {
    let leftTitle: LocalizedStringKey
    let leftValueTitle: LocalizedStringKey
    let leftEmptyTitle: LocalizedStringKey
    let leftEmptyIcon: String
    let leftRows: [ModelPreviewRow]

    let rightTitle: LocalizedStringKey
    let rightValueTitle: LocalizedStringKey
    let rightEmptyTitle: LocalizedStringKey
    let rightEmptyIcon: String
    let rightRows: [ModelPreviewRow]

    let overallEmptyTitle: LocalizedStringKey
    let overallEmptyIcon: String
    var valueColumnWidth: CGFloat = 80

    var body: some View {
        if leftRows.isEmpty && rightRows.isEmpty {
            InsightEmptyState(title: overallEmptyTitle, icon: overallEmptyIcon)
        } else {
            HStack(alignment: .top, spacing: 18) {
                ModelPreviewColumn(
                    title: leftTitle,
                    valueTitle: leftValueTitle,
                    emptyTitle: leftEmptyTitle,
                    emptyIcon: leftEmptyIcon,
                    rows: leftRows,
                    valueColumnWidth: valueColumnWidth
                )

                Divider()
                    .opacity(0.45)

                ModelPreviewColumn(
                    title: rightTitle,
                    valueTitle: rightValueTitle,
                    emptyTitle: rightEmptyTitle,
                    emptyIcon: rightEmptyIcon,
                    rows: rightRows,
                    valueColumnWidth: valueColumnWidth
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModelPreviewColumn: View {
    let title: LocalizedStringKey
    let valueTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let rows: [ModelPreviewRow]
    let valueColumnWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(valueTitle)
                    .frame(width: valueColumnWidth, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)

            if rows.isEmpty {
                InsightEmptyState(title: emptyTitle, icon: emptyIcon)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        ModelPreviewRowView(row: row, valueColumnWidth: valueColumnWidth)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelPreviewRowView: View {
    let row: ModelPreviewRow
    let valueColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 22)

            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: valueColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(AppCardBackground(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kindTitle), \(row.value)")
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

        if trimmedName.localizedCaseInsensitiveContains("parakeet")
            || trimmedName.localizedCaseInsensitiveContains("nemotron")
        {
            return identity(for: .fluidAudio)
        }

        if trimmedName.localizedCaseInsensitiveContains("apple") {
            return identity(for: .nativeApple)
        }

        if trimmedName.localizedCaseInsensitiveContains("whisper")
            || trimmedName.localizedCaseInsensitiveContains("large")
            || trimmedName.localizedCaseInsensitiveContains("base")
            || trimmedName.localizedCaseInsensitiveContains("tiny")
        {
            return identity(for: .whisper)
        }

        return unknownIdentity(
            providerName: String(localized: "Transcription Model"), fallbackSystemImage: "captions.bubble.fill")
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
            let provider = matchingProviders.first
        {
            return identity(for: provider)
        }

        if isSavedOpenRouterModel(trimmedName) {
            return identity(for: .openRouter)
        }

        if matchingProviders.isEmpty,
            isOpenRouterModelIdentifier(trimmedName)
        {
            return identity(for: .openRouter)
        }

        if matchingProviders.isEmpty,
            let provider = inferredEnhancementProvider(from: trimmedName)
        {
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

    private static func isSavedOpenRouterModel(_ modelName: String) -> Bool {
        guard let models = UserDefaults.standard.array(forKey: "openRouterModels") as? [String] else {
            return false
        }

        return models.contains { namesMatch($0, modelName) }
    }

    private static func isOpenRouterModelIdentifier(_ modelName: String) -> Bool {
        let components = modelName.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && components.allSatisfy {
                !String($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
