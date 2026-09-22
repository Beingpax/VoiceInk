import AppKit
import SwiftUI

struct ProviderDetailPanel: View {
    let descriptor: ProviderDescriptor
    let onClose: () -> Void

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var isRefreshingOpenRouterModels = false
    @State private var verificationMessage: String?
    @State private var verificationDetailMessage: String?
    @State private var verificationSucceeded = false
    @State private var isShowingRemoveAPIKeyConfirmation = false
    @State private var activeDescriptorID = ""

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var iconName: String {
        if descriptor.hasTranscription && descriptor.hasEnhancement { return "rectangle.2.swap" }
        if descriptor.hasTranscription { return "captions.bubble.fill" }
        return "sparkles"
    }

    var body: some View {
        QuickPanelScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    apiKeySection

                    if descriptor.hasTranscription {
                        transcriptionModelsSection
                    }

                    if descriptor.hasEnhancement {
                        enhancementModelsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
                .padding(.bottom, 20)
            }
        } header: {
            header
        }
        .onAppear(perform: loadSavedAPIKey)
        .onChange(of: descriptor.id) { _, _ in
            resetProviderState()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProviderBrandIcon(
                descriptor: descriptor,
                fallbackSystemImage: iconName,
                isSelected: false,
                size: 38,
                iconSize: 18
            )

            Text(descriptor.displayName)
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.headerHeight)
    }

    private var apiKeySection: some View {
        ProviderConfigurationGroup(title: "Connection") {
            VStack(alignment: .leading, spacing: 8) {
                if isConfigured {
                    verifiedAPIKeyRow
                } else {
                    apiKeyInputRow
                }

                verificationStatusMessage
            }
        }
    }

    @ViewBuilder
    private var verificationStatusMessage: some View {
        if let verificationMessage {
            VStack(alignment: .leading, spacing: 3) {
                Text(verificationMessage)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(verificationSucceeded ? AppTheme.Status.positive : AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)

                if let verificationDetailMessage, !verificationSucceeded {
                    Text(verificationDetailMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Status.error.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var verifiedAPIKeyRow: some View {
        HStack(spacing: 12) {
            providerDetailIcon("checkmark.seal.fill")

            VStack(alignment: .leading, spacing: 3) {
                Text("Key verified")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let obfuscatedKey {
                    Text(obfuscatedKey)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button {
                isShowingRemoveAPIKeyConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .help("Remove API key")
        }
        .padding(12)
        .background(ProviderSurface(cornerRadius: 8))
        .alert("Remove API Key?", isPresented: $isShowingRemoveAPIKeyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removeAPIKey()
            }
        } message: {
            Text(
                String(
                    format: String(localized: "This will remove your %@ API key. You can add it again later."),
                    descriptor.displayName))
        }
    }

    private var apiKeyInputRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerDetailIcon("key.fill")

                VStack(alignment: .leading, spacing: 3) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 8) {
                SecureField("Paste API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(isVerifying)
                    .onChange(of: apiKey) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        verificationMessage = nil
                        verificationDetailMessage = nil
                    }

                Button {
                    verifyAndSaveAPIKey()
                } label: {
                    HStack(spacing: 5) {
                        if isVerifying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal")
                        }
                        Text(isVerifying ? LocalizedStringKey("Verifying") : LocalizedStringKey("Verify"))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                .opacity(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying ? 0.55 : 1)
            }

            if let consoleURL = descriptor.apiConsoleURL {
                Link(destination: consoleURL) {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))

                        Text(String(format: String(localized: "Get %@ API Key"), descriptor.displayName))
                            .font(.system(size: 12, weight: .medium))

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(neutralLinkButtonBackground)
                }
                .buttonStyle(.plain)
                .help(String(format: String(localized: "Open %@ API key page"), descriptor.displayName))
            }
        }
        .padding(12)
        .background(ProviderSurface(cornerRadius: 8))
    }

    private func providerDetailIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.Surface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var neutralLinkButtonBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(AppTheme.Surface.control)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
            )
    }

    private var transcriptionModelsSection: some View {
        let models = descriptor.transcriptionModels

        return ProviderModelListSection(title: "Available Transcription Models") {
            if descriptor.cloudProvider?.modelProvider == .openRouter {
                openRouterCatalogStatus(modelCount: models.count)
            }

            ForEach(Array(models.prefix(8).enumerated()), id: \.element.id) { index, model in
                modelRow(
                    title: model.displayName,
                    subtitle: nil,
                    trailing: nil,
                    systemImage: "captions.bubble.fill"
                )

                if index < min(models.count, 8) - 1 {
                    Divider()
                }
            }

            if models.count > 8 {
                Divider()
                Text("+\(models.count - 8) more transcription models available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var enhancementModelsSection: some View {
        if let provider = descriptor.aiProvider {
            let models = aiService.availableModels(for: provider)
            let previewCount = provider == .openRouter ? 5 : 8

            ProviderModelListSection(title: "Available Enhancement Models") {
                if provider == .openRouter {
                    openRouterCatalogStatus(modelCount: models.count)
                }

                if provider != .openRouter && models.isEmpty {
                    Text("No models listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(models.prefix(previewCount).enumerated()), id: \.offset) { index, model in
                        modelRow(
                            title: model,
                            subtitle: nil,
                            trailing: nil,
                            systemImage: "sparkles"
                        )

                        if index < min(models.count, previewCount) - 1 {
                            Divider()
                        }
                    }

                    if models.count > previewCount {
                        Divider()
                        Text("+\(models.count - previewCount) more enhancement models available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }

            }
        }
    }

    private func openRouterModelAvailabilityText(for count: Int) -> String {
        if count == 0 {
            return String(localized: "No models loaded.")
        }

        return String(localized: "\(count) models available")
    }

    private func openRouterCatalogStatus(modelCount: Int) -> some View {
        HStack(spacing: 12) {
            Text(openRouterModelAvailabilityText(for: modelCount))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(modelCount == 0 ? .secondary : .primary)

            Spacer()

            Button {
                refreshOpenRouterModels()
            } label: {
                HStack(spacing: 5) {
                    if isRefreshingOpenRouterModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshingOpenRouterModels ? LocalizedStringKey("Refreshing") : LocalizedStringKey("Refresh"))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshingOpenRouterModels)
        }
        .padding(.vertical, 8)
    }

    private func modelRow(title: String, subtitle: String?, trailing: String?, systemImage: String) -> some View {
        HStack(spacing: 10) {
            modelTypeIcon(systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func modelTypeIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.Surface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var obfuscatedKey: String? {
        guard let savedKey = APIKeyManager.shared.getAPIKey(forProvider: descriptor.providerKey) else {
            return nil
        }

        let trimmedKey = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        if trimmedKey.count <= 8 {
            return String(repeating: "\u{2022}", count: trimmedKey.count)
        }

        return
            "\(trimmedKey.prefix(4))\(String(repeating: "\u{2022}", count: max(4, trimmedKey.count - 8)))\(trimmedKey.suffix(4))"
    }

    private func loadSavedAPIKey() {
        resetProviderState()
    }

    private func resetProviderState() {
        activeDescriptorID = descriptor.id
        verificationSucceeded = isConfigured
        apiKey = ""
        isVerifying = false
        isRefreshingOpenRouterModels = false
        verificationMessage = nil
        verificationDetailMessage = nil
        isShowingRemoveAPIKeyConfirmation = false
    }

    private func verificationModel(for provider: AIProvider) -> String {
        let selectedModel = aiService.selectedModel(for: provider)
        let models = aiService.availableModels(for: provider)

        if provider.supportsCustomModelID || models.contains(selectedModel) {
            return selectedModel
        }

        return models.first ?? selectedModel
    }

    private func verifyAndSaveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationDetailMessage = nil
        let providerID = descriptor.id

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            if let cloudProvider = descriptor.cloudProvider {
                result = await cloudProvider.verifyAPIKey(trimmedKey)
            } else if let provider = descriptor.aiProvider {
                result = await aiService.verifyAPIKey(
                    trimmedKey,
                    for: provider,
                    model: verificationModel(for: provider)
                )
            } else {
                result = (false, String(localized: "Provider is not supported"))
            }

            await MainActor.run {
                guard activeDescriptorID == providerID else { return }

                isVerifying = false
                verificationSucceeded = result.isValid

                if result.isValid {
                    APIKeyManager.shared.saveAPIKey(trimmedKey, forProvider: descriptor.providerKey)
                    if let provider = descriptor.aiProvider, aiService.selectedProvider == provider {
                        aiService.apiKey = trimmedKey
                        aiService.isAPIKeyValid = true
                    }
                    apiKey = ""
                    verificationMessage = nil
                    verificationDetailMessage = nil
                    transcriptionModelManager.refreshAllAvailableModels()
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    verificationMessage = String(
                        localized: "Could not verify this API key. Check the key and try again.")
                    verificationDetailMessage = result.errorMessage
                }
            }
        }
    }

    private func removeAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: descriptor.providerKey)
        apiKey = ""
        verificationSucceeded = false
        verificationMessage = nil
        verificationDetailMessage = nil
        transcriptionModelManager.refreshAllAvailableModels()
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }

    private func refreshOpenRouterModels() {
        guard !isRefreshingOpenRouterModels else { return }
        isRefreshingOpenRouterModels = true

        Task {
            await aiService.fetchOpenRouterModels()
            await transcriptionModelManager.refreshOpenRouterCatalog()
            await MainActor.run {
                isRefreshingOpenRouterModels = false
            }
        }
    }

}
