import SwiftUI
import AppKit
import LLMkit

// MARK: - Cloud Model Card View
struct CloudModelCardView: View {
    let model: CloudModel

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var isExpanded = false
    @State private var apiKey = ""

    init(model: CloudModel) {
        self.model = model
    }
    @State private var isVerifying = false
    @State private var verificationStatus: VerificationStatus = .none
    @State private var verificationError: String? = nil
    @State private var verificationErrorDetail: String? = nil
    
    enum VerificationStatus {
        case none, verifying, success, failure
    }
    
    private var isConfigured: Bool {
        return APIKeyManager.shared.hasAPIKey(forProvider: providerKey)
    }
    
    private var providerKey: String {
        CloudProviderRegistry.provider(for: model.provider)?.providerKey ?? model.provider.rawValue
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
        .background(AppMaterialCardBackground())
        .onAppear {
            loadSavedAPIKey()
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Provider
            Label(model.provider.rawValue, systemImage: "cloud")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            // Speed
            HStack(spacing: 3) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            // Accuracy
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
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
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            if isConfigured {
                modelStatusPill("Connected", systemImage: "checkmark.circle")
            } else {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Configure")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "gear.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AppTheme.Accent.primary)
                            .shadow(color: AppTheme.Accent.shadow, radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            if isConfigured {
                Menu {
                    Button {
                        clearAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key Configuration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            HStack(spacing: 8) {
                SecureField("Enter your \(model.provider.rawValue) API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isVerifying)
                    .onChange(of: apiKey) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        if verificationStatus == .failure {
                            verificationStatus = .none
                        }
                        verificationError = nil
                        verificationErrorDetail = nil
                    }
                
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
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(verificationStatus == .success ? AppTheme.Status.positive : AppTheme.Accent.primary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isVerifying)
            }
            
            if verificationStatus == .failure {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verificationError ?? "Could not verify this API key. Check the key and try again.")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Status.error)

                    if let verificationErrorDetail {
                        Text(verificationErrorDetail)
                            .font(.caption)
                            .foregroundColor(AppTheme.Status.error.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if verificationStatus == .success {
                Text("Verified")
                    .font(.caption)
                    .foregroundColor(AppTheme.Status.positive)
            }
        }
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
        verificationError = nil
        verificationErrorDetail = nil
        let key = apiKey

        guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider) else {
            isVerifying = false
            verificationStatus = .failure
            verificationError = "Could not verify this API key. Check the key and try again."
            verificationErrorDetail = "Unsupported provider"
            return
        }

        Task {
            let result = await cloudProvider.verifyAPIKey(key)

            await MainActor.run {
                isVerifying = false
                if result.isValid {
                    verificationStatus = .success
                    verificationError = nil
                    verificationErrorDetail = nil
                    APIKeyManager.shared.saveAPIKey(key, forProvider: providerKey)
                    transcriptionModelManager.refreshAllAvailableModels()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = false
                    }
                } else {
                    verificationStatus = .failure
                    verificationError = "Could not verify this API key. Check the key and try again."
                    verificationErrorDetail = result.errorMessage
                }
            }
        }
    }
    
    private func clearAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: providerKey)
        apiKey = ""
        verificationStatus = .none
        verificationError = nil
        verificationErrorDetail = nil

        transcriptionModelManager.refreshAllAvailableModels()

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }
}
