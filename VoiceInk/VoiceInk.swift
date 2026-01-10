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
    
    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @State private var showMenuBarIcon = true
    
    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared
    
    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared
    
    // MetricKit manager for production performance monitoring
    @available(macOS 12.0, *)
    private var metricsManager: MetricsManager { MetricsManager.shared }
    
    init() {
        // Migrate API keys from UserDefaults to Keychain (runs once on first launch after update)
        APIKeyMigrationService.migrateAPIKeysIfNeeded()
        
        if !AppSettings.contains(key: AppSettings.Keys.powerModeUIFlag) {
            let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
            AppSettings.General.powerModeUIFlag = hasEnabledPowerModes
        }

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        let schema = Schema([Transcription.self])
        var initializationFailed = false
        
        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            container = persistentContainer
            
            #if DEBUG
            // Print SwiftData storage location in debug builds only
            if let url = persistentContainer.mainContext.container.configurations.first?.url {
                print("💾 SwiftData storage location: \(url.path)")
            }
            #endif
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            container = memoryContainer
            
            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")
            
            // Show alert to user about storage issue
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // Attempt 3: Try ultra-minimal default container
        else if let minimalContainer = Self.createMinimalContainer(schema: schema, logger: logger) {
            container = minimalContainer
            logger.warning("Using minimal emergency container")
        }
        // All attempts failed: Create disabled container and mark for termination
        else {
            logger.critical("All ModelContainer initialization attempts failed")
            initializationFailed = true
            
            // Create a dummy container to satisfy Swift's initialization requirements
            // App will show error and terminate in onAppear
            container = Self.createDummyContainer(schema: schema)
        }
        
        containerInitializationFailed = initializationFailed
        
        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        
        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)
        
        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)
        if !(AppSettings.General.enableAIEnhancementFeatures ?? false) {
            enhancementService.isEnhancementEnabled = false
        }
        
        let whisperState = WhisperState(modelContext: container.mainContext, enhancementService: enhancementService)
        _whisperState = StateObject(wrappedValue: whisperState)
        
        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)
        
        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        appDelegate.menuBarManager = menuBarManager
        
        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        activeWindowService.configureWhisperState(whisperState)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)
        
        // Ensure no lingering recording state from previous runs
        Task {
            await whisperState.resetOnLaunch()
        }
        
        AppShortcuts.updateAppShortcutParameters()
    }
    
    // MARK: - Container Creation Helpers
    
    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Use bundle identifier for app-specific storage directory
            let bundleID = Bundle.main.bundleIdentifier ?? "com.tmm22.VoiceLinkCommunity"
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(bundleID, isDirectory: true)
            
            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            
            // Configure SwiftData to use the conventional location
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            logger.error("Failed to create persistent ModelContainer: \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Failed to create in-memory ModelContainer: \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func createMinimalContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Try default initializer without custom configuration
            return try ModelContainer(for: schema)
        } catch {
            logger.error("Failed to create minimal ModelContainer: \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func createDummyContainer(schema: Schema) -> ModelContainer {
        // Create an absolute minimal container for initialization
        // This uses in-memory storage and will never actually be used
        // as the app will show an error and terminate in onAppear
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        // Note: In-memory containers should always succeed unless SwiftData itself is unavailable
        // (which would indicate a serious system-level issue). We use preconditionFailure here
        // rather than fatalError because:
        // 1. This code is only reached after 3 prior initialization attempts have failed
        // 2. An in-memory container failing indicates SwiftData is completely unavailable
        // 3. Swift requires non-optional container property to be initialized
        // 4. The app will immediately terminate in onAppear when containerInitializationFailed is checked
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // This indicates a system-level SwiftData failure - app cannot function
            preconditionFailure("Unable to create even a dummy ModelContainer. SwiftData is unavailable: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(whisperState)
                    .environmentObject(hotkeyManager)
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
                        
                        updaterViewModel.silentlyCheckForUpdates()
                        if enableAnnouncements {
                            AnnouncementsService.shared.start()
                        }
                        
                        // Start the transcription auto-cleanup service (handles immediate and scheduled transcript deletion)
                        transcriptionAutoCleanupService.startMonitoring(modelContext: container.mainContext)
                        
                        // Clean up expired trash items (items deleted more than 30 days ago)
                        Task {
                            await TrashCleanupService.shared.cleanupExpiredTrashItems(modelContext: container.mainContext)
                        }
                        
                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !AppSettings.Cleanup.isTranscriptionCleanupEnabled {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }
                        
                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                        
                        // Register MetricKit for production performance monitoring
                        if #available(macOS 12.0, *) {
                            metricsManager.register()
                        }
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        AnnouncementsService.shared.stop()
                        whisperState.unloadModel()
                        
                        // Stop the transcription auto-cleanup service
                        transcriptionAutoCleanupService.stopMonitoring()
                        
                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                        
                        // Unregister MetricKit
                        if #available(macOS 12.0, *) {
                            metricsManager.unregister()
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(hotkeyManager)
                    .environmentObject(whisperState)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .frame(minWidth: 880, minHeight: 780)
                    .background(WindowAccessor { window in
                        if window.identifier == nil || window.identifier != NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.onboardingWindow") {
                            WindowManager.shared.configureOnboardingPanel(window)
                        }
                    })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
            
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showShortcutCheatSheet, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
        
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                if let img = NSImage(named: "menuBarIcon") {
                    let ratio = img.size.height / img.size.width
                    img.size.height = 22
                    img.size.width = 22 / ratio
                    return img
                } else {
                    // Fallback system image if custom asset is missing
                    let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceInk") ?? NSImage()
                    fallback.size = NSSize(width: 18, height: 22)
                    return fallback
                }
            }()

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
}

@MainActor
class UpdaterViewModel: ObservableObject {
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // Enable automatic update checking
        updaterController.updater.automaticallyChecksForUpdates = autoUpdateCheck
        updaterController.updater.updateCheckInterval = 24 * 60 * 60
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func toggleAutoUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }
    
    func checkForUpdates() {
        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }
    
    func silentlyCheckForUpdates() {
        // This checks for updates in the background without showing UI unless an update is found
        updaterController.updater.checkForUpdatesInBackground()
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
        Task { @MainActor in
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
