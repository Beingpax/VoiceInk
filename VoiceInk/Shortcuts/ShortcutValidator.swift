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
        for (action, reservedShortcut) in reservedMiniRecorderShortcuts {
            if reservedShortcut.conflicts(with: shortcut) {
                return action
            }
        }

        return nil
    }

    private static var allStoredActions: [ShortcutAction] {
        ShortcutAction.legacyKeyboardShortcutActions +
            PowerModeManager.shared.configurations.map { ShortcutAction.powerMode($0.id) }
    }

    private static var reservedMiniRecorderShortcuts: [(ShortcutAction, Shortcut)] {
        digitKeyCodes.enumerated().flatMap { index, keyCode in
            [
                (
                    ShortcutAction.miniRecorderPrompt(index),
                    Shortcut.key(keyCode: keyCode, modifierFlags: [.command])
                ),
                (
                    ShortcutAction.miniRecorderPowerMode(index),
                    Shortcut.key(keyCode: keyCode, modifierFlags: [.option])
                )
            ]
        }
    }

    private static var systemReservedShortcuts: [Shortcut] {
        commonEditAndAppShortcuts +
            systemNavigationShortcuts +
            screenshotShortcuts +
            sessionShortcuts +
            finderShortcuts +
            textEditingShortcuts +
            accessibilityAndInputShortcuts +
            functionKeyShortcuts
    }

    private static var commonEditAndAppShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_A, [.command]),
            shortcut(kVK_ANSI_C, [.command]),
            shortcut(kVK_ANSI_F, [.command]),
            shortcut(kVK_ANSI_G, [.command]),
            shortcut(kVK_ANSI_G, [.shift, .command]),
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

    private static var systemNavigationShortcuts: [Shortcut] {
        [
            shortcut(kVK_Space, [.command]),
            shortcut(kVK_Space, [.option, .command]),
            shortcut(kVK_Space, [.control, .command]),
            shortcut(kVK_Tab, [.command]),
            shortcut(kVK_Tab, [.shift, .command]),
            shortcut(kVK_ANSI_Grave, [.command]),
            shortcut(kVK_ANSI_Grave, [.shift, .command]),
            shortcut(kVK_ANSI_Grave, [.option, .command]),
            shortcut(kVK_UpArrow, [.control]),
            shortcut(kVK_DownArrow, [.control]),
            shortcut(kVK_Space, [.control]),
            shortcut(kVK_Space, [.control, .option])
        ]
    }

    private static var screenshotShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_3, [.shift, .command]),
            shortcut(kVK_ANSI_4, [.shift, .command]),
            shortcut(kVK_ANSI_5, [.shift, .command]),
            shortcut(kVK_ANSI_6, [.shift, .command]),
            shortcut(kVK_ANSI_3, [.control, .shift, .command]),
            shortcut(kVK_ANSI_4, [.control, .shift, .command]),
            shortcut(kVK_ANSI_5, [.control, .shift, .command]),
            shortcut(kVK_ANSI_6, [.control, .shift, .command])
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

    private static var finderShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_D, [.command]),
            shortcut(kVK_ANSI_E, [.command]),
            shortcut(kVK_ANSI_I, [.command]),
            shortcut(kVK_ANSI_J, [.command]),
            shortcut(kVK_ANSI_K, [.command]),
            shortcut(kVK_ANSI_R, [.command]),
            shortcut(kVK_ANSI_Y, [.command]),
            shortcut(kVK_ANSI_C, [.shift, .command]),
            shortcut(kVK_ANSI_D, [.shift, .command]),
            shortcut(kVK_ANSI_F, [.shift, .command]),
            shortcut(kVK_ANSI_G, [.shift, .command]),
            shortcut(kVK_ANSI_H, [.shift, .command]),
            shortcut(kVK_ANSI_I, [.shift, .command]),
            shortcut(kVK_ANSI_K, [.shift, .command]),
            shortcut(kVK_ANSI_N, [.shift, .command]),
            shortcut(kVK_ANSI_O, [.shift, .command]),
            shortcut(kVK_ANSI_P, [.shift, .command]),
            shortcut(kVK_ANSI_R, [.shift, .command]),
            shortcut(kVK_ANSI_T, [.shift, .command]),
            shortcut(kVK_ANSI_U, [.shift, .command]),
            shortcut(kVK_ANSI_D, [.option, .command]),
            shortcut(kVK_ANSI_L, [.option, .command]),
            shortcut(kVK_ANSI_N, [.option, .command]),
            shortcut(kVK_ANSI_P, [.option, .command]),
            shortcut(kVK_ANSI_S, [.option, .command]),
            shortcut(kVK_ANSI_T, [.option, .command]),
            shortcut(kVK_ANSI_V, [.option, .command]),
            shortcut(kVK_ANSI_Y, [.option, .command]),
            shortcut(kVK_Delete, [.command]),
            shortcut(kVK_Delete, [.shift, .command]),
            shortcut(kVK_Delete, [.option, .shift, .command]),
            shortcut(kVK_ANSI_LeftBracket, [.command]),
            shortcut(kVK_ANSI_RightBracket, [.command]),
            shortcut(kVK_UpArrow, [.command]),
            shortcut(kVK_DownArrow, [.command]),
            shortcut(kVK_UpArrow, [.control, .command])
        ]
    }

    private static var accessibilityAndInputShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_8, [.control, .option, .command]),
            shortcut(kVK_ANSI_Comma, [.control, .option, .command]),
            shortcut(kVK_ANSI_Period, [.control, .option, .command]),
            shortcut(kVK_F5, [.option, .command]),
            shortcut(kVK_Tab, [.control]),
            shortcut(kVK_Tab, [.control, .shift])
        ]
    }

    private static var textEditingShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_B, [.command]),
            shortcut(kVK_ANSI_I, [.command]),
            shortcut(kVK_ANSI_U, [.command]),
            shortcut(kVK_ANSI_D, [.control, .command]),
            shortcut(kVK_ANSI_Semicolon, [.command]),
            shortcut(kVK_ANSI_Semicolon, [.shift, .command]),
            shortcut(kVK_ANSI_Minus, [.shift, .command]),
            shortcut(kVK_ANSI_Equal, [.command]),
            shortcut(kVK_ANSI_Equal, [.shift, .command]),
            shortcut(kVK_ANSI_Slash, [.command]),
            shortcut(kVK_ANSI_Slash, [.shift, .command]),
            shortcut(kVK_ANSI_LeftBracket, [.shift, .command]),
            shortcut(kVK_ANSI_RightBracket, [.shift, .command]),
            shortcut(kVK_ANSI_Backslash, [.shift, .command]),
            shortcut(kVK_Delete, [.option]),
            shortcut(kVK_Delete, [.function]),
            shortcut(kVK_UpArrow, [.function]),
            shortcut(kVK_DownArrow, [.function]),
            shortcut(kVK_LeftArrow, [.function]),
            shortcut(kVK_RightArrow, [.function]),
            shortcut(kVK_UpArrow, [.command]),
            shortcut(kVK_DownArrow, [.command]),
            shortcut(kVK_LeftArrow, [.command]),
            shortcut(kVK_RightArrow, [.command]),
            shortcut(kVK_LeftArrow, [.option]),
            shortcut(kVK_RightArrow, [.option]),
            shortcut(kVK_UpArrow, [.shift]),
            shortcut(kVK_DownArrow, [.shift]),
            shortcut(kVK_LeftArrow, [.shift]),
            shortcut(kVK_RightArrow, [.shift]),
            shortcut(kVK_UpArrow, [.shift, .command]),
            shortcut(kVK_DownArrow, [.shift, .command]),
            shortcut(kVK_LeftArrow, [.shift, .command]),
            shortcut(kVK_RightArrow, [.shift, .command]),
            shortcut(kVK_UpArrow, [.option, .shift]),
            shortcut(kVK_DownArrow, [.option, .shift]),
            shortcut(kVK_LeftArrow, [.option, .shift]),
            shortcut(kVK_RightArrow, [.option, .shift]),
            shortcut(kVK_ANSI_A, [.control]),
            shortcut(kVK_ANSI_B, [.control]),
            shortcut(kVK_ANSI_D, [.control]),
            shortcut(kVK_ANSI_E, [.control]),
            shortcut(kVK_ANSI_F, [.control]),
            shortcut(kVK_ANSI_H, [.control]),
            shortcut(kVK_ANSI_K, [.control]),
            shortcut(kVK_ANSI_L, [.control]),
            shortcut(kVK_ANSI_N, [.control]),
            shortcut(kVK_ANSI_O, [.control]),
            shortcut(kVK_ANSI_P, [.control]),
            shortcut(kVK_ANSI_T, [.control]),
            shortcut(kVK_ANSI_Y, [.control])
        ]
    }

    private static var functionKeyShortcuts: [Shortcut] {
        [
            shortcut(kVK_ANSI_A, [.function]),
            shortcut(kVK_ANSI_C, [.function]),
            shortcut(kVK_ANSI_D, [.function]),
            shortcut(kVK_ANSI_E, [.function]),
            shortcut(kVK_ANSI_N, [.function]),
            shortcut(kVK_ANSI_Q, [.function]),
            shortcut(kVK_ANSI_A, [.function, .shift]),
            shortcut(kVK_F2, [.control]),
            shortcut(kVK_F3, [.control]),
            shortcut(kVK_F4, [.control]),
            shortcut(kVK_F5, [.control]),
            shortcut(kVK_F6, [.control]),
            shortcut(kVK_F6, [.control, .shift]),
            shortcut(kVK_F7, [.control]),
            shortcut(kVK_F8, [.control])
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
