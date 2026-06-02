import SwiftUI
import AppKit

struct AIProviderVerificationCard: View {
    @ObservedObject var aiService: AIService

    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider
    let onVerificationChanged: () -> Void

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationDetailMessage: String?
    @State private var verificationSucceeded = false
    @State private var isSwitchingProvider = false

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSelectedProviderConnected: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: selectedProvider.rawValue)
    }

    private var shouldShowAPIKeyEntry: Bool {
        !isSelectedProviderConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerSummary

            if shouldShowAPIKeyEntry {
                apiKeyField
                verificationFooter
            } else {
                verifiedProviderSummary
            }
        }
        .padding(16)
        .background(AppMaterialCardBackground(cornerRadius: 10))
        .onAppear { refreshVerificationState() }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            refreshVerificationState()
        }
        .onChange(of: selectedProvider) { _, _ in
            handleProviderChange()
        }
        .onChange(of: apiKey) { _, _ in
            guard !apiKey.isEmpty else { return }
            verificationSucceeded = false
            verificationMessage = nil
            verificationDetailMessage = nil
        }
    }

    private var providerSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderBrandIcon(
                descriptor: providerDescriptor(for: selectedProvider),
                fallbackSystemImage: "sparkles",
                isSelected: true,
                size: 28,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedProvider.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
            }

            Spacer(minLength: 0)

            if providerOptions.count > 1 {
                Button {
                    isSwitchingProvider.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("Switch AI provider")
                        Image(systemName: isSwitchingProvider ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Text.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppTheme.Surface.controlActive))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isSwitchingProvider, arrowEdge: .bottom) {
                    AIProviderSelectionCard(
                        providerOptions: providerOptions,
                        selectedProvider: $selectedProvider
                    )
                    .frame(width: 430)
                    .padding(10)
                }
            }
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("\(selectedProvider.rawValue) API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)

                Spacer()

                if let apiKeyURL {
                    Button {
                        NSWorkspace.shared.open(apiKeyURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Get API key")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.Text.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.Surface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                )
        }
    }

    private var verificationFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            statusLine

            Spacer(minLength: 12)

            Button(action: verifyAPIKey) {
                HStack(spacing: 6) {
                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(isVerifying ? "Testing..." : "Test connection")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(canVerify ? AppTheme.Action.primaryForeground : AppTheme.Action.disabledForeground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(canVerify ? AppTheme.Action.primaryFill : AppTheme.Action.disabledFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canVerify)
        }
        .padding(.top, 2)
    }

    private var verifiedProviderSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Status.positive)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection verified.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let verificationMessage {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: verificationSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(verificationSucceeded ? AppTheme.Status.positive : AppTheme.Status.error)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verificationMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(verificationSucceeded ? AppTheme.Text.secondary : AppTheme.Status.error)
                        .fixedSize(horizontal: false, vertical: true)

                    if let verificationDetailMessage, !verificationSucceeded {
                        Text(verificationDetailMessage)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Status.error.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            Text("Test the connection to continue.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Text.secondary)
        }
    }

    private var canVerify: Bool {
        !trimmedAPIKey.isEmpty && !isVerifying
    }

    private var apiKeyPlaceholder: String {
        "Paste \(selectedProvider.rawValue) API key"
    }

    private var apiKeyURL: URL? {
        selectedProvider.apiKeyURL
    }

    private func refreshVerificationState() {
        verificationSucceeded = isSelectedProviderConnected
        verificationMessage = verificationSucceeded ? "\(selectedProvider.rawValue) connection verified." : nil
        verificationDetailMessage = nil

        if verificationSucceeded {
            apiKey = ""
        }
    }

    private func handleProviderChange() {
        apiKey = ""
        isVerifying = false
        isSwitchingProvider = false
        refreshVerificationState()
        onVerificationChanged()
    }

    private func verifyAPIKey() {
        let key = trimmedAPIKey
        guard !key.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationDetailMessage = nil
        verificationSucceeded = false

        Task {
            let provider = selectedProvider
            let modelName = provider.defaultModel
            let result = await aiService.verifyAPIKey(key, for: provider, model: modelName)

            await MainActor.run {
                isVerifying = false

                guard selectedProvider == provider else {
                    refreshVerificationState()
                    onVerificationChanged()
                    return
                }

                verificationSucceeded = result.isValid

                if result.isValid {
                    guard APIKeyManager.shared.saveAPIKey(key, forProvider: provider.rawValue) else {
                        verificationSucceeded = false
                        verificationMessage = "The key worked, but VoiceInk could not save it securely."
                        verificationDetailMessage = nil
                        onVerificationChanged()
                        return
                    }

                    aiService.selectedProvider = provider
                    aiService.selectModel(modelName, for: provider)
                    aiService.apiKey = key
                    aiService.isAPIKeyValid = true
                    apiKey = ""
                    verificationMessage = "\(provider.rawValue) connection verified."
                    verificationDetailMessage = nil
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    verificationMessage = "Could not verify this API key. Check the key and try again."
                    verificationDetailMessage = result.errorMessage
                }

                onVerificationChanged()
            }
        }
    }
}

private struct AIProviderSelectionCard: View {
    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(providerOptions, id: \.self) { provider in
                    ProviderChoiceButton(
                        provider: provider,
                        isSelected: selectedProvider == provider,
                        action: {
                            selectedProvider = provider
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(ProviderSurface(cornerRadius: 12))
    }
}

private struct ProviderChoiceButton: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ProviderBrandIcon(
                    descriptor: providerDescriptor(for: provider),
                    fallbackSystemImage: "sparkles",
                    isSelected: isSelected,
                    size: 28,
                    iconSize: 15
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)
                        .lineLimit(1)

                    if provider == .groq {
                        RecommendedProviderPill()
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Text.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .background(ProviderSurface(isActive: isSelected, cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(provider.rawValue)
    }

}

private struct RecommendedProviderPill: View {
    var body: some View {
        Text("Recommended")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(AppTheme.Text.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.Surface.control.opacity(0.55)))
            .overlay(
                Capsule()
                    .stroke(AppTheme.Border.control.opacity(0.28), lineWidth: 1)
            )
    }
}

fileprivate func providerDescriptor(for provider: AIProvider) -> ProviderDescriptor {
    ProviderDescriptor(
        displayName: provider.rawValue,
        providerKey: provider.rawValue,
        aiProvider: provider,
        cloudProvider: nil
    )
}

fileprivate extension AIProvider {
    var apiKeyURL: URL? {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys/")
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/platform")
        default:
            return nil
        }
    }
}
