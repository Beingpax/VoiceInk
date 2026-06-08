import Combine
import Foundation

struct ModeFormWarmupSnapshot {
    let connectedAIProviders: [AIProvider]
    let aiModelsByProvider: [AIProvider: [String]]
    let selectedAIModelsByProvider: [AIProvider: String]
    let usableTranscriptionModels: [any TranscriptionModel]
    let allTranscriptionModels: [any TranscriptionModel]
    let prompts: [CustomPrompt]

    static let empty = ModeFormWarmupSnapshot(
        connectedAIProviders: [],
        aiModelsByProvider: [:],
        selectedAIModelsByProvider: [:],
        usableTranscriptionModels: [],
        allTranscriptionModels: [],
        prompts: []
    )

    @MainActor
    init(
        aiService: AIService,
        enhancementService: AIEnhancementService,
        transcriptionModelManager: TranscriptionModelManager
    ) {
        let providers = aiService.connectedProviders
        var modelsByProvider: [AIProvider: [String]] = [:]
        var selectedModelsByProvider: [AIProvider: String] = [:]

        for provider in providers {
            modelsByProvider[provider] = aiService.availableModels(for: provider)
            selectedModelsByProvider[provider] = aiService.selectedModel(for: provider)
        }

        connectedAIProviders = providers
        aiModelsByProvider = modelsByProvider
        selectedAIModelsByProvider = selectedModelsByProvider
        usableTranscriptionModels = transcriptionModelManager.usableModels
        allTranscriptionModels = transcriptionModelManager.allAvailableModels
        prompts = enhancementService.allPrompts
    }

    private init(
        connectedAIProviders: [AIProvider],
        aiModelsByProvider: [AIProvider: [String]],
        selectedAIModelsByProvider: [AIProvider: String],
        usableTranscriptionModels: [any TranscriptionModel],
        allTranscriptionModels: [any TranscriptionModel],
        prompts: [CustomPrompt]
    ) {
        self.connectedAIProviders = connectedAIProviders
        self.aiModelsByProvider = aiModelsByProvider
        self.selectedAIModelsByProvider = selectedAIModelsByProvider
        self.usableTranscriptionModels = usableTranscriptionModels
        self.allTranscriptionModels = allTranscriptionModels
        self.prompts = prompts
    }

    var firstPromptId: UUID? {
        prompts.first?.id
    }

    func availableModels(for provider: AIProvider) -> [String] {
        aiModelsByProvider[provider] ?? []
    }

    func selectedModel(for provider: AIProvider) -> String {
        selectedAIModelsByProvider[provider] ?? provider.defaultModel
    }

    func transcriptionModel(named name: String?) -> (any TranscriptionModel)? {
        guard let name else { return nil }
        return allTranscriptionModels.first { $0.name == name }
    }

    func hasUsableTranscriptionModel(named name: String) -> Bool {
        usableTranscriptionModels.contains { $0.name == name }
    }
}

@MainActor
final class ModeFormWarmupStore: ObservableObject {
    static let shared = ModeFormWarmupStore()

    @Published private(set) var snapshot = ModeFormWarmupSnapshot.empty
    @Published private(set) var installedApps: [InstalledAppInfo] = []
    @Published private(set) var isLoadingInstalledApps = false

    private weak var aiService: AIService?
    private weak var enhancementService: AIEnhancementService?
    private weak var transcriptionModelManager: TranscriptionModelManager?

    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var pendingSnapshotRefresh: DispatchWorkItem?
    private var hasSnapshot = false

    private init() {}

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        pendingSnapshotRefresh?.cancel()
    }

    func configure(
        aiService: AIService,
        enhancementService: AIEnhancementService,
        transcriptionModelManager: TranscriptionModelManager
    ) {
        let dependenciesChanged = self.aiService !== aiService ||
            self.enhancementService !== enhancementService ||
            self.transcriptionModelManager !== transcriptionModelManager

        self.aiService = aiService
        self.enhancementService = enhancementService
        self.transcriptionModelManager = transcriptionModelManager

        if dependenciesChanged {
            installChangeObservers()
        }

        if dependenciesChanged || !hasSnapshot {
            refreshSnapshot()
        }
        loadInstalledAppsIfNeeded()
    }

    func refreshSnapshot() {
        guard let aiService,
              let enhancementService,
              let transcriptionModelManager else { return }

        snapshot = ModeFormWarmupSnapshot(
            aiService: aiService,
            enhancementService: enhancementService,
            transcriptionModelManager: transcriptionModelManager
        )
        hasSnapshot = true
    }

    func scheduleSnapshotRefresh() {
        pendingSnapshotRefresh?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshSnapshot()
            }
        }

        pendingSnapshotRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func loadInstalledAppsIfNeeded() {
        guard installedApps.isEmpty else { return }
        refreshInstalledApps()
    }

    func refreshInstalledApps() {
        guard !isLoadingInstalledApps else { return }

        isLoadingInstalledApps = true

        DispatchQueue.global(qos: .utility).async {
            let apps = InstalledApps.load()

            Task { @MainActor in
                self.installedApps = apps
                self.isLoadingInstalledApps = false
            }
        }
    }

    private func installChangeObservers() {
        cancellables.removeAll()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()

        aiService?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRefresh()
                }
            }
            .store(in: &cancellables)

        enhancementService?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRefresh()
                }
            }
            .store(in: &cancellables)

        transcriptionModelManager?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRefresh()
                }
            }
            .store(in: &cancellables)

        let notificationNames: [Notification.Name] = [
            .AppSettingsDidChange,
            .aiProviderKeyChanged
        ]

        notificationObservers = notificationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRefresh()
                }
            }
        }
    }
}
