import SwiftUI

struct CustomProviderManagementView: View {
    @ObservedObject var customModelManager: CustomCloudModelManager
    @ObservedObject var customAIProviderManager: CustomAIProviderManager

    let onAddTranscriptionModel: () -> Void
    let onEditTranscriptionModel: (CustomCloudModel) -> Void
    let onDeleteTranscriptionModel: (CustomCloudModel) -> Void
    let onAddEnhancementModel: () -> Void
    let onEditEnhancementModel: (CustomAIProviderConfig) -> Void
    let onDeleteEnhancementModel: (CustomAIProviderConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            customTranscriptionSection
            customEnhancementSection
        }
    }

    private var customTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Transcription Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                addHelp: "Add transcription model",
                onAdd: onAddTranscriptionModel
            )

            if customModelManager.customModels.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "waveform",
                    title: "No Custom Transcription Models"
                )
            } else {
                ForEach(customModelManager.customModels) { model in
                    CustomModelCardView(
                        model: model,
                        deleteAction: {
                            onDeleteTranscriptionModel(model)
                        },
                        editAction: onEditTranscriptionModel
                    )
                }
            }
        }
    }

    private var customEnhancementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Enhancement Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                addHelp: "Add enhancement model",
                onAdd: onAddEnhancementModel
            )

            if customAIProviderManager.providers.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "sparkles",
                    title: "No Custom Enhancement Models"
                )
            } else {
                ForEach(customAIProviderManager.providers) { provider in
                    CustomEnhancementModelRow(
                        provider: provider,
                        onEdit: {
                            onEditEnhancementModel(provider)
                        },
                        onDelete: {
                            onDeleteEnhancementModel(provider)
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        addHelp: LocalizedStringResource,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderSectionHeader(title: title, subtitle: subtitle)

            Spacer(minLength: 8)

            AddIconButton(helpText: addHelp, action: onAdd)
        }
    }

}

private struct CustomProviderEmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomEnhancementModelRow: View {
    let provider: CustomAIProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))

                if provider.modelName.isEmpty {
                    Text("No model configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(provider.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(14)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

struct CustomTranscriptionModelEditorPanel: View {
    let editingModel: CustomCloudModel?
    @ObservedObject var customModelManager: CustomCloudModelManager
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isMultilingual = true
    @State private var validationErrors: [String] = []
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?

    private var isEditing: Bool {
        editingModel != nil
    }

    private var canTestConnection: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetConnectionTest() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        connectionTest = .idle
    }

    private func runConnectionTest() {
        connectionTestTask?.cancel()
        connectionTest = .testing
        let endpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        connectionTestTask = Task {
            let result = await CustomModelConnectionTester.testTranscriptionEndpoint(
                endpoint: endpoint,
                apiKey: key,
                modelName: model
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connectionTest = ConnectionTestState(result: result)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader(title: isEditing ? "Edit Custom Transcription Model" : "Add Custom Transcription Model")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(
                                label: "Display Name", placeholder: String(localized: "My Custom Model"),
                                text: $displayName)
                            CustomModelTextField(
                                label: "API Endpoint", placeholder: "https://api.openai.com/v1/audio/transcriptions",
                                text: $apiEndpoint)
                            CustomModelTextField(
                                label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey,
                                isSecure: true)
                            CustomModelTextField(
                                label: "Model Name", placeholder: "gpt-4o-mini-transcribe", text: $modelName)
                            CustomModelToggleRow(title: "Multilingual Model", isOn: $isMultilingual)
                            ConnectionTestRow(
                                state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
                        }
                    }

                    ConnectionTestResultBox(state: connectionTest)

                    if !validationErrors.isEmpty {
                        CustomModelErrorBox(messages: validationErrors)
                    }
                }
                .padding(20)
            }

            editorFooter(
                primaryTitle: isSaving ? "Saving" : isEditing ? "Save Changes" : "Add Model",
                isPrimaryDisabled: !canSave || isSaving,
                primaryAction: saveModel
            )
        }
        .onAppear(perform: loadModel)
        .onChange(of: editingModel?.id) { _, _ in
            loadModel()
        }
        .onChange(of: apiEndpoint) { _, _ in resetConnectionTest() }
        .onChange(of: apiKey) { _, _ in resetConnectionTest() }
        .onChange(of: modelName) { _, _ in resetConnectionTest() }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadModel() {
        if let editingModel {
            displayName = editingModel.displayName
            apiEndpoint = editingModel.apiEndpoint
            apiKey = APIKeyManager.shared.getCustomModelAPIKey(forModelId: editingModel.id) ?? ""
            modelName = editingModel.modelName
            isMultilingual = editingModel.isMultilingualModel
        } else {
            displayName = ""
            apiEndpoint = "https://api.openai.com/v1/audio/transcriptions"
            apiKey = ""
            modelName = "gpt-4o-mini-transcribe"
            isMultilingual = true
        }

        validationErrors = []
        isSaving = false
        resetConnectionTest()
    }

    private func saveModel() {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedName = trimmedDisplayName.lowercased().replacingOccurrences(of: " ", with: "-")

        validationErrors = customModelManager.validateModelDetails(
            name: generatedName,
            displayName: trimmedDisplayName,
            apiEndpoint: trimmedEndpoint,
            modelName: trimmedModelName,
            excludingId: editingModel?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else { return }
        isSaving = true

        if let editingModel {
            let updatedModel = CustomCloudModel(
                id: editingModel.id,
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                isMultilingual: isMultilingual
            )

            guard customModelManager.updateCustomModel(updatedModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }
        } else {
            let customModel = CustomCloudModel(
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                isMultilingual: isMultilingual
            )

            guard customModelManager.addCustomModel(customModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }
        }

        isSaving = false
        onSave()
    }

    private func editorHeader(title: LocalizedStringKey) -> some View {
        CustomModelEditorHeader(title: title, onClose: onClose)
    }

    private func editorFooter(
        primaryTitle: LocalizedStringKey, isPrimaryDisabled: Bool, primaryAction: @escaping () -> Void
    ) -> some View {
        CustomModelEditorFooter(
            primaryTitle: primaryTitle,
            isPrimaryDisabled: isPrimaryDisabled,
            onCancel: onClose,
            onPrimary: primaryAction
        )
    }
}

struct CustomEnhancementModelEditorPanel: View {
    let editingProvider: CustomAIProviderConfig?
    @ObservedObject var manager: CustomAIProviderManager
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?

    private var isEditing: Bool {
        editingProvider != nil
    }

    private var canTestConnection: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetConnectionTest() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        connectionTest = .idle
    }

    private func runConnectionTest() {
        connectionTestTask?.cancel()
        connectionTest = .testing
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        connectionTestTask = Task {
            let result = await CustomModelConnectionTester.testEnhancementEndpoint(
                baseURL: url,
                apiKey: key,
                modelName: model
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connectionTest = ConnectionTestState(result: result)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomModelEditorHeader(
                title: isEditing ? "Edit Custom Enhancement Model" : "Add Custom Enhancement Model",
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(
                                label: "Display Name", placeholder: String(localized: "My Enhancement Model"),
                                text: $displayName)
                            CustomModelTextField(
                                label: "Base URL", placeholder: "https://api.openai.com/v1/chat/completions",
                                text: $baseURL)
                            CustomModelTextField(
                                label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey,
                                isSecure: true)
                            CustomModelTextField(label: "Model Name", placeholder: "gpt-5.5", text: $modelName)
                            ConnectionTestRow(
                                state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
                        }
                    }

                    ConnectionTestResultBox(state: connectionTest)

                    if let errorMessage {
                        CustomModelErrorBox(messages: [errorMessage])
                    }
                }
                .padding(20)
            }

            CustomModelEditorFooter(
                primaryTitle: primaryButtonTitle,
                isPrimaryDisabled: !canSave || isSaving,
                onCancel: onClose,
                onPrimary: saveProvider
            )
        }
        .onAppear(perform: loadProvider)
        .onChange(of: editingProvider?.id) { _, _ in
            loadProvider()
        }
        .onChange(of: baseURL) { _, _ in resetConnectionTest() }
        .onChange(of: apiKey) { _, _ in resetConnectionTest() }
        .onChange(of: modelName) { _, _ in resetConnectionTest() }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadProvider() {
        if let editingProvider {
            displayName = editingProvider.name
            baseURL = editingProvider.baseURL
            apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: editingProvider.id) ?? ""
            modelName = editingProvider.modelName
        } else {
            displayName = ""
            baseURL = "https://api.openai.com/v1/chat/completions"
            apiKey = ""
            modelName = "gpt-5.5"
        }

        errorMessage = nil
        isSaving = false
        resetConnectionTest()
    }

    private var primaryButtonTitle: LocalizedStringKey {
        if isSaving {
            return "Saving"
        }

        return isEditing ? "Save Changes" : "Add Model"
    }

    private func saveProvider() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        var validationErrors = manager.validateProvider(
            name: trimmedName,
            baseURL: trimmedURL,
            model: trimmedModelName,
            excluding: editingProvider?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: "\n")
            return
        }

        errorMessage = nil

        let provider = CustomAIProviderConfig(
            id: editingProvider?.id ?? UUID(),
            name: trimmedName,
            baseURL: trimmedURL,
            models: [trimmedModelName],
            selectedModel: trimmedModelName
        )

        if isEditing {
            isSaving = true
            let didSave = manager.updateProvider(provider, apiKey: trimmedKey)
            isSaving = false

            if didSave {
                onSave()
            } else {
                errorMessage = String(localized: "Failed to save custom enhancement model")
            }
            return
        }

        isSaving = true
        let didSave = manager.addProvider(provider, apiKey: trimmedKey)
        isSaving = false

        if didSave {
            onSave()
        } else {
            errorMessage = String(localized: "Failed to save API key securely")
        }
    }
}

private enum CustomModelEditorMetrics {
    static let labelWidth: CGFloat = 112
    static let fieldMaxWidth: CGFloat = 220
}

private struct CustomModelEditorSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(ProviderSurface(cornerRadius: 10))
        }
    }
}

private struct CustomModelTextField: View {
    let label: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField("", text: $text, prompt: Text(verbatim: placeholder))
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(message: String)

    init(result: ConnectionTestResult) {
        switch result {
        case .success:
            self = .success
        case .failure(let message):
            self = .failure(message: message)
        }
    }

    var isTesting: Bool {
        self == .testing
    }
}

private struct ConnectionTestRow: View {
    let state: ConnectionTestState
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Connection")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                    Text("Test")
                        .font(.system(size: 12))
                }
            }
            .disabled(isDisabled || state.isTesting)

            inlineStatus

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inlineStatus: some View {
        switch state {
        case .idle, .failure:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing…")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.Text.secondary)
        case .success:
            Label("Test successful", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Status.positive)
                .lineLimit(1)
        }
    }
}

private struct ConnectionTestResultBox: View {
    let state: ConnectionTestState

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .testing, .success:
            EmptyView()
        case .failure(let message):
            CustomModelErrorBox(messages: [message])
        }
    }
}

private struct CustomModelToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelErrorBox: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomModelEditorHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }
}

private struct CustomModelEditorFooter: View {
    let primaryTitle: LocalizedStringKey
    let isPrimaryDisabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)
        }
        .padding(20)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }
}

#if DEBUG
    private enum CustomModelsPreviewPanel {
        case transcription
        case enhancement
    }

    private struct CustomModelsSidePanelPreview: View {
        @State private var activePanel: CustomModelsPreviewPanel? = .transcription

        private var isPanelOpen: Binding<Bool> {
            Binding(
                get: { activePanel != nil },
                set: { if !$0 { activePanel = nil } }
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                AppScreenHeader(title: "Model Catalog") {
                    AppIconButton(systemName: "plus.circle.fill", help: "Add custom model") {
                        activePanel = .transcription
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        customSectionHeader(
                            title: "Custom Transcription Models",
                            subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                            action: { activePanel = .transcription }
                        )

                        CustomModelCardView(
                            model: Self.sampleTranscriptionModel,
                            deleteAction: {},
                            editAction: { _ in activePanel = .transcription }
                        )

                        customSectionHeader(
                            title: "Custom Enhancement Models",
                            subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                            action: { activePanel = .enhancement }
                        )

                        CustomEnhancementModelRow(
                            provider: Self.sampleEnhancementProvider,
                            onEdit: { activePanel = .enhancement },
                            onDelete: {}
                        )
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: 920, height: 640)
            .background(AppTheme.Surface.window)
            .sidePanel(isPresented: isPanelOpen) {
                panelContent
            }
        }

        @ViewBuilder
        private var panelContent: some View {
            switch activePanel {
            case .transcription:
                CustomTranscriptionModelEditorPanel(
                    editingModel: Self.sampleTranscriptionModel,
                    customModelManager: .shared,
                    onClose: { activePanel = nil },
                    onSave: { activePanel = nil }
                )
            case .enhancement:
                CustomEnhancementModelEditorPanel(
                    editingProvider: Self.sampleEnhancementProvider,
                    manager: .shared,
                    onClose: { activePanel = nil },
                    onSave: { activePanel = nil }
                )
            case nil:
                EmptyView()
            }
        }

        private func customSectionHeader(
            title: LocalizedStringKey, subtitle: LocalizedStringKey, action: @escaping () -> Void
        ) -> some View {
            HStack(alignment: .top, spacing: 12) {
                ProviderSectionHeader(title: title, subtitle: subtitle)

                Spacer()

                AddIconButton(helpText: "Add model", action: action)
            }
        }

        private static let sampleTranscriptionModel = CustomCloudModel(
            name: "acme-transcribe",
            displayName: "Acme Transcribe",
            description: "OpenAI-compatible transcription endpoint for previewing custom model cards.",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "acme-transcribe-large",
            isMultilingual: true
        )

        private static let sampleEnhancementProvider = CustomAIProviderConfig(
            name: "Acme Enhance",
            baseURL: "https://api.example.com/v1/chat/completions",
            models: ["acme-enhance-pro"],
            selectedModel: "acme-enhance-pro"
        )
    }

    #Preview("Custom AI Models - Side Panel") {
        CustomModelsSidePanelPreview()
    }
#endif
