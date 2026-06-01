import SwiftUI
import AppKit

struct AIProviderVerificationCard: View {
    @ObservedObject var aiService: AIService

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationSucceeded = false
    @State private var isReplacingAPIKey = false

    private let onboardingProvider: AIProvider = .groq

    private var selectedProvider: AIProvider {
        onboardingProvider
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSelectedProviderConnected: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: selectedProvider.rawValue)
    }

    private var shouldShowAPIKeyEntry: Bool {
        !isSelectedProviderConnected || isReplacingAPIKey
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
        .onAppear {
            refreshVerificationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            refreshVerificationState()
        }
        .onChange(of: apiKey) { _, _ in
            if !apiKey.isEmpty {
                verificationSucceeded = false
                verificationMessage = nil
            }
        }
    }

    private var providerSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.Surface.controlActive)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Groq")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Connect Groq for setup. You can change providers later in Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Groq API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.82))

                Spacer()

                Button(action: openAPIKeyPage) {
                    HStack(spacing: 4) {
                        Text("Get API key")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )

            Text("VoiceInk sends a small verification request. The key is saved only after the test succeeds.")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
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

                    Text(isVerifying ? "Testing..." : "Test Connection")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(canVerify ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(canVerify ? Color.primary.opacity(0.78) : AppTheme.Surface.controlActive)
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
                Circle()
                    .fill(Color.primary.opacity(0.68))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedProvider.rawValue) connection verified.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.78))

                    Text("You can change providers later in Settings.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(.secondaryLabelColor))
                }
            }

            Spacer(minLength: 12)

            Button(action: startReplacingAPIKey) {
                Text("Replace Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.74))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppTheme.Surface.controlActive))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let verificationMessage {
            HStack(spacing: 7) {
                Circle()
                    .fill(verificationSucceeded ? Color.primary.opacity(0.68) : AppTheme.Status.error)
                    .frame(width: 7, height: 7)

                Text(verificationMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(verificationSucceeded ? .primary.opacity(0.74) : AppTheme.Status.error)
                    .lineLimit(2)
            }
        } else {
            Text("Test the connection to continue.")
                .font(.system(size: 12))
                .foregroundColor(Color(.secondaryLabelColor))
        }
    }

    private var canVerify: Bool {
        !trimmedAPIKey.isEmpty && !isVerifying
    }

    private var apiKeyPlaceholder: String {
        isReplacingAPIKey
            ? "Paste new Groq API key"
            : "Paste Groq API key"
    }

    private var apiKeyURL: URL? {
        URL(string: "https://console.groq.com/keys")
    }

    private func openAPIKeyPage() {
        guard let apiKeyURL else { return }
        NSWorkspace.shared.open(apiKeyURL)
    }

    private func refreshVerificationState() {
        if isReplacingAPIKey {
            verificationSucceeded = false
            verificationMessage = nil
            return
        }

        verificationSucceeded = isSelectedProviderConnected
        verificationMessage = verificationSucceeded ? "\(selectedProvider.rawValue) connection verified." : nil

        if verificationSucceeded {
            apiKey = ""
        }
    }

    private func startReplacingAPIKey() {
        apiKey = ""
        isReplacingAPIKey = true
        verificationSucceeded = false
        verificationMessage = nil
    }

    private func verifyAPIKey() {
        let key = trimmedAPIKey
        guard !key.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil
        verificationSucceeded = false

        Task {
            let provider = selectedProvider
            let result = await aiService.verifyAPIKey(key, for: provider, model: provider.defaultModel)

            await MainActor.run {
                isVerifying = false
                verificationSucceeded = result.isValid

                if result.isValid {
                    guard APIKeyManager.shared.saveAPIKey(key, forProvider: provider.rawValue) else {
                        verificationSucceeded = false
                        verificationMessage = "The key worked, but VoiceInk could not save it securely."
                        return
                    }

                    aiService.selectedProvider = provider
                    aiService.selectModel(provider.defaultModel, for: provider)
                    aiService.apiKey = key
                    aiService.isAPIKeyValid = true
                    apiKey = ""
                    isReplacingAPIKey = false
                    verificationMessage = "\(provider.rawValue) connection verified."
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    verificationMessage = result.errorMessage ?? "Could not verify this API key."
                }
            }
        }
    }
}
