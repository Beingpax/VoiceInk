import AppKit
import Foundation

@MainActor
class RecordingShortcutManager: ObservableObject {
    @Published var primaryRecordingShortcut: ShortcutSelection {
        didSet {
            UserDefaults.standard.set(primaryRecordingShortcut.rawValue, forKey: "primaryRecordingShortcut")
            refreshShortcutMonitoring()
        }
    }
    @Published var secondaryRecordingShortcut: ShortcutSelection {
        didSet {
            if secondaryRecordingShortcut == .none {
                ShortcutStore.setShortcut(nil, for: .secondaryRecording)
            }
            UserDefaults.standard.set(secondaryRecordingShortcut.rawValue, forKey: "secondaryRecordingShortcut")
            refreshShortcutMonitoring()
        }
    }
    @Published var primaryRecordingShortcutMode: Mode {
        didSet {
            UserDefaults.standard.set(primaryRecordingShortcutMode.rawValue, forKey: "primaryRecordingShortcutMode")
            primaryRecordingShortcutModeSource.primaryMode = primaryRecordingShortcutMode
        }
    }
    @Published var secondaryRecordingShortcutMode: Mode {
        didSet {
            UserDefaults.standard.set(secondaryRecordingShortcutMode.rawValue, forKey: "secondaryRecordingShortcutMode")
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMiddleClickToggleEnabled, forKey: "isMiddleClickToggleEnabled")
            refreshShortcutMonitoring()
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            UserDefaults.standard.set(middleClickActivationDelay, forKey: "middleClickActivationDelay")
        }
    }

    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var recorderPanelShortcutManager: RecorderPanelShortcutManager
    private let modeShortcutManager: ModeShortcutManager
    private let shortcutMonitor = ShortcutMonitor(ownerLabel: "Recording")
    private var shortcutChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
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

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshShortcutMonitoring()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.refreshShortcutMonitoring()
            ShortcutDiagnostics.logHealthReport(reason: "app-launch-after-shortcut-setup")
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previousOK = ShortcutMonitor.installSucceededByOwnerValue(for: "Recording")
                let snapshot = ShortcutDiagnostics.logPermissionSnapshot(
                    reason: "app-did-become-active",
                    force: false
                )

                // If Accessibility was granted while we were in background and the tap never installed, rebuild.
                if snapshot.accessibilityTrusted, previousOK == false {
                    ShortcutDiagnostics.notice(
                        "Accessibility now trusted after previous tap failure — refreshing shortcut monitoring"
                    )
                    self.refreshShortcutMonitoring()
                }
            }
        }
    }

    private func refreshShortcutMonitoring() {
        removeAllMonitoring()

        refreshShortcutMonitor()
        setupMiddleClickMonitoring()
    }

    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else { return }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delay = UInt64(self.middleClickActivationDelay) * 1_000_000  // ms to ns
                    try await Task.sleep(nanoseconds: delay)

                    guard self.isMiddleClickToggleEnabled, !Task.isCancelled else { return }

                    Task { @MainActor in
                        guard self.canHandleShortcutAction else { return }
                        await self.recorderUIManager.toggleRecorderPanel()
                    }
                } catch {
                    // Cancelled
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
    }

    private func refreshShortcutMonitor() {
        let primaryShortcut = primaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .primaryRecording) : nil
        let secondaryShortcut =
            secondaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .secondaryRecording) : nil
        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.globalUtilityActions)
        var interruptibleRecordingActions = Set<ShortcutAction>()

        if let primaryShortcut {
            shortcuts[.primaryRecording] = primaryShortcut
            interruptibleRecordingActions.insert(.primaryRecording)
        }

        if let secondaryShortcut {
            shortcuts[.secondaryRecording] = secondaryShortcut
            interruptibleRecordingActions.insert(.secondaryRecording)
        }

        ShortcutDiagnostics.notice(
            "refresh monitor: primarySelection=\(primaryRecordingShortcut.rawValue) primary=\(primaryShortcut?.diagnosticDescription ?? "nil") secondarySelection=\(secondaryRecordingShortcut.rawValue) secondary=\(secondaryShortcut?.diagnosticDescription ?? "nil") totalRegistered=\(shortcuts.count) recordingState=\(String(describing: engine.recordingState))"
        )

        let config = ShortcutDiagnostics.configurationSnapshot()
        if !config.issues.isEmpty {
            ShortcutDiagnostics.error(
                "refresh monitor config issues: \(config.issues.joined(separator: "; "))"
            )
        }
        if primaryRecordingShortcut == .custom, primaryShortcut == nil {
            ShortcutDiagnostics.error(
                "primary is Custom but stored shortcut is nil — user will see no global recording hotkey until they re-record"
            )
        }

        let installed = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: interruptibleRecordingActions,
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self else { return }
                    guard let mode = self.recordingMode(for: action) else {
                        ShortcutDiagnostics.notice(
                            "keyDown ignored: no recording mode for action=\(action.displayName)"
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
                Task { @MainActor in
                    guard let self else { return }
                    if let mode = self.recordingMode(for: action) {
                        await self.shortcutModeHandler.handleKeyUp(
                            action: action,
                            eventTime: eventTime,
                            mode: mode
                        )
                    } else {
                        ShortcutDiagnostics.notice(
                            "global utility keyUp action=\(action.displayName)"
                        )
                        await self.handleGlobalShortcut(action)
                    }
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, self.recordingMode(for: action) != nil else { return }
                    ShortcutDiagnostics.notice(
                        "recording shortcut interrupted action=\(action.displayName)"
                    )
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )

        if !installed {
            ShortcutDiagnostics.error(
                "recording shortcut event tap failed to install; global shortcuts will not work. \(ShortcutDiagnostics.permissionSnapshot().humanSummary)"
            )
        } else {
            ShortcutDiagnostics.notice(
                "recording shortcut monitor refreshed successfully liveTaps=\(ShortcutMonitor.allOwnersLiveTapSummary)"
            )
        }
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
            break
        }
    }

    private func removeAllMonitoring() {
        shortcutMonitor.stop()

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
        // Called when a shortcut changes
        refreshShortcutMonitoring()
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }

        MainActor.assumeIsolated {
            removeAllMonitoring()
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
        let state = recordingState()
        let recorderVisible = isRecorderVisible()

        if interruptedRecordingActions.remove(action) != nil {
            ShortcutDiagnostics.notice(
                "handler keyDown IGNORED (prior interruption) action=\(action.displayName) mode=\(mode.rawValue) state=\(String(describing: state)) — event was already matched/suppressed by the tap"
            )
            return
        }

        if let lastTrigger = lastShortcutPressTime,
            Date().timeIntervalSince(lastTrigger) < shortcutPressCooldown
        {
            ShortcutDiagnostics.notice(
                "handler keyDown IGNORED (cooldown \(shortcutPressCooldown)s) action=\(action.displayName) mode=\(mode.rawValue) state=\(String(describing: state)) — event was already matched/suppressed by the tap"
            )
            return
        }

        guard !isShortcutPressed else {
            ShortcutDiagnostics.notice(
                "handler keyDown IGNORED (already pressed) action=\(action.displayName) active=\(activeRecordingShortcutAction?.displayName ?? "nil") — event was already matched/suppressed by the tap"
            )
            return
        }
        isShortcutPressed = true
        activeRecordingShortcutAction = action
        activeShortcutCanCancelAccidentalStart = canCurrentShortcutPressCancelAccidentalStart
        lastShortcutPressTime = Date()
        shortcutPressStartTime = eventTime

        ShortcutDiagnostics.notice(
            "handler keyDown begin action=\(action.displayName) mode=\(mode.rawValue) modeId=\(modeId?.uuidString ?? "nil") state=\(String(describing: state)) recorderVisible=\(recorderVisible) handsFree=\(isHandsFreeRecording) canHandle=\(canHandleShortcutAction())"
        )

        switch mode {
        case .toggle, .hybrid:
            if isHandsFreeRecording {
                isHandsFreeRecording = false
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "handler keyDown skip toggle (busy) action=\(action.displayName) state=\(String(describing: state)) — key already suppressed, user may hear system reject sound with no UI"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "handler keyDown → toggleRecorderPanel (hands-free stop) action=\(action.displayName)"
                )
                await toggleRecorderPanel(modeId)
                return
            }

            if !isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "handler keyDown skip start (busy) action=\(action.displayName) state=\(String(describing: state)) — key already suppressed, user may hear system reject sound with no UI"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "handler keyDown → toggleRecorderPanel (start) action=\(action.displayName)"
                )
                await toggleRecorderPanel(modeId)
            } else {
                ShortcutDiagnostics.notice(
                    "handler keyDown no-op (recorder already visible) action=\(action.displayName)"
                )
            }

        case .pushToTalk:
            if !isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "handler keyDown skip PTT start (busy) action=\(action.displayName) state=\(String(describing: state)) — key already suppressed"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "handler keyDown → toggleRecorderPanel (PTT start) action=\(action.displayName)"
                )
                await toggleRecorderPanel(modeId)
            }
        }
    }

    func handleKeyUp(
        action: ShortcutAction,
        eventTime: TimeInterval,
        mode: RecordingShortcutManager.Mode,
        modeId: UUID? = nil
    ) async {
        guard isShortcutPressed, activeRecordingShortcutAction == action else {
            ShortcutDiagnostics.notice(
                "handler keyUp IGNORED action=\(action.displayName) isPressed=\(isShortcutPressed) active=\(activeRecordingShortcutAction?.displayName ?? "nil")"
            )
            return
        }
        isShortcutPressed = false
        activeRecordingShortcutAction = nil
        activeShortcutCanCancelAccidentalStart = false

        let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
        ShortcutDiagnostics.notice(
            "handler keyUp begin action=\(action.displayName) mode=\(mode.rawValue) duration=\(pressDuration)s state=\(String(describing: recordingState())) recorderVisible=\(isRecorderVisible())"
        )

        switch mode {
        case .toggle:
            isHandsFreeRecording = true

        case .pushToTalk:
            if isRecorderVisible() {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "handler keyUp skip PTT stop (busy) action=\(action.displayName)"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "handler keyUp → toggleRecorderPanel (PTT stop) action=\(action.displayName)"
                )
                await toggleRecorderPanel(modeId)
            }

        case .hybrid:
            if pressDuration >= hybridPressThreshold && recordingState() == .recording {
                guard canHandleShortcutAction() else {
                    ShortcutDiagnostics.notice(
                        "handler keyUp skip hybrid stop (busy) action=\(action.displayName)"
                    )
                    return
                }
                ShortcutDiagnostics.notice(
                    "handler keyUp → toggleRecorderPanel (hybrid long-press stop) action=\(action.displayName)"
                )
                await toggleRecorderPanel(modeId)
            } else {
                isHandsFreeRecording = true
                ShortcutDiagnostics.notice(
                    "handler keyUp hybrid → hands-free action=\(action.displayName) duration=\(pressDuration)s"
                )
            }
        }

        shortcutPressStartTime = nil
    }

    func handleInterruption(action: ShortcutAction) async {
        guard isShortcutPressed, activeRecordingShortcutAction == action else {
            if canCurrentShortcutPressCancelAccidentalStart {
                interruptedRecordingActions.insert(action)
                ShortcutDiagnostics.notice(
                    "handler interruption queued (pre-handler) action=\(action.displayName)"
                )
            } else {
                ShortcutDiagnostics.notice(
                    "handler interruption ignored (not active) action=\(action.displayName)"
                )
            }
            return
        }

        guard activeShortcutCanCancelAccidentalStart else {
            ShortcutDiagnostics.notice(
                "handler interruption ignored (cannot cancel) action=\(action.displayName)"
            )
            return
        }

        ShortcutDiagnostics.notice(
            "handler interruption → cancelRecording action=\(action.displayName)"
        )
        reset()
        await cancelRecording()
    }

    private var canCurrentShortcutPressCancelAccidentalStart: Bool {
        !isRecorderVisible() && recordingState() == .idle
    }
}
