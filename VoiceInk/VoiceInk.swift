import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import AppIntents
import FluidAudio

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool

    @StateObject private var engine: VoiceInkEngine
    @StateObject private var whisperModelManager: WhisperModelManager
    @StateObject private var fluidAudioModelManager: FluidAudioModelManager
    @StateObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var recorderUIManager: RecorderUIManager
    @StateObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = false
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @State private var showMenuBarIcon = true
    @State private var didShowAccessibilityReminder = false

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()
        OnboardingV2Migration.prepareIfNeeded()

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        // Keep existing model order stable; append new models after synced entities.
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            SessionMetric.self
        ])
        var initializationFailed = false
        let resolvedContainer: ModelContainer

        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            resolvedContainer = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            resolvedContainer = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("ModelContainer initialization failed")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            resolvedContainer = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                let alert = NSAlert()
                alert.messageText = "VoiceInk Could Not Start"
                alert.informativeText = "VoiceInk failed to initialize and must quit.\n\nTry restarting your Mac. If the problem persists, please contact support."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                exit(1)
            }()
        }

        container = resolvedContainer
        containerInitializationFailed = initializationFailed
        DictionaryService.removeExactDuplicateContent(context: resolvedContainer.mainContext, source: "launch")

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        aiService.refreshOllamaAvailabilityInBackground()

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: resolvedContainer.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)

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

        _whisperModelManager = StateObject(wrappedValue: whisperModelManager)
        _fluidAudioModelManager = StateObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = StateObject(wrappedValue: transcriptionModelManager)
        _recorderUIManager = StateObject(wrappedValue: recorderUIManager)
        _engine = StateObject(wrappedValue: engine)

        // 7. Create other services that depend on engine
        let recordingShortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        _recordingShortcutManager = StateObject(wrappedValue: recordingShortcutManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: resolvedContainer, engine: engine)

        let activeWindowService = ActiveWindowService.shared
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: resolvedContainer.mainContext
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        let migrationTask = SessionMetricMigrationService.shared.runIfNeeded(modelContainer: resolvedContainer)
        let mainContext = resolvedContainer.mainContext
        Task {
            await migrationTask?.value
            TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: mainContext)
        }
    }

    // MARK: - Container Creation Helpers

    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Create app-specific Application Support directory URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)

            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Define storage locations
            let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
            let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")
            let statsStoreURL = appSupportURL.appendingPathComponent("stats.store")

            // Transcript configuration
            let transcriptSchema = Schema([
                Transcription.self
            ])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                url: defaultStoreURL,
                cloudKitDatabase: .none
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            #if LOCAL_BUILD
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
            #else
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private("iCloud.com.prakashjoshipax.VoiceInk")
            #endif
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: dictionaryCloudKit
            )

            // Recorder session metrics configuration
            let statsSchema = Schema([SessionMetric.self])
            let statsConfig = ModelConfiguration(
                "stats",
                schema: statsSchema,
                url: statsStoreURL,
                cloudKitDatabase: .none
            )

            // Initialize container
            return try ModelContainer(
                for: schema,
                configurations: transcriptConfig, dictionaryConfig, statsConfig
            )
        } catch {
            logger.error("❌ Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Transcript configuration
            let transcriptSchema = Schema([
                Transcription.self
            ])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                isStoredInMemoryOnly: true
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                isStoredInMemoryOnly: true
            )

            let statsSchema = Schema([SessionMetric.self])
            let statsConfig = ModelConfiguration(
                "stats",
                schema: statsSchema,
                isStoredInMemoryOnly: true
            )

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig)
        } catch {
            logger.error("❌ Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboardingV2 {
                    ContentView()
                        .environmentObject(engine)
                        .environmentObject(whisperModelManager)
                        .environmentObject(fluidAudioModelManager)
                        .environmentObject(transcriptionModelManager)
                        .environmentObject(recorderUIManager)
                        .environmentObject(recordingShortcutManager)
                        .environmentObject(updaterViewModel)
                        .environmentObject(menuBarManager)
                        .environmentObject(aiService)
                        .environmentObject(enhancementService)
                        .modelContainer(container)
                        .onAppear {
                            // Check if container initialization failed
                            if containerInitializationFailed {
                                let alert = NSAlert()
                                alert.messageText = "Critical Storage Error"
                                alert.informativeText = "VoiceInk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                                alert.alertStyle = .critical
                                alert.addButton(withTitle: "Quit")
                                alert.runModal()

                                NSApplication.shared.terminate(nil)
                                return
                            }

                            if enableAnnouncements {
                                AnnouncementsService.shared.start()
                            }

                            showAccessibilityReminderIfNeeded()

                            // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                            if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                                audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                            }

                            // Process any pending open-file request now that the main ContentView is ready.
                            if let pendingURL = appDelegate.pendingOpenFileURL {
                                NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                                }
                                appDelegate.pendingOpenFileURL = nil
                            }
                        }
                        .background(WindowAccessor { window in
                            WindowManager.shared.configureWindow(window)
                        })
                        .onDisappear {
                            AnnouncementsService.shared.stop()
                            whisperModelManager.unloadModel()

                            // Stop the automatic audio cleanup process
                            audioCleanupManager.stopAutomaticCleanup()
                        }
                } else {
                    OnboardingView(hasCompletedOnboardingV2: $hasCompletedOnboardingV2)
                        .environmentObject(fluidAudioModelManager)
                        .environmentObject(aiService)
                        .environmentObject(enhancementService)
                        .frame(width: 950)
                        .frame(minHeight: 730)
                        .background(WindowAccessor { window in
                            WindowManager.shared.configureWindow(window)
                        })
                }
            }
            .confettiCelebrationPresenter()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 950, height: 730)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(recordingShortcutManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
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

    private func showAccessibilityReminderIfNeeded() {
        guard !didShowAccessibilityReminder else { return }
        didShowAccessibilityReminder = true

        guard !AXIsProcessTrusted() else { return }

        NotificationManager.shared.showNotification(
            title: "Accessibility permission is not provided",
            type: .warning,
            duration: 7.0,
            actionButton: ("Open Settings", Self.openAccessibilitySettings)
        )
    }

    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
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
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
