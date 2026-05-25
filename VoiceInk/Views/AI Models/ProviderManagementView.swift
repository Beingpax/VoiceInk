import SwiftUI
import AppKit

struct LocalEnhancementProviderManagementView: View {
    @EnvironmentObject private var aiService: AIService

    @State private var isOllamaExpanded = false
    @State private var isLocalCLIExpanded = false
    @State private var ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var selectedOllamaModel = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
    @State private var ollamaUserRefreshError: String?
    @State private var localCLICommandTemplate = ""
    @State private var localCLITimeoutSeconds = LocalCLIService.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false

    private var isLocalCLIConfigured: Bool {
        !localCLICommandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderSectionHeader(
                title: "Local & CLI Providers",
                subtitle: "Run enhancement with Ollama on this Mac, or send it to any CLI command."
            )
            .padding(.top, 8)

            VStack(spacing: 0) {
                LocalProviderDisclosureRow(
                    title: "Ollama",
                    subtitle: ollamaModelNames.isEmpty ? "Local server" : localModelCountLabel,
                    systemImage: "server.rack",
                    statusTitle: ollamaStatusTitle,
                    isExpanded: $isOllamaExpanded
                ) {
                    ollamaConfiguration
                }

                Divider()
                    .padding(.leading, 58)

                LocalProviderDisclosureRow(
                    title: "Local CLI",
                    subtitle: "Claude, Codex, scripts, or any command",
                    systemImage: "terminal",
                    statusTitle: isLocalCLIConfigured ? "Configured" : "Not configured",
                    isExpanded: $isLocalCLIExpanded
                ) {
                    localCLIConfiguration
                }
            }
            .background(GroupedCardBackground(cornerRadius: 11))
        }
        .onAppear {
            selectedOllamaModel = aiService.selectedModel(for: .ollama)
            syncLocalCLIStateFromService()
        }
    }

    private var ollamaModelNames: [String] {
        aiService.availableModels(for: .ollama)
    }

    private var localModelCountLabel: String {
        "\(ollamaModelNames.count) \(ollamaModelNames.count == 1 ? "model" : "models")"
    }

    private var ollamaStatusTitle: String {
        if aiService.isOllamaRefreshing {
            return "Checking"
        }

        if !aiService.connectedProviders.contains(.ollama) {
            return "Disconnected"
        }

        return ollamaModelNames.isEmpty ? "No models" : localModelCountLabel
    }

    private var ollamaActionTitle: String {
        aiService.connectedProviders.contains(.ollama) ? "Refresh" : "Connect"
    }

    private var ollamaConfiguration: some View {
        LocalProviderExpandedContent {
            LocalProviderFormRow(title: "Server") {
                HStack(spacing: 8) {
                    TextField("http://localhost:11434", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .disabled(aiService.isOllamaRefreshing)
                        .onChange(of: ollamaBaseURL) { _, _ in
                            ollamaUserRefreshError = nil
                        }

                    Button {
                        ollamaUserRefreshError = nil
                        aiService.updateOllamaBaseURL(ollamaBaseURL)
                        checkOllamaConnectionFromUserAction()
                    } label: {
                        if aiService.isOllamaRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(ollamaActionTitle)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(aiService.isOllamaRefreshing)
                }
            }

            if let ollamaUserRefreshError {
                Text(ollamaUserRefreshError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, LocalProviderMetrics.labelWidth + 12)
            }

            if !ollamaModelNames.isEmpty {
                Divider()
                    .padding(.leading, LocalProviderMetrics.labelWidth + 12)

                LocalProviderFormRow(title: "Model") {
                    Picker("Model", selection: $selectedOllamaModel) {
                        ForEach(ollamaModelNames, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                    .onChange(of: selectedOllamaModel) { _, newValue in
                        aiService.updateSelectedOllamaModel(newValue)
                        aiService.selectModel(newValue, for: .ollama)
                    }
                }
            }
        }
    }

    private var localCLIConfiguration: some View {
        LocalProviderExpandedContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Command")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        ForEach(LocalCLITemplate.allCases) { template in
                            Button(template.displayName) {
                                aiService.loadLocalCLITemplate(template)
                                syncLocalCLIStateFromService()
                            }
                        }
                    } label: {
                        Label("Template", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                TextEditor(text: $localCLICommandTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                    )
                    .onChange(of: localCLICommandTemplate) { _, newValue in
                        guard !isSyncingLocalCLIState else { return }
                        aiService.updateLocalCLICommandTemplate(newValue)
                    }
            }

            Divider()
                .padding(.leading, LocalProviderMetrics.labelWidth + 12)

            LocalProviderFormRow(title: "Timeout") {
                Picker("Timeout", selection: $localCLITimeoutSeconds) {
                    Text("15s").tag(15.0)
                    Text("30s").tag(30.0)
                    Text("45s").tag(45.0)
                    Text("60s").tag(60.0)
                    Text("90s").tag(90.0)
                    Text("120s").tag(120.0)
                    Text("180s").tag(180.0)
                    Text("300s").tag(300.0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110, alignment: .leading)
                .onChange(of: localCLITimeoutSeconds) { _, newValue in
                    aiService.updateLocalCLITimeoutSeconds(newValue)
                }
            }

            Text("Variables: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func checkOllamaConnectionFromUserAction() {
        Task { @MainActor in
            let result = await aiService.refreshOllamaAvailability()
            let models = result.models.map(\.name)

            ollamaUserRefreshError = result.errorMessage

            if !models.contains(selectedOllamaModel), let firstModel = models.first {
                selectedOllamaModel = firstModel
                aiService.selectModel(firstModel, for: .ollama)
            }
        }
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }
}

private enum LocalProviderMetrics {
    static let labelWidth: CGFloat = 72
}

private struct LocalProviderDisclosureRow<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let statusTitle: String
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        statusTitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.statusTitle = statusTitle
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.leading, 58)

                content()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }
}

private struct LocalProviderExpandedContent<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocalProviderFormRow<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: LocalProviderMetrics.labelWidth, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
        isConfigured ? .green : .secondary
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

struct ProviderDetailPanel: View {
    let descriptor: ProviderDescriptor
    let onClose: () -> Void

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var isRefreshingOpenRouterModels = false
    @State private var verificationMessage: String?
    @State private var verificationSucceeded = false
    @State private var isShowingRemoveAPIKeyConfirmation = false

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var iconName: String {
        if descriptor.hasTranscription && descriptor.hasEnhancement { return "rectangle.2.swap" }
        if descriptor.hasTranscription { return "captions.bubble.fill" }
        return "sparkles"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: loadSavedAPIKey)
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

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var apiKeySection: some View {
        ProviderConfigurationGroup(title: "Connection") {
            VStack(alignment: .leading, spacing: 8) {
                if isConfigured {
                    verifiedAPIKeyRow
                } else {
                    apiKeyInputRow
                }

                if let verificationMessage {
                    Text(verificationMessage)
                        .font(.caption)
                        .foregroundStyle(verificationSucceeded ? .green : .red)
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
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeAPIKey()
            }
        } message: {
            Text("This will remove your \(descriptor.displayName) API key. You can add it again later.")
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
                        Text(isVerifying ? "Verifying" : "Verify")
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

                        Text("Get \(descriptor.displayName) API Key")
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
                .help("Open \(descriptor.displayName) API key page")
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
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var neutralLinkButtonBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
            )
    }

    private var transcriptionModelsSection: some View {
        let models = descriptor.transcriptionModels

        return ProviderModelListSection(title: "Available Transcription Models") {
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
                Text("More transcription models available")
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

            ProviderModelListSection(title: "Available Enhancement Models") {
                if provider == .openRouter {
                    HStack(spacing: 12) {
                        Text(openRouterModelAvailabilityText(for: models.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(models.isEmpty ? .secondary : .primary)

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
                                Text(isRefreshingOpenRouterModels ? "Refreshing" : "Refresh")
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshingOpenRouterModels)
                        .opacity(isRefreshingOpenRouterModels ? 0.55 : 1)
                    }
                    .padding(.vertical, 8)
                } else if models.isEmpty {
                    Text("No models listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(models.prefix(8).enumerated()), id: \.offset) { index, model in
                        modelRow(
                            title: model,
                            subtitle: nil,
                            trailing: nil,
                            systemImage: "sparkles"
                        )

                        if index < min(models.count, 8) - 1 {
                            Divider()
                        }
                    }

                    if models.count > 8 {
                        Divider()
                        Text("More enhancement models available")
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
            return "No models loaded."
        }

        return "\(count) \(count == 1 ? "model" : "models") available"
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
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
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

        return "\(trimmedKey.prefix(4))\(String(repeating: "\u{2022}", count: max(4, trimmedKey.count - 8)))\(trimmedKey.suffix(4))"
    }

    private func loadSavedAPIKey() {
        verificationSucceeded = isConfigured
        apiKey = ""
    }

    private func verificationModel(for provider: AIProvider) -> String {
        let selectedModel = aiService.selectedModel(for: provider)
        let models = aiService.availableModels(for: provider)

        if models.contains(selectedModel) {
            return selectedModel
        }

        return models.first ?? selectedModel
    }

    private func verifyAndSaveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isVerifying = true
        verificationMessage = nil

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
                result = (false, "Provider is not supported")
            }

            await MainActor.run {
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
                    transcriptionModelManager.refreshAllAvailableModels()
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    verificationMessage = result.errorMessage ?? "Verification failed"
                }
            }
        }
    }

    private func removeAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: descriptor.providerKey)
        apiKey = ""
        verificationSucceeded = false
        verificationMessage = nil
        transcriptionModelManager.refreshAllAvailableModels()
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }

    private func refreshOpenRouterModels() {
        guard !isRefreshingOpenRouterModels else { return }
        isRefreshingOpenRouterModels = true

        Task {
            await aiService.fetchOpenRouterModels()
            await MainActor.run {
                isRefreshingOpenRouterModels = false
            }
        }
    }

}

private struct ProviderBrandIcon: View {
    let descriptor: ProviderDescriptor
    let fallbackSystemImage: String
    let isSelected: Bool
    let size: CGFloat
    let iconSize: CGFloat

    private var hasBrandAsset: Bool {
        descriptor.brandAssetName != nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(7, size * 0.25))
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: max(7, size * 0.25))
                        .stroke(borderColor, lineWidth: 1)
                )

            if let assetName = descriptor.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .padding(size * 0.24)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        if hasBrandAsset {
            return Color.white.opacity(isSelected ? 0.96 : 0.9)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.35)
        }
        return Color(NSColor.separatorColor).opacity(hasBrandAsset ? 0.45 : 0.2)
    }
}

struct ProviderSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ProviderConfigurationGroup<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }
}

struct ProviderModelListSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(ProviderSurface(cornerRadius: 10))
        }
    }
}

struct ProviderSurface: View {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        GroupedCardBackground(isSelected: isActive, cornerRadius: cornerRadius)
    }
}

private struct ProviderStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
