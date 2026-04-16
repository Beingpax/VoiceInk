import SwiftUI
import AppKit
import LLMkit

// MARK: - Cloud Model Card View
struct CloudModelCardView: View {
    let model: CloudModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var isExpanded = false
    @State private var apiKey = ""
    @State private var streamingEnabled = true
    @State private var isVerifying = false
    @State private var verificationStatus: VerificationStatus = .none
    @State private var verificationError: String? = nil
    
    enum VerificationStatus {
        case none, verifying, success, failure
    }
    
    private var isConfigured: Bool {
        return APIKeyManager.shared.hasAPIKey(forProvider: providerKey)
    }
    
    private var providerKey: String {
        switch model.provider {
        case .groq:
            return "Groq"
        case .elevenLabs:
            return "ElevenLabs"
        case .deepgram:
            return "Deepgram"
        case .mistral:
            return "Mistral"
        case .gemini:
            return "Gemini"
        case .soniox:
            return "Soniox"
        case .speechmatics:
            return "Speechmatics"
        default:
            return model.provider.rawValue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection
            }
            .padding(16)
            
            // Expandable configuration section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                configurationSection
                    .padding(16)
            }
        }
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .onAppear {
            loadSavedAPIKey()
            streamingEnabled = UserDefaults.standard.object(forKey: streamingDefaultsKey) as? Bool ?? true
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.labelColor))

            statusBadge

            if model.supportsStreaming && isConfigured {
                streamingModeBadge
            }

            Spacer()
        }
    }
    
    private var statusBadge: some View {
        Group {
            if isCurrent {
                Text("Default")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            } else if isConfigured {
                Text("Configured")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemGreen).opacity(0.2)))
                    .foregroundStyle(Color(.systemGreen))
            } else {
                Text("Setup Required")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemOrange).opacity(0.2)))
                    .foregroundStyle(Color(.systemOrange))
            }
        }
    }
    
    private var streamingModeBadge: some View {
        Button {
            streamingEnabled.toggle()
            UserDefaults.standard.set(streamingEnabled, forKey: streamingDefaultsKey)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: streamingEnabled ? "waveform" : "doc.text")
                    .font(.system(size: 8, weight: .semibold))
                Text(streamingEnabled ? "Live" : "Batch")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(streamingEnabled
                    ? Color.accentColor.opacity(0.15)
                    : Color(.secondaryLabelColor).opacity(0.15))
            )
            .foregroundStyle(streamingEnabled ? Color.accentColor : Color(.secondaryLabelColor))
        }
        .buttonStyle(.plain)
        .help(streamingEnabled ? "Live streaming enabled — click to switch to batch" : "Batch mode — click to enable live streaming")
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Provider
            Label(model.provider.rawValue, systemImage: "cloud")
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabelColor))
                .lineLimit(1)

            // Speed
            HStack(spacing: 3) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            // Accuracy
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundStyle(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabelColor))
            } else if isConfigured {
                Button(action: setDefaultAction) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Configure")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "gear")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                            .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            if isConfigured {
                Menu("More options", systemImage: "ellipsis.circle") {
                    Button {
                        clearAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 20)
            }
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key Configuration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.labelColor))
            
            HStack(spacing: 8) {
                SecureField("Enter your \(model.provider.rawValue) API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isVerifying)
                
                Button(action: verifyAPIKey) {
                    HStack(spacing: 4) {
                        if isVerifying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: verificationStatus == .success ? "checkmark" : "checkmark.shield")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(isVerifying ? "Verifying..." : "Verify")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(verificationStatus == .success ? Color(.systemGreen) : Color(.controlAccentColor))
                    )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isVerifying)
            }
            
            if verificationStatus == .failure {
                if let error = verificationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(.systemRed))
                } else {
                    Text("Verification failed")
                        .font(.caption)
                        .foregroundStyle(Color(.systemRed))
                }
            } else if verificationStatus == .success {
                Text("API key verified successfully!")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGreen))
            }
        }
    }
    
    private var streamingDefaultsKey: String {
        "streaming-enabled-\(model.name)"
    }

    private func loadSavedAPIKey() {
        if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: providerKey) {
            apiKey = savedKey
            verificationStatus = .success
        }
    }
    
    private func verifyAPIKey() {
        guard !apiKey.isEmpty else { return }

        isVerifying = true
        verificationStatus = .verifying
        let key = apiKey

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            switch model.provider {
            case .groq:
                result = await OpenAILLMClient.verifyAPIKey(
                    baseURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                    apiKey: key,
                    model: model.name
                )
            case .elevenLabs:
                result = await ElevenLabsClient.verifyAPIKey(key)
            case .deepgram:
                result = await DeepgramClient.verifyAPIKey(key)
            case .mistral:
                result = await MistralTranscriptionClient.verifyAPIKey(key)
            case .gemini:
                result = await GeminiTranscriptionClient.verifyAPIKey(key)
            case .soniox:
                result = await SonioxClient.verifyAPIKey(key)
            case .speechmatics:
                result = await SpeechmaticsClient.verifyAPIKey(key)
            default:
                await MainActor.run {
                    isVerifying = false
                    verificationStatus = .failure
                    verificationError = "Unsupported provider"
                }
                return
            }

            await MainActor.run {
                isVerifying = false
                if result.isValid {
                    verificationStatus = .success
                    verificationError = nil
                    APIKeyManager.shared.saveAPIKey(key, forProvider: providerKey)
                    transcriptionModelManager.refreshAllAvailableModels()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = false
                    }
                } else {
                    verificationStatus = .failure
                    verificationError = result.errorMessage
                }
            }
        }
    }
    
    private func clearAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: providerKey)
        apiKey = ""
        verificationStatus = .none
        verificationError = nil

        if isCurrent {
            transcriptionModelManager.clearCurrentTranscriptionModel()
        }

        transcriptionModelManager.refreshAllAvailableModels()

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }
}
