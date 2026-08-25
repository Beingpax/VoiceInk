import AppKit
import Foundation

@MainActor
class RecordingShortcutManager: ObservableObject {
    @Published var primaryRecordingShortcut: ShortcutSelection {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=primarySelection old=\(oldValue.rawValue) new=\(primaryRecordingShortcut.rawValue)"
            )
            UserDefaults.standard.set(primaryRecordingShortcut.rawValue, forKey: "primaryRecordingShortcut")
            refreshShortcutMonitoring(reason: "primary-selection-changed")
        }
    }
    @Published var secondaryRecordingShortcut: ShortcutSelection {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=secondarySelection old=\(oldValue.rawValue) new=\(secondaryRecordingShortcut.rawValue)"
            )
            if secondaryRecordingShortcut == .none {
                ShortcutStore.setShortcut(nil, for: .secondaryRecording)
            }
            UserDefaults.standard.set(secondaryRecordingShortcut.rawValue, forKey: "secondaryRecordingShortcut")
            refreshShortcutMonitoring(reason: "secondary-selection-changed")
        }
    }
    @Published var primaryRecordingShortcutMode: Mode {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=primaryMode old=\(oldValue.rawValue) new=\(primaryRecordingShortcutMode.rawValue)"
            )
            UserDefaults.standard.set(primaryRecordingShortcutMode.rawValue, forKey: "primaryRecordingShortcutMode")
            primaryRecordingShortcutModeSource.primaryMode = primaryRecordingShortcutMode
        }
    }
    @Published var secondaryRecordingShortcutMode: Mode {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=secondaryMode old=\(oldValue.rawValue) new=\(secondaryRecordingShortcutMode.rawValue)"
            )
            UserDefaults.standard.set(secondaryRecordingShortcutMode.rawValue, forKey: "secondaryRecordingShortcutMode")
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=middleClickEnabled old=\(oldValue) new=\(isMiddleClickToggleEnabled)"
            )
            UserDefaults.standard.set(isMiddleClickToggleEnabled, forKey: "isMiddleClickToggleEnabled")
            refreshShortcutMonitoring(reason: "middle-click-setting-changed")
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            ShortcutDiagnostics.notice(
                "recording-manager setting=middleClickDelay old=\(oldValue) new=\(middleClickActivationDelay)"
            )
            UserDefaults.standard.set(middleClickActivationDelay, forKey: "middleClickActivationDelay")
        }
    }

    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var recorderPanelShortcutManager: RecorderPanelShortcutManager
    private let modeShortcutManager: ModeShortcutManager
    private let shortcutMonitor = ShortcutMonitor(ownerLabel: "Recording")
    private var shortcutChangeObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private let primaryRecordingShortcutModeSource: RecordingShortcutModeSource

    // MARK: - Helper Properties
    private var canHandleShortcutAction: Bool {
        Self.canHandleShortcutAction(for: engine.recordingState)
    }

    // Middle-click event monitoring
    private var middleClickMonitors: [Any?] = []
    private var middleClickTask: Task<Void, Never>?

    enum Mode: String, CaseIterable {
        case toggle = "toggle"
        case pushToTalk = "pushToTalk"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .toggle: return String(localized: "Toggle")
            case .pushToTalk: return String(localized: "Push to Talk")
            case .hybrid: return String(localized: "Hybrid")
            }
        }
    }

    enum ShortcutSelection: String, CaseIterable {
        case none = "none"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .none: return String(localized: "None")
            case .custom: return String(localized: "Custom")
            }
        }
    }

    private static func canHandleShortcutAction(for recordingState: RecordingState) -> Bool {
        recordingState != .transcribing && recordingState != .enhancing && recordingState != .busy
    }

    init(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        ShortcutMigration.migrateLegacyShortcutsIfNeeded()

        self.primaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .primaryRecording,
            allowsNone: false
        )
        self.secondaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .secondaryRecording,
            allowsNone: true
        )

        let primaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .primaryRecording
        )
        self.primaryRecordingShortcutMode = primaryRecordingShortcutMode
        self.secondaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .secondaryRecording
        )

        self.isMiddleClickToggleEnabled = UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled")
        self.middleClickActivationDelay = UserDefaults.standard.integer(forKey: "middleClickActivationDelay")

        let shortcutModeHandler = RecordingShortcutModeHandler(
            canHandleShortcutAction: {
                Self.canHandleShortcutAction(for: engine.recordingState)
            },
            isRecorderVisible: {
                recorderUIManager.isRecorderPanelVisible
            },
            recordingState: {
                engine.recordingState
            },
            toggleRecorderPanel: { modeId in
                await recorderUIManager.toggleRecorderPanel(modeId: modeId)
            },
            cancelRecording: {
                await recorderUIManager.cancelRecording()
            }
        )

        let primaryRecordingShortcutModeSource = RecordingShortcutModeSource(
            primaryMode: primaryRecordingShortcutMode
        )

        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.recorderPanelShortcutManager = RecorderPanelShortcutManager(recorderUIManager: recorderUIManager)
        self.shortcutModeHandler = shortcutModeHandler
        self.primaryRecordingShortcutModeSource = primaryRecordingShortcutModeSource
        self.modeShortcutManager = ModeShortcutManager(
            modeProvider: {
                primaryRecordingShortcutModeSource.primaryMode
            },
            shortcutModeHandler: shortcutModeHandler
        )

        ShortcutDiagnostics.notice(
            "recording-manager init primarySelection=\(primaryRecordingShortcut.rawValue) primaryShortcut=\(ShortcutStore.shortcut(for: .primaryRecording)?.diagnosticDescription ?? "none") primaryMode=\(primaryRecordingShortcutMode.rawValue) secondarySelection=\(secondaryRecordingShortcut.rawValue) secondaryShortcut=\(ShortcutStore.shortcut(for: .secondaryRecording)?.diagnosticDescription ?? "none") secondaryMode=\(secondaryRecordingShortcutMode.rawValue) engineState=\(String(describing: engine.recordingState)) recorderVisible=\(recorderUIManager.isRecorderPanelVisible)"
        )
        setupLifecycleDiagnostics()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let action = (notification.object as? ShortcutAction)?.storageName ?? "unknown"
            ShortcutDiagnostics.notice("recording-manager shortcut-change-observed action=\(action)")
            Task { @MainActor in
                self?.refreshShortcutMonitoring(reason: "shortcut-store-notification.\(action)")
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.refreshShortcutMonitoring(reason: "delayed-initial-refresh")
        }
    }

    private func refreshShortcutMonitoring(reason: String) {
        ShortcutDiagnostics.notice(
            "recording-manager refresh begin reason=\(reason) engineState=\(String(describing: engine.recordingState)) recorderVisible=\(recorderUIManager.isRecorderPanelVisible)"
        )
        removeAllMonitoring(reason: "refresh.\(reason)")

        refreshShortcutMonitor()
        setupMiddleClickMonitoring()
        ShortcutDiagnostics.notice("recording-manager refresh end reason=\(reason)")
    }

    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else {
            ShortcutDiagnostics.notice("middle-click-monitor result=skipped-disabled")
            return
        }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self else {
                ShortcutDiagnostics.notice("middle-click event=down result=ignored-manager-released")
                return
            }
            guard event.buttonNumber == 2 else { return }

            ShortcutDiagnostics.notice(
                "middle-click event=down delayMs=\(self.middleClickActivationDelay) engineState=\(String(describing: self.engine.recordingState)) recorderVisible=\(self.recorderUIManager.isRecorderPanelVisible)"
            )

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delay = UInt64(self.middleClickActivationDelay) * 1_000_000  // ms to ns
                    try await Task.sleep(nanoseconds: delay)

                    guard self.isMiddleClickToggleEnabled else {
                        ShortcutDiagnostics.notice("middle-click result=ignored-disabled-after-delay")
                        return
                    }
                    guard !Task.isCancelled else {
                        ShortcutDiagnostics.notice("middle-click result=ignored-task-cancelled")
                        return
                    }

                    Task { @MainActor in
                        guard self.canHandleShortcutAction else {
                            ShortcutDiagnostics.notice(
                                "middle-click result=rejected-engine-state state=\(String(describing: self.engine.recordingState))"
                            )
                            return
                        }
                        ShortcutDiagnostics.notice("middle-click result=toggle-recorder")
                        await self.recorderUIManager.toggleRecorderPanel()
                    }
                } catch {
                    ShortcutDiagnostics.notice(
                        "middle-click result=delay-cancelled error=\(error.localizedDescription)"
                    )
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            ShortcutDiagnostics.notice("middle-click event=up result=cancel-pending-activation")
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
        ShortcutDiagnostics.notice(
            "middle-click-monitor result=installed down=\(downMonitor == nil ? "failed" : "ok") up=\(upMonitor == nil ? "failed" : "ok")"
        )
    }

    private func refreshShortcutMonitor() {
        let primaryShortcut = primaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .primaryRecording) : nil
        let secondaryShortcut =
            secondaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .secondaryRecording) : nil
        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.globalUtilityActions)
        var interruptibleRecordingActions = Set<ShortcutAction>()

        let missingUtilityActions = ShortcutAction.globalUtilityActions.filter { shortcuts[$0] == nil }.map(\.storageName)
        ShortcutDiagnostics.notice(
            "recording-manager registration-input primarySelection=\(primaryRecordingShortcut.rawValue) primaryStored=\(ShortcutStore.shortcut(for: .primaryRecording)?.diagnosticDescription ?? "none") primaryWillRegister=\(primaryShortcut != nil) secondarySelection=\(secondaryRecordingShortcut.rawValue) secondaryStored=\(ShortcutStore.shortcut(for: .secondaryRecording)?.diagnosticDescription ?? "none") secondaryWillRegister=\(secondaryShortcut != nil) utilityRegistered=\(shortcuts.keys.map(\.storageName).sorted().joined(separator: ",")) utilityMissing=\(missingUtilityActions.sorted().joined(separator: ","))"
        )

        if let primaryShortcut {
            shortcuts[.primaryRecording] = primaryShortcut
            interruptibleRecordingActions.insert(.primaryRecording)
        }

        if let secondaryShortcut {
            shortcuts[.secondaryRecording] = secondaryShortcut
            interruptibleRecordingActions.insert(.secondaryRecording)
        }

        let didStart = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: interruptibleRecordingActions,
            onKeyDown: { [weak self] action, eventTime in
                ShortcutDiagnostics.notice(
                    "recording-manager dispatch-received action=\(action.storageName) transition=keyDown eventUptime=\(eventTime)"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "recording-manager dispatch-dropped action=\(action.storageName) transition=keyDown reason=manager-released"
                        )
                        return
                    }
                    guard let mode = self.recordingMode(for: action) else {
                        ShortcutDiagnostics.notice(
                            "recording-manager dispatch-dropped action=\(action.storageName) transition=keyDown reason=not-recording-action"
                        )
                        return
                    }
                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: mode
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime in
                ShortcutDiagnostics.notice(
                    "recording-manager dispatch-received action=\(action.storageName) transition=keyUp eventUptime=\(eventTime)"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "recording-manager dispatch-dropped action=\(action.storageName) transition=keyUp reason=manager-released"
                        )
                        return
                    }
                    if let mode = self.recordingMode(for: action) {
                        await self.shortcutModeHandler.handleKeyUp(
                            action: action,
                            eventTime: eventTime,
                            mode: mode
                        )
                    } else {
                        await self.handleGlobalShortcut(action)
                    }
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                ShortcutDiagnostics.notice(
                    "recording-manager dispatch-received action=\(action.storageName) transition=interrupted"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "recording-manager dispatch-dropped action=\(action.storageName) transition=interrupted reason=manager-released"
                        )
                        return
                    }
                    guard self.recordingMode(for: action) != nil else {
                        ShortcutDiagnostics.notice(
                            "recording-manager dispatch-dropped action=\(action.storageName) transition=interrupted reason=not-recording-action"
                        )
                        return
                    }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
        let summary = shortcuts.map { "\($0.key.storageName)=\($0.value.diagnosticDescription)" }.sorted().joined(separator: " | ")
        ShortcutDiagnostics.notice(
            "recording-manager monitor-start result=\(didStart) count=\(shortcuts.count) interruptible=\(interruptibleRecordingActions.count) shortcuts={\(summary.isEmpty ? "none" : summary)}"
        )
    }

    private func recordingMode(for action: ShortcutAction) -> Mode? {
        switch action {
        case .primaryRecording:
            return primaryRecordingShortcutMode
        case .secondaryRecording:
            return secondaryRecordingShortcutMode
        default:
            return nil
        }
    }

    private func handleGlobalShortcut(_ action: ShortcutAction) async {
        ShortcutDiagnostics.notice(
            "global-action begin action=\(action.storageName) engineState=\(String(describing: engine.recordingState))"
        )
        switch action {
        case .pasteLastTranscription:
            LastTranscriptionService.pasteLastTranscription(from: engine.modelContext)
        case .pasteLastEnhancement:
            LastTranscriptionService.pasteLastEnhancement(from: engine.modelContext)
        case .retryLastTranscription:
            LastTranscriptionService.retryLastTranscription(
                from: engine.modelContext,
                transcriptionModelManager: engine.transcriptionModelManager,
                serviceRegistry: engine.serviceRegistry,
                enhancementService: engine.enhancementService
            )
        case .openHistoryWindow:
            HistoryWindowController.shared.showHistoryWindow(
                modelContainer: engine.modelContext.container,
                engine: engine
            )
        case .quickAddToDictionary:
            DictionaryQuickAddManager.shared.toggle(modelContainer: engine.modelContext.container)
        default:
            ShortcutDiagnostics.notice("global-action action=\(action.storageName) result=no-handler")
            break
        }
        ShortcutDiagnostics.notice("global-action end action=\(action.storageName)")
    }

    private func removeAllMonitoring(reason: String) {
        ShortcutDiagnostics.notice(
            "recording-manager remove-monitoring reason=\(reason) middleClickMonitorCount=\(middleClickMonitors.compactMap { $0 }.count)"
        )
        shortcutMonitor.stop(reason: reason)

        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()

        shortcutModeHandler.reset()
    }

    var isShortcutConfigured: Bool {
        let isPrimaryShortcutConfigured =
            primaryRecordingShortcut != .none && ShortcutStore.shortcut(for: .primaryRecording) != nil
        let isSecondaryShortcutConfigured =
            secondaryRecordingShortcut == .none || ShortcutStore.shortcut(for: .secondaryRecording) != nil
        return isPrimaryShortcutConfigured && isSecondaryShortcutConfigured
    }

    func updateShortcutStatus() {
        refreshShortcutMonitoring(reason: "explicit-status-update")
    }

    private func setupLifecycleDiagnostics() {
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        lifecycleObservers.append(
            appCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "application-did-become-active")
            })
        lifecycleObservers.append(
            appCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "application-did-resign-active")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "workspace-will-sleep")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "workspace-did-wake")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "screens-did-sleep")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "screens-did-wake")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "session-did-resign-active")
            })
        lifecycleObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
                ShortcutDiagnostics.logHealthReport(reason: "session-did-become-active")
            })
    }

    deinit {
        MainActor.assumeIsolated {
            if let shortcutChangeObserver {
                NotificationCenter.default.removeObserver(shortcutChangeObserver)
            }
            for observer in lifecycleObservers {
                NotificationCenter.default.removeObserver(observer)
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            removeAllMonitoring(reason: "manager-deinit")
        }
    }
}

@MainActor
private final class RecordingShortcutModeSource {
    var primaryMode: RecordingShortcutManager.Mode

    init(primaryMode: RecordingShortcutManager.Mode) {
        self.primaryMode = primaryMode
    }
}

@MainActor
final class RecordingShortcutModeHandler {
    private let canHandleShortcutAction: @MainActor () -> Bool
    private let isRecorderVisible: @MainActor () -> Bool
    private let recordingState: @MainActor () -> RecordingState
    private let toggleRecorderPanel: @MainActor (UUID?) async -> Void
    private let cancelRecording: @MainActor () async -> Void

    private var shortcutPressStartTime: TimeInterval?
    private var isHandsFreeRecording = false
    private var isShortcutPressed = false
    private var activeRecordingShortcutAction: ShortcutAction?
    private var interruptedRecordingActions = Set<ShortcutAction>()
    private var activeShortcutCanCancelAccidentalStart = false
    private var lastShortcutPressTime: Date?

    private let shortcutPressCooldown: TimeInterval = 0.5
    private let hybridPressThreshold: TimeInterval = 0.5

    init(
        canHandleShortcutAction: @escaping @MainActor () -> Bool,
        isRecorderVisible: @escaping @MainActor () -> Bool,
        recordingState: @escaping @MainActor () -> RecordingState,
        toggleRecorderPanel: @escaping @MainActor (UUID?) async -> Void,
        cancelRecording: @escaping @MainActor () async -> Void
    ) {
        self.canHandleShortcutAction = canHandleShortcutAction
        self.isRecorderVisible = isRecorderVisible
        self.recordingState = recordingState
        self.toggleRecorderPanel = toggleRecorderPanel
        self.cancelRecording = cancelRecording
    }

    func reset() {
        ShortcutDiagnostics.notice(
            "mode-handler reset wasPressed=\(isShortcutPressed) activeAction=\(activeRecordingShortcutAction?.storageName ?? "none") handsFree=\(isHandsFreeRecording) interrupted=\(interruptedRecordingActions.map(\.storageName).sorted().joined(separator: ","))"
        )
        isShortcutPressed = false
        shortcutPressStartTime = nil
        isHandsFreeRecording = false
        activeRecordingShortcutAction = nil
        interruptedRecordingActions.removeAll()
        activeShortcutCanCancelAccidentalStart = false
    }

    func handleKeyDown(
        action: ShortcutAction,
        eventTime: TimeInterval,
        mode: RecordingShortcutManager.Mode,
        modeId: UUID? = nil
    ) async {
        let currentState = recordingState()
        let recorderVisible = isRecorderVisible()
        ShortcutDiagnostics.notice(
            "mode-handler keyDown begin action=\(action.storageName) mode=\(mode.rawValue) modeId=\(modeId?.uuidString ?? "none") engineState=\(String(describing: currentState)) recorderVisible=\(recorderVisible) isPressed=\(isShortcutPressed) activeAction=\(activeRecordingShortcutAction?.storageName ?? "none") handsFree=\(isHandsFreeRecording)"
        )

        if interruptedRecordingActions.remove(action) != nil {
            ShortcutDiagnostics.notice(
                "mode-handler keyDown action=\(action.storageName) result=rejected reason=previously-interrupted"
            )
            return
        }

        if let lastTrigger = lastShortcutPressTime,
            Date().timeIntervalSince(lastTrigger) < shortcutPressCooldown
        {
            ShortcutDiagnostics.notice(
                "mode-handler keyDown action=\(action.storageName) result=rejected reason=cooldown elapsed=\(Date().timeIntervalSince(lastTrigger)) threshold=\(shortcutPressCooldown)"
            )
            return
        }

        guard !isShortcutPressed else {
            ShortcutDiagnostics.notice(
                "mode-handler keyDown action=\(action.storageName) result=rejected reason=another-shortcut-still-pressed activeAction=\(activeRecordingShortcutAction?.storageName ?? "none")"
            )
            return
        }
        isShortcutPressed = true
        activeRecordingShortcutAction = action
        activeShortcutCanCancelAccidentalStart = canCurrentShortcutPressCancelAccidentalStart
        lastShortcutPressTime = Date()
        shortcutPressStartTime = eventTime

        switch mode {
        case .toggle, .hybrid:
            if isHandsFreeRecording {
                isHandsFreeRecording = false
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "mode-handler keyDown action=\(action.storageName) result=rejected reason=engine-state handsFreeWasCleared=true engineState=\(String(describing: recordingState()))"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "mode-handler keyDown action=\(action.storageName) result=toggle-recorder reason=stop-hands-free"
                )
                await toggleRecorderPanel(modeId)
                return
            }

            if !isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "mode-handler keyDown action=\(action.storageName) result=rejected reason=engine-state engineState=\(String(describing: recordingState()))"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "mode-handler keyDown action=\(action.storageName) result=toggle-recorder reason=recorder-hidden"
                )
                await toggleRecorderPanel(modeId)
            } else {
                ShortcutDiagnostics.notice(
                    "mode-handler keyDown action=\(action.storageName) result=no-toggle reason=recorder-already-visible mode=\(mode.rawValue)"
                )
            }

        case .pushToTalk:
            if !isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "mode-handler keyDown action=\(action.storageName) result=rejected reason=engine-state engineState=\(String(describing: recordingState()))"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "mode-handler keyDown action=\(action.storageName) result=toggle-recorder reason=push-to-talk-start"
                )
                await toggleRecorderPanel(modeId)
            } else {
                ShortcutDiagnostics.notice(
                    "mode-handler keyDown action=\(action.storageName) result=no-toggle reason=recorder-already-visible mode=pushToTalk"
                )
            }
        }
        ShortcutDiagnostics.notice(
            "mode-handler keyDown end action=\(action.storageName) engineState=\(String(describing: recordingState())) recorderVisible=\(isRecorderVisible())"
        )
    }

    func handleKeyUp(
        action: ShortcutAction,
        eventTime: TimeInterval,
        mode: RecordingShortcutManager.Mode,
        modeId: UUID? = nil
    ) async {
        let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
        ShortcutDiagnostics.notice(
            "mode-handler keyUp begin action=\(action.storageName) mode=\(mode.rawValue) modeId=\(modeId?.uuidString ?? "none") duration=\(pressDuration) engineState=\(String(describing: recordingState())) recorderVisible=\(isRecorderVisible()) isPressed=\(isShortcutPressed) activeAction=\(activeRecordingShortcutAction?.storageName ?? "none")"
        )
        guard isShortcutPressed else {
            ShortcutDiagnostics.notice(
                "mode-handler keyUp action=\(action.storageName) result=rejected reason=no-active-press"
            )
            return
        }
        guard activeRecordingShortcutAction == action else {
            ShortcutDiagnostics.notice(
                "mode-handler keyUp action=\(action.storageName) result=rejected reason=active-action-mismatch activeAction=\(activeRecordingShortcutAction?.storageName ?? "none")"
            )
            return
        }
        isShortcutPressed = false
        activeRecordingShortcutAction = nil
        activeShortcutCanCancelAccidentalStart = false

        switch mode {
        case .toggle:
            isHandsFreeRecording = true
            ShortcutDiagnostics.notice(
                "mode-handler keyUp action=\(action.storageName) result=hands-free-enabled mode=toggle"
            )

        case .pushToTalk:
            if isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "mode-handler keyUp action=\(action.storageName) result=rejected reason=engine-state engineState=\(String(describing: recordingState())) mode=pushToTalk"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "mode-handler keyUp action=\(action.storageName) result=toggle-recorder reason=push-to-talk-stop"
                )
                await toggleRecorderPanel(modeId)
            } else {
                ShortcutDiagnostics.notice(
                    "mode-handler keyUp action=\(action.storageName) result=no-toggle reason=recorder-hidden mode=pushToTalk"
                )
            }

        case .hybrid:
            if pressDuration >= hybridPressThreshold && recordingState() == .recording {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "mode-handler keyUp action=\(action.storageName) result=rejected reason=engine-state engineState=\(String(describing: recordingState())) mode=hybrid"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "mode-handler keyUp action=\(action.storageName) result=toggle-recorder reason=hybrid-long-press duration=\(pressDuration)"
                )
                await toggleRecorderPanel(modeId)
            } else {
                isHandsFreeRecording = true
                ShortcutDiagnostics.notice(
                    "mode-handler keyUp action=\(action.storageName) result=hands-free-enabled reason=hybrid-short-or-not-recording duration=\(pressDuration) engineState=\(String(describing: recordingState()))"
                )
            }
        }

        shortcutPressStartTime = nil
        ShortcutDiagnostics.notice(
            "mode-handler keyUp end action=\(action.storageName) engineState=\(String(describing: recordingState())) recorderVisible=\(isRecorderVisible()) handsFree=\(isHandsFreeRecording)"
        )
    }

    func handleInterruption(action: ShortcutAction) async {
        ShortcutDiagnostics.notice(
            "mode-handler interruption begin action=\(action.storageName) isPressed=\(isShortcutPressed) activeAction=\(activeRecordingShortcutAction?.storageName ?? "none") canCancelCurrent=\(canCurrentShortcutPressCancelAccidentalStart) activeCanCancel=\(activeShortcutCanCancelAccidentalStart)"
        )
        guard isShortcutPressed, activeRecordingShortcutAction == action else {
            if canCurrentShortcutPressCancelAccidentalStart {
                interruptedRecordingActions.insert(action)
                ShortcutDiagnostics.notice(
                    "mode-handler interruption action=\(action.storageName) result=queued-before-keydown-handler"
                )
            } else {
                ShortcutDiagnostics.notice(
                    "mode-handler interruption action=\(action.storageName) result=ignored reason=not-active-and-cannot-cancel"
                )
            }
            return
        }

        guard activeShortcutCanCancelAccidentalStart else {
            ShortcutDiagnostics.notice(
                "mode-handler interruption action=\(action.storageName) result=ignored reason=active-press-cannot-cancel"
            )
            return
        }

        ShortcutDiagnostics.notice(
            "mode-handler interruption action=\(action.storageName) result=cancel-accidental-recording"
        )
        reset()
        await cancelRecording()
    }

    private var canCurrentShortcutPressCancelAccidentalStart: Bool {
        !isRecorderVisible() && recordingState() == .idle
    }
}
