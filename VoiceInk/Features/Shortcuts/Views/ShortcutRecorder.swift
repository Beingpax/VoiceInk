import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: View {
    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let onShortcutChanged: () -> Void

    @StateObject private var recorder = ShortcutRecorderModel()
    @State private var recorderID = UUID()
    @State private var shortcut: Shortcut?

    init(
        action: ShortcutAction,
        defaultShortcut: Shortcut? = nil,
        onShortcutChanged: @escaping () -> Void = {}
    ) {
        self.action = action
        self.defaultShortcut = defaultShortcut
        self.onShortcutChanged = onShortcutChanged
        _shortcut = State(initialValue: ShortcutStore.shortcut(for: action))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if recorder.isRecording {
                    recorder.cancel()
                } else {
                    NotificationCenter.default.post(
                        name: Self.shortcutRecordingDidStart,
                        object: recorderID
                    )
                    clearShortcutBeforeRecording()
                    recorder.start(action: action) { newShortcut in
                        shortcut = newShortcut
                        onShortcutChanged()
                    }
                }
            } label: {
                ShortcutVisualization(
                    shortcut: displayedShortcut,
                    isRecording: recorder.isRecording
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)

        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let changedAction = notification.object as? ShortcutAction, changedAction == action else { return }
            shortcut = ShortcutStore.shortcut(for: action)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.shortcutRecordingDidStart)) { notification in
            guard let activeRecorderID = notification.object as? UUID, activeRecorderID != recorderID else { return }
            recorder.cancel()
        }
        .onChange(of: action) { _, newAction in
            recorder.cancel()
            recorderID = UUID()
            shortcut = ShortcutStore.shortcut(for: newAction)
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var accessibilityLabel: String {
        if recorder.isRecording {
            return recorder.previewShortcut?.displayString ?? String(localized: "Press shortcut")
        }

        return displayedShortcut?.displayString ?? String(localized: "Record shortcut")
    }

    private var displayedShortcut: Shortcut? {
        if recorder.isRecording {
            return recorder.previewShortcut
        }

        return shortcut ?? defaultShortcut
    }

    private func clearShortcutBeforeRecording() {
        ShortcutStore.setShortcut(nil, for: action)
        shortcut = nil
        onShortcutChanged()
    }

    private static let shortcutRecordingDidStart = Notification.Name("ShortcutRecorderRecordingDidStart")
}

struct ShortcutVisualization: View {
    let shortcut: Shortcut?
    let isRecording: Bool
    var isCompact = false

    var body: some View {
        HStack(spacing: 4) {
            if let shortcut {
                ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
                    ShortcutKeyCap(title: token, isRecording: isRecording, isCompact: isCompact)
                }
            } else {
                Text(isRecording ? LocalizedStringKey("Press shortcut") : LocalizedStringKey("Record"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isRecording ? .primary : .secondary)
            }
        }
        .padding(isCompact ? 2 : 4)
        .frame(minWidth: shortcut == nil ? 104 : nil, minHeight: isCompact ? 20 : 26)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: isCompact ? 5 : 6)
                .fill(isRecording ? AppTheme.Accent.fill : AppTheme.Surface.control)
        }
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 5 : 6)
                .stroke(isRecording ? AppTheme.Accent.border : AppTheme.Border.subtle, lineWidth: 1)
        }
    }
}

private struct ShortcutKeyCap: View {
    let title: String
    let isRecording: Bool
    let isCompact: Bool

    var body: some View {
        Text(title)
            .font(.system(size: isCompact ? 9 : 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isCompact ? 4 : 5)
            .frame(minHeight: isCompact ? 14 : 18)
            .background {
                RoundedRectangle(cornerRadius: isCompact ? 3 : 4)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: isCompact ? 3 : 4)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }

    private var backgroundColor: Color {
        Color(NSColor.labelColor)
    }

    private var borderColor: Color {
        isRecording ? AppTheme.Accent.foreground : foregroundColor.opacity(0.28)
    }
}

final class ShortcutRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var previewShortcut: Shortcut?

    private var localMonitor: Any?
    private var onCapture: ((Shortcut) -> Void)?
    private var activeAction: ShortcutAction?
    private var pendingModifierShortcut: Shortcut?
    private var peakModifierFlags: NSEvent.ModifierFlags = []

    deinit {
        removeRecordingMonitor()
    }

    func start(action: ShortcutAction, onCapture: @escaping (Shortcut) -> Void) {
        cancel()

        activeAction = action
        self.onCapture = onCapture
        isRecording = true
        previewShortcut = nil
        installRecordingMonitor()
    }

    func cancel() {
        removeRecordingMonitor()
        resetRecordingState()
    }

    private func finish(with shortcut: Shortcut) {
        guard let activeAction else {
            cancel()
            return
        }

        if let validationError = ShortcutValidator.validationError(for: shortcut, action: activeAction) {
            cancel()
            showErrorNotification(validationError.notificationTitle(for: shortcut))
            return
        }

        let capture = onCapture
        removeRecordingMonitor()
        resetRecordingState()

        ShortcutStore.setShortcut(shortcut, for: activeAction)
        capture?(shortcut)
    }

    private func resetRecordingState() {
        isRecording = false
        previewShortcut = nil
        onCapture = nil
        activeAction = nil
        pendingModifierShortcut = nil
        peakModifierFlags = []
    }

    private func showErrorNotification(_ title: String) {
        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: title,
                type: .error
            )
        }
    }

    private func installRecordingMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let shouldConsume = self.handleRecordingEvent(event)
            return shouldConsume ? nil : event
        }
    }

    private func removeRecordingMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        guard isRecording else {
            return false
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        case .otherMouseDown:
            return handleMouseDown(buttonNumber: event.buttonNumber, modifierFlags: event.modifierFlags)
        default:
            return false
        }
    }

    private func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            if activeAction == .cancelRecorder {
                let shortcut = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
                previewShortcut = shortcut
                finish(with: shortcut)
            } else {
                cancel()
            }
            return true
        }

        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return true
        }

        let shortcut = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
        previewShortcut = shortcut
        finish(with: shortcut)
        return true
    }

    private func handleMouseDown(buttonNumber: Int, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let buttonNumber = UInt16(exactly: buttonNumber),
            Shortcut.isSupportedMouseButtonNumber(buttonNumber)
        else {
            return false
        }

        let shortcut = Shortcut.mouseButton(
            buttonNumber: buttonNumber,
            modifierFlags: Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil)
        )
        previewShortcut = shortcut
        finish(with: shortcut)
        return true
    }

    private func handleFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if modifiers.isEmpty,
            Shortcut.isFunctionKeyCode(keyCode),
            Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil).contains(.function)
        {
            return true
        }

        if !modifiers.isEmpty {
            peakModifierFlags.formUnion(modifiers)
            let singleModifierKeyCode = Shortcut.modifierKeyCodeForSingleModifierEvent(
                keyCode: keyCode,
                modifiers: peakModifierFlags
            )
            let shortcut = Shortcut.modifierOnly(
                keyCode: singleModifierKeyCode,
                modifierFlags: peakModifierFlags
            )

            pendingModifierShortcut = shortcut
            previewShortcut = shortcut
            return true
        }

        if let pendingModifierShortcut {
            finish(with: pendingModifierShortcut)
        }

        return true
    }
}
