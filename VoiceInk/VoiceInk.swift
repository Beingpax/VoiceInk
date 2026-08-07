import Combine
import AppIntents
import AppKit
import FluidAudio
import OSLog
import Sparkle
import SwiftData
import SwiftUI

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer

    @State private var engine: VoiceInkEngine
    @State private var whisperModelManager: WhisperModelManager
    @State private var fluidAudioModelManager: FluidAudioModelManager
    @State private var transcriptionModelManager: TranscriptionModelManager
    @State private var recorderUIManager: RecorderUIManager
    @State private var recordingShortcutManager: RecordingShortcutManager
    @State private var updaterViewModel: UpdaterViewModel
    @State private var menuBarManager: MenuBarManager
    private let mainWindowNavigation = MainWindowNavigation.shared
    @State private var aiService = AIService()
    @State private var enhancementService: AIEnhancementService
    private let activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = false
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @State private var showMenuBarIcon = true
    @State private var didShowLaunchReminders = false

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    private let prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()
        AppLanguagePreference.applyStored()
        AppAppearancePreference.applyStored()
        OnboardingV2Migration.prepareIfNeeded()

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        // Keep existing model order stable; append new models after synced entities.
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            SessionMetric.self,
        ])
        let resolvedContainer: ModelContainer

        // Attempt 1: Try persistent storage
        do {
            resolvedContainer = try Self.createPersistentContainer(schema: schema, logger: logger)
        } catch let persistentError {
            // Attempt 2: Try in-memory storage
            do {
                resolvedContainer = try Self.createInMemoryContainer(schema: schema, logger: logger)
                logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Storage Warning")
                    alert.informativeText = String(
                        localized:
                            "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions."
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: String(localized: "OK"))
                    alert.runModal()
                }
            } catch let memoryError {
                let persistentDetail = Self.fullErrorDescription(persistentError)
                let memoryDetail = Self.fullErrorDescription(memoryError)
                logger.critical(
                    "❌ All ModelContainer init attempts failed.\nPersistent:\n\(persistentDetail, privacy: .public)\nIn-memory:\n\(memoryDetail, privacy: .public)"
                )
                fatalError(
                    "VoiceInk failed to initialize storage.\nPersistent:\n\(persistentDetail)\nIn-memory:\n\(memoryDetail)"
                )
            }
        }

        container = resolvedContainer
        DictionaryService.removeExactDuplicateContent(context: resolvedContainer.mainContext, source: "launch")

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = State(initialValue: aiService)
        aiService.refreshOllamaAvailabilityInBackground()

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = State(initialValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: resolvedContainer.mainContext)
        _enhancementService = State(initialValue: enhancementService)

        // 1. Create modelsDirectory URL
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        let modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")

        // 2. Create model managers
        let whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        // 3. Create UI manager
        let recorderUIManager = RecorderUIManager()

        // 4. Create engine
        let engine = VoiceInkEngine(
            modelContext: resolvedContainer.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            enhancementService: enhancementService
        )

        // 5. Configure circular deps
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager

        // 6. Initialize model state
        // Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
        StreamingKeysMigration.run()
        whisperModelManager.createModelsDirectoryIfNeeded()
        whisperModelManager.loadAvailableModels()
        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()

        _whisperModelManager = State(initialValue: whisperModelManager)
        _fluidAudioModelManager = State(initialValue: fluidAudioModelManager)
        _transcriptionModelManager = State(initialValue: transcriptionModelManager)
        _recorderUIManager = State(initialValue: recorderUIManager)
        _engine = State(initialValue: engine)

        // 7. Create other services that depend on engine
        let recordingShortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        _recordingShortcutManager = State(initialValue: recordingShortcutManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = State(initialValue: menuBarManager)
        menuBarManager.configure(modelContainer: resolvedContainer, engine: engine)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: resolvedContainer.mainContext
        )
        self.prewarmService = prewarmService

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        let statsMigrationTask = SessionMetricMigrationService.shared.runStatsMigrationIfNeeded(
            modelContainer: resolvedContainer)
        let mainContext = resolvedContainer.mainContext
        Task { @MainActor in
            await statsMigrationTask?.value
            TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: mainContext)

            let tokenBackfillTask = SessionMetricMigrationService.shared.runEnhancementTokenBackfillIfNeeded(
                modelContainer: resolvedContainer)
            await tokenBackfillTask?.value
        }
    }

    // MARK: - Container Creation Helpers

    private static func fullErrorDescription(_ error: Error, depth: Int = 0) -> String {
        let ns = error as NSError
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        lines.append("\(indent)[\(ns.domain) \(ns.code)] \(ns.localizedDescription)")
        for (key, value) in ns.userInfo {
            let keyStr = "\(key)"
            if keyStr == NSUnderlyingErrorKey || keyStr == "NSDetailedErrors" { continue }
            lines.append("\(indent)  \(keyStr): \(value)")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            lines.append("\(indent)  Underlying:")
            lines.append(fullErrorDescription(underlying, depth: depth + 2))
        }
        if let details = ns.userInfo["NSDetailedErrors"] as? [Error] {
            lines.append("\(indent)  DetailedErrors (\(details.count)):")
            for (i, detail) in details.enumerated() {
                lines.append("\(indent)    [\(i)]:")
                lines.append(fullErrorDescription(detail, depth: depth + 3))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func createPersistentContainer(schema: Schema, logger: Logger) throws -> ModelContainer {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
        let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")
        let statsStoreURL = appSupportURL.appendingPathComponent("stats.store")

        let transcriptSchema = Schema([Transcription.self])
        let transcriptConfig = ModelConfiguration(
            "default",
            schema: transcriptSchema,
            url: defaultStoreURL,
            cloudKitDatabase: .none
        )

        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        #if LOCAL_BUILD
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
        #else
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private(
                "iCloud.com.prakashjoshipax.VoiceInk")
        #endif
        let dictionaryConfig = ModelConfiguration(
            "dictionary",
            schema: dictionarySchema,
            url: dictionaryStoreURL,
            cloudKitDatabase: dictionaryCloudKit
        )

        let statsSchema = Schema([SessionMetric.self])
        let statsConfig = ModelConfiguration(
            "stats",
            schema: statsSchema,
            url: statsStoreURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig)
        } catch {
            logger.error(
                "❌ Failed to create persistent ModelContainer:\n\(Self.fullErrorDescription(error), privacy: .public)")
            throw error
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) throws -> ModelContainer {
        let transcriptSchema = Schema([Transcription.self])
        let transcriptConfig = ModelConfiguration("default", schema: transcriptSchema, isStoredInMemoryOnly: true)

        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        let dictionaryConfig = ModelConfiguration("dictionary", schema: dictionarySchema, isStoredInMemoryOnly: true)

        let statsSchema = Schema([SessionMetric.self])
        let statsConfig = ModelConfiguration("stats", schema: statsSchema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig)
        } catch {
            logger.error(
                "❌ Failed to create in-memory ModelContainer:\n\(Self.fullErrorDescription(error), privacy: .public)")
            throw error
        }
    }

    var body: some Scene {
        Window("VoiceInk", id: AppWindowID.main) {
            Group {
                if hasCompletedOnboardingV2 {
                    ContentView()
                        .environment(engine)
                        .environment(whisperModelManager)
                        .environment(fluidAudioModelManager)
                        .environment(transcriptionModelManager)
                        .environment(recorderUIManager)
                        .environment(recordingShortcutManager)
                        .environment(updaterViewModel)
                        .environment(menuBarManager)
                        .environment(mainWindowNavigation)
                        .environment(aiService)
                        .environment(enhancementService)
                        .modelContainer(container)
                        .onAppear {
                            if enableAnnouncements {
                                AnnouncementsService.shared.start()
                            }

                            showLaunchRemindersIfNeeded()

                            // Run due audio-only cleanup and schedule future checks when transcript cleanup is not managing retention.
                            if !UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled)
                                && UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled)
                            {
                                Task {
                                    await audioCleanupManager.runAutomaticCleanupIfNeeded(
                                        modelContext: container.mainContext)
                                }
                                audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                            }

                            // Process any pending open-file request now that the main ContentView is ready.
                            if let pendingURL = appDelegate.pendingOpenFileURL {
                                NotificationCenter.default.post(
                                    name: .navigateToDestination, object: nil,
                                    userInfo: ["destination": "Transcribe Audio"])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(
                                        name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                                }
                                appDelegate.pendingOpenFileURL = nil
                            }
                        }
                        .background(
                            WindowAccessor { window in
                                WindowManager.shared.configureWindow(window)
                            }
                        )
                        .onDisappear {
                            AnnouncementsService.shared.stop()
                            whisperModelManager.unloadModel()

                            // Stop the automatic audio cleanup process
                            audioCleanupManager.stopAutomaticCleanup()
                        }
                } else {
                    OnboardingView(hasCompletedOnboardingV2: $hasCompletedOnboardingV2)
                        .environment(fluidAudioModelManager)
                        .environment(transcriptionModelManager)
                        .environment(aiService)
                        .environment(enhancementService)
                        .frame(minWidth: AppWindowLayout.minimumWidth, minHeight: AppWindowLayout.minimumHeight)
                        .background(
                            WindowAccessor { window in
                                WindowManager.shared.configureWindow(window)
                            })
                }
            }
            .confettiCelebrationPresenter()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }

            // Settings lives inside the main window rather than in a Settings scene, so the
            // standard shortcut has to be routed to the sidebar by hand.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    mainWindowNavigation.navigate(to: .settings)
                    WindowManager.shared.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(engine)
                .environment(whisperModelManager)
                .environment(fluidAudioModelManager)
                .environment(transcriptionModelManager)
                .environment(recorderUIManager)
                .environment(recordingShortcutManager)
                .environment(menuBarManager)
                .environment(mainWindowNavigation)
                .environment(updaterViewModel)
                .environment(aiService)
                .environment(enhancementService)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
                .background(MainWindowRequestBridge(menuBarManager: menuBarManager))
        }
        .menuBarExtraStyle(.menu)

        #if DEBUG
            WindowGroup("Debug") {
                Button("Toggle Menu Bar Only") {
                    menuBarManager.isMenuBarOnly.toggle()
                }
            }
        #endif
    }

    /// Only one notification fits on screen, so show at most one launch reminder.
    private func showLaunchRemindersIfNeeded() {
        guard !didShowLaunchReminders else { return }
        didShowLaunchReminders = true

        if !AXIsProcessTrusted() {
            NotificationManager.shared.showNotification(
                title: String(localized: "Accessibility permission is not provided"),
                type: .warning,
                duration: 7.0,
                actionButton: (String(localized: "Open Settings"), Self.openAccessibilitySettings)
            )
            return
        }

        if !ModeManager.shared.hasEnabledConfiguration {
            NotificationManager.shared.showNotification(
                title: String(localized: "No mode configured"),
                type: .warning,
                duration: 7.0,
                actionButton: (String(localized: "Manage Modes"), ModeSetupNavigator.openModesSettings)
            )
        }
    }

    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct MainWindowRequestBridge: View {
    @Environment(\.openWindow) private var openWindow
    let menuBarManager: MenuBarManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .showMainWindowRequested)) { _ in
                let existingWindow = WindowManager.shared.currentMainWindow()

                if existingWindow == nil {
                    menuBarManager.activateForPresentedWindow()
                    WindowManager.shared.prepareForUserRequestedMainWindow()
                    openWindow(id: AppWindowID.main)
                } else {
                    menuBarManager.activateForPresentedWindow()
                    openWindow(id: AppWindowID.main)
                    WindowManager.shared.showMainWindow()
                }
            }
    }
}

@MainActor
@Observable
class UpdaterViewModel {
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController
    @ObservationIgnored private var observers: Set<AnyCancellable> = []

    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        // Sparkle exposes these via KVO. `assign(to: &$x)` only works with @Published, so mirror
        // the values into observed storage by hand.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &observers)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] value in self?.automaticallyChecksForUpdates = value }
            .store(in: &observers)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }

    func checkForUpdates() {
        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }
}

struct CheckForUpdatesView: View {
    var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        notifyWindowIfNeeded(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        notifyWindowIfNeeded(for: nsView, context: context)
    }

    private func notifyWindowIfNeeded(for view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window,
                context.coordinator.window !== window
            {
                context.coordinator.window = window
                callback(window)
            }
        }
    }

    final class Coordinator {
        weak var window: NSWindow?
    }
}
