import AppKit
import Carbon.HIToolbox

enum ShortcutValidationError: Equatable {
    case plainKeyRequiresModifier
    case shiftTypingKeyRequiresAdditionalModifier
    case reservedBySystem
    case alreadyUsedBy(String)

    func notificationTitle(for shortcut: Shortcut) -> String {
        switch self {
        case .plainKeyRequiresModifier:
            return "Shortcut not allowed: \(shortcut.displayString)"
        case .shiftTypingKeyRequiresAdditionalModifier:
            return "Shortcut not allowed: \(shortcut.displayString)"
        case .reservedBySystem:
            return "Shortcut reserved by macOS: \(shortcut.displayString)"
        case .alreadyUsedBy(let actionName):
            return "Shortcut already used by \(actionName)"
        }
    }
}

enum ShortcutValidator {
    static func validationError(for shortcut: Shortcut, action: ShortcutAction) -> ShortcutValidationError? {
        if let error = userRecordingShortcutError(for: shortcut) {
            return error
        }

        if let reservedAction = reservedActionConflicting(with: shortcut) {
            return .alreadyUsedBy(reservedAction.displayName)
        }

        if systemReservedShortcuts.contains(where: { $0.conflicts(with: shortcut) }) {
            return .reservedBySystem
        }

        if let existingAction = storedActionConflicting(with: shortcut, excluding: action) {
            return .alreadyUsedBy(existingAction.displayName)
        }

        return nil
    }

    private static func userRecordingShortcutError(for shortcut: Shortcut) -> ShortcutValidationError? {
        switch shortcut.kind {
        case .modifierOnly:
            return shortcut.modifierFlags.isEmpty ? .plainKeyRequiresModifier : nil
        case .key:
            if Shortcut.isFunctionKeyCode(shortcut.keyCode) {
                return nil
            }

            guard !shortcut.modifierFlags.isEmpty else {
                return .plainKeyRequiresModifier
            }

            if shortcut.modifierFlags == [.shift],
               shiftOnlyTypingKeyCodes.contains(shortcut.keyCode) {
                return .shiftTypingKeyRequiresAdditionalModifier
            }

            return nil
        }
    }

    private static func storedActionConflicting(with candidate: Shortcut, excluding actionToIgnore: ShortcutAction) -> ShortcutAction? {
        for action in allStoredActions where action != actionToIgnore {
            guard let existingShortcut = ShortcutStore.shortcut(for: action) else {
                continue
            }

            if existingShortcut.conflicts(with: candidate) {
                return action
            }
        }

        return nil
    }

    private static func reservedActionConflicting(with shortcut: Shortcut) -> ShortcutAction? {
        for (action, reservedShortcut) in reservedRecorderPanelShortcuts {
            if reservedShortcut.conflicts(with: shortcut) {
                return action
            }
        }

        return nil
    }

    private static var allStoredActions: [ShortcutAction] {
        var seenActions = Set<ShortcutAction>()
        let actions = ShortcutAction.legacyKeyboardShortcutActions +
            ModeManager.shared.configurations.map { ShortcutAction.mode($0.id) }

        return actions.filter { seenActions.insert($0).inserted }
    }

    private static var reservedRecorderPanelShortcuts: [(ShortcutAction, Shortcut)] {
        digitKeyCodes.enumerated().map { index, keyCode in
            (
                ShortcutAction.recorderPanelMode(index),
                Shortcut.key(keyCode: keyCode, modifierFlags: [.option])
            )
        }
    }

    private static var systemReservedShortcuts: [Shortcut] {
        commonEditAndAppShortcuts +
            sessionShortcuts +
            essentialTextEditingShortcuts
    }

    private static var commonEditAndAppShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_A, [.command]),
            shortcut(kVK_ANSI_C, [.command]),
            shortcut(kVK_ANSI_F, [.command]),
            shortcut(kVK_ANSI_H, [.command]),
            shortcut(kVK_ANSI_H, [.option, .command]),
            shortcut(kVK_ANSI_M, [.command]),
            shortcut(kVK_ANSI_M, [.option, .command]),
            shortcut(kVK_ANSI_N, [.command]),
            shortcut(kVK_ANSI_O, [.command]),
            shortcut(kVK_ANSI_P, [.command]),
            shortcut(kVK_ANSI_Q, [.command]),
            shortcut(kVK_ANSI_S, [.command]),
            shortcut(kVK_ANSI_T, [.command]),
            shortcut(kVK_ANSI_V, [.command]),
            shortcut(kVK_ANSI_V, [.option, .shift, .command]),
            shortcut(kVK_ANSI_W, [.command]),
            shortcut(kVK_ANSI_W, [.option, .command]),
            shortcut(kVK_ANSI_X, [.command]),
            shortcut(kVK_ANSI_Z, [.command]),
            shortcut(kVK_ANSI_Z, [.shift, .command]),
            shortcut(kVK_ANSI_Comma, [.command])
        ]
    }

    private static var sessionShortcuts: [Shortcut] {
        [
            shortcut(kVK_Escape, [.option, .command]),
            shortcut(kVK_ANSI_Q, [.control, .command]),
            shortcut(kVK_ANSI_Q, [.shift, .command]),
            shortcut(kVK_ANSI_Q, [.option, .shift, .command])
        ]
    }

    private static var essentialTextEditingShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_B, [.command]),
            shortcut(kVK_ANSI_I, [.command]),
            shortcut(kVK_ANSI_U, [.command]),
            shortcut(kVK_ANSI_D, [.control, .command]),
            shortcut(kVK_Delete, [.option])
        ]
    }

    private static func shortcut(_ keyCode: Int, _ modifierFlags: NSEvent.ModifierFlags) -> Shortcut {
        .key(keyCode: UInt16(keyCode), modifierFlags: modifierFlags)
    }

    private static let shiftOnlyTypingKeyCodes: Set<UInt16> = [
        UInt16(kVK_ANSI_A),
        UInt16(kVK_ANSI_B),
        UInt16(kVK_ANSI_C),
        UInt16(kVK_ANSI_D),
        UInt16(kVK_ANSI_E),
        UInt16(kVK_ANSI_F),
        UInt16(kVK_ANSI_G),
        UInt16(kVK_ANSI_H),
        UInt16(kVK_ANSI_I),
        UInt16(kVK_ANSI_J),
        UInt16(kVK_ANSI_K),
        UInt16(kVK_ANSI_L),
        UInt16(kVK_ANSI_M),
        UInt16(kVK_ANSI_N),
        UInt16(kVK_ANSI_O),
        UInt16(kVK_ANSI_P),
        UInt16(kVK_ANSI_Q),
        UInt16(kVK_ANSI_R),
        UInt16(kVK_ANSI_S),
        UInt16(kVK_ANSI_T),
        UInt16(kVK_ANSI_U),
        UInt16(kVK_ANSI_V),
        UInt16(kVK_ANSI_W),
        UInt16(kVK_ANSI_X),
        UInt16(kVK_ANSI_Y),
        UInt16(kVK_ANSI_Z),
        UInt16(kVK_ANSI_0),
        UInt16(kVK_ANSI_1),
        UInt16(kVK_ANSI_2),
        UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5),
        UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_Grave),
        UInt16(kVK_ANSI_Minus),
        UInt16(kVK_ANSI_Equal),
        UInt16(kVK_ANSI_LeftBracket),
        UInt16(kVK_ANSI_RightBracket),
        UInt16(kVK_ANSI_Backslash),
        UInt16(kVK_ANSI_Semicolon),
        UInt16(kVK_ANSI_Quote),
        UInt16(kVK_ANSI_Comma),
        UInt16(kVK_ANSI_Period),
        UInt16(kVK_ANSI_Slash),
        UInt16(kVK_Space),
        UInt16(kVK_ANSI_Keypad0),
        UInt16(kVK_ANSI_Keypad1),
        UInt16(kVK_ANSI_Keypad2),
        UInt16(kVK_ANSI_Keypad3),
        UInt16(kVK_ANSI_Keypad4),
        UInt16(kVK_ANSI_Keypad5),
        UInt16(kVK_ANSI_Keypad6),
        UInt16(kVK_ANSI_Keypad7),
        UInt16(kVK_ANSI_Keypad8),
        UInt16(kVK_ANSI_Keypad9),
        UInt16(kVK_ANSI_KeypadDecimal),
        UInt16(kVK_ANSI_KeypadDivide),
        UInt16(kVK_ANSI_KeypadMultiply),
        UInt16(kVK_ANSI_KeypadMinus),
        UInt16(kVK_ANSI_KeypadPlus),
        UInt16(kVK_ANSI_KeypadEquals)
    ]

    private static let digitKeyCodes: [UInt16] = [
        UInt16(kVK_ANSI_1),
        UInt16(kVK_ANSI_2),
        UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5),
        UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_0)
    ]
}
