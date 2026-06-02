import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ModelFilter: String, CaseIterable, Identifiable {
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"
    var id: String { self.rawValue }
}

struct ModelManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @StateObject private var customAIProviderManager = CustomAIProviderManager.shared
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: ModelFilter = .local
    @State private var activePanel: ModelManagementPanel?

    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    private enum ModelManagementPanel {
        case settings
        case cloudProvider(ProviderDescriptor)
        case customTranscriptionModel(CustomCloudModel?)
        case customEnhancementModel(CustomAIProviderConfig?)
    }

    private var isSettingsPanelOpen: Bool {
        if case .settings? = activePanel { return true }
        return false
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    private var selectedCloudProviderID: String? {
        if case .cloudProvider(let descriptor)? = activePanel {
            return descriptor.id
        }
        return nil
    }

    private func closePanel() {
        activePanel = nil
    }

    private func toggleSettingsPanel() {
        activePanel = isSettingsPanelOpen ? nil : .settings
    }

    private func openCloudProviderPanel(_ descriptor: ProviderDescriptor) {
        activePanel = .cloudProvider(descriptor)
    }

    private func openCustomTranscriptionModelPanel(_ model: CustomCloudModel? = nil) {
        activePanel = .customTranscriptionModel(model)
    }

    private func openCustomEnhancementModelPanel(_ provider: CustomAIProviderConfig? = nil) {
        activePanel = .customEnhancementModel(provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if SystemArchitecture.isIntelMac {
                        intelMacWarningBanner
                    }

                    availableModelsSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .sidePanel(isPresented: .init(
            get: { isPanelOpen },
            set: { if !$0 { closePanel() } }
        )) {
            modelPanelContent
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private var headerSection: some View {
        AppScreenHeader(title: "Model Catalog") {
            settingsButton
        }
    }

    @ViewBuilder
    private var modelPanelContent: some View {
        switch activePanel {
        case .settings:
            settingsPanelContent
        case .cloudProvider(let descriptor):
            ProviderDetailPanel(descriptor: descriptor, onClose: closePanel)
                .environmentObject(aiService)
                .environmentObject(transcriptionModelManager)
                .id(descriptor.id)
        case .customTranscriptionModel(let model):
            CustomTranscriptionModelEditorPanel(
                editingModel: model,
                customModelManager: customModelManager,
                onClose: closePanel,
                onSave: {
                    transcriptionModelManager.refreshAllAvailableModels()
                    closePanel()
                }
            )
        case .customEnhancementModel(let provider):
            CustomEnhancementModelEditorPanel(
                editingProvider: provider,
                manager: customAIProviderManager,
                onClose: closePanel,
                onSave: closePanel
            )
        case nil:
            EmptyView()
        }
    }

    private var settingsPanelContent: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Model Settings", onClose: closePanel)

            ModelSettingsPanel()
        }
    }

    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelFilterPicker

            switch selectedFilter {
            case .local:
                localModelsSection
            case .cloud:
                CloudProviderManagementView(
                    selectedProviderID: selectedCloudProviderID,
                    onSelectProvider: openCloudProviderPanel
                )
                    .environmentObject(aiService)
                    .environmentObject(transcriptionModelManager)
            case .custom:
                CustomProviderManagementView(
                    customModelManager: customModelManager,
                    customAIProviderManager: customAIProviderManager,
                    onAddTranscriptionModel: {
                        openCustomTranscriptionModelPanel()
                    },
                    onEditTranscriptionModel: { model in
                        openCustomTranscriptionModelPanel(model)
                    },
                    onDeleteTranscriptionModel: { model in
                        confirmDeleteCustomModel(model)
                    },
                    onAddEnhancementModel: {
                        openCustomEnhancementModelPanel()
                    },
                    onEditEnhancementModel: { provider in
                        openCustomEnhancementModelPanel(provider)
                    },
                    onDeleteEnhancementModel: { provider in
                        confirmDeleteCustomEnhancementModel(provider)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelFilterPicker: some View {
        HStack(spacing: 12) {
            ForEach(ModelFilter.allCases, id: \.self) { filter in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedFilter = filter
                    }
                    activePanel = nil
                }) {
                    Text(filter.rawValue)
                        .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                        .foregroundColor(selectedFilter == filter ? .primary : .primary.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            AppMaterialCardBackground(isSelected: selectedFilter == filter, cornerRadius: 22)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.bottom, 8)
    }

    private var settingsButton: some View {
        AppIconButton(
            systemName: "gearshape.fill",
            help: "Model Settings"
        ) {
            toggleSettingsPanel()
        }
    }

    private var localModelsSection: some View {
        VStack(spacing: 12) {
            ForEach(localModels, id: \.id) { model in
                let isWarming = (model as? WhisperModel).map { whisperModel in
                    warmupCoordinator.isWarming(modelNamed: whisperModel.name)
                } ?? false

                ModelCardView(
                    model: model,
                    fluidAudioModelManager: fluidAudioModelManager,
                    isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
                    downloadProgress: whisperModelManager.downloadProgress,
                    modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
                    isWarming: isWarming,
                    deleteAction: {
                        confirmDeleteLocalModel(model)
                    },
                    downloadAction: {
                        if let whisperModel = model as? WhisperModel {
                            Task { await whisperModelManager.downloadModel(whisperModel) }
                        }
                    }
                )
            }

            importLocalModelButton

            LocalEnhancementProviderManagementView()
                .environmentObject(aiService)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importLocalModelButton: some View {
        HStack(spacing: 8) {
            Button(action: { presentImportPanel() }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Local Model…")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(AppMaterialCardBackground(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            InfoTip(
                "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file.",
                learnMoreURL: "https://tryvoiceink.com/docs/custom-local-whisper-models"
            )
            .help("Read more about custom local models")
        }
    }

    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Status.warningStrong)

            Text("Local models don't work reliably on Intel Macs")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text("Use Cloud")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AppTheme.Status.warningStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.Status.warningStrong.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Status.warningStrong.opacity(0.08))
        .cornerRadius(8)
    }

    private var localModels: [any TranscriptionModel] {
        transcriptionModelManager.allAvailableModels.filter {
            ($0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio)
                && transcriptionModelManager.isAvailableOnCurrentOS($0)
        }
    }

    private func confirmDeleteLocalModel(_ model: any TranscriptionModel) {
        guard let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) else {
            return
        }

        alertTitle = "Delete Model"
        alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
        deleteActionClosure = {
            Task {
                await whisperModelManager.deleteModel(downloadedModel)
            }
        }
        isShowingDeleteAlert = true
    }

    private func confirmDeleteCustomModel(_ model: CustomCloudModel) {
        alertTitle = "Delete Custom Model"
        alertMessage = "Are you sure you want to delete the custom model '\(model.displayName)'?"
        deleteActionClosure = {
            customModelManager.removeCustomModel(withId: model.id)
            transcriptionModelManager.refreshAllAvailableModels()
        }
        isShowingDeleteAlert = true
    }

    private func confirmDeleteCustomEnhancementModel(_ provider: CustomAIProviderConfig) {
        alertTitle = "Delete Custom Enhancement Model"
        alertMessage = "Are you sure you want to delete the custom enhancement model '\(provider.name)'?"
        deleteActionClosure = {
            customAIProviderManager.deleteProvider(provider)
        }
        isShowingDeleteAlert = true
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = "Select a Whisper ggml .bin model"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }
}
