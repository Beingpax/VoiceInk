import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    enum Kind: String, Codable {
        case key
        case modifierOnly
    }

    private static let genericModifierKeyCode = UInt16.max

    let kind: Kind
    let keyCode: UInt16
    private let modifierFlagsRawValue: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
        let keyCode = kind == .key ? keyCode : nil
        return Self.normalizedModifierFlags(flags, forKeyCode: keyCode)
    }

    var isModifierOnly: Bool {
        kind == .modifierOnly
    }

    var displayString: String {
        displayTokens.joined(separator: " + ")
    }

    var displayTokens: [String] {
        switch kind {
        case .key:
            return modifierFlags.shortcutDisplayTokens + [Self.keyName(for: keyCode)]
        case .modifierOnly:
            if let sideSpecificName = Self.sideSpecificModifierName(for: keyCode, modifiers: modifierFlags) {
                return [sideSpecificName]
            }

            return modifierFlags.shortcutDisplayTokens
        }
    }

    init(kind: Kind, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.kind = kind
        self.keyCode = keyCode
        let keyCodeForNormalization = kind == .key ? keyCode : nil
        self.modifierFlagsRawValue = Self.normalizedModifierFlags(
            modifierFlags,
            forKeyCode: keyCodeForNormalization
        ).rawValue
    }

    static func key(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Self {
        Self(kind: .key, keyCode: keyCode, modifierFlags: modifierFlags)
    }

    static func modifierOnly(keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) -> Self {
        Self(
            kind: .modifierOnly,
            keyCode: keyCode ?? Self.genericModifierKeyCode,
            modifierFlags: modifierFlags
        )
    }

    static var rightCommand: Self {
        .modifierOnly(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command])
    }

    static func fromLegacyShortcut(_ shortcut: LegacyKeyboardShortcut) -> Self {
        Self(
            kind: .key,
            keyCode: UInt16(shortcut.carbonKeyCode),
            modifierFlags: .shortcutFlags(fromCarbonModifiers: shortcut.carbonModifiers)
        )
    }

    func conflicts(with other: Shortcut) -> Bool {
        kind == other.kind &&
            keyCode == other.keyCode &&
            modifierFlags == other.modifierFlags
    }

    func matchesKeyEvent(keyCode eventKeyCode: UInt16, modifierFlags eventModifierFlags: NSEvent.ModifierFlags) -> Bool {
        kind == .key &&
            keyCode == eventKeyCode &&
            modifierFlags == Self.normalizedModifierFlags(eventModifierFlags, forKeyCode: eventKeyCode)
    }

    func matchesModifierEvent(keyCode eventKeyCode: UInt16, modifierFlags eventModifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard kind == .modifierOnly else {
            return false
        }

        let normalizedFlags = Self.normalizedModifierFlags(eventModifierFlags, forKeyCode: eventKeyCode)

        if keyCode == Self.genericModifierKeyCode {
            return normalizedFlags == modifierFlags
        }

        return keyCode == eventKeyCode && normalizedFlags == modifierFlags
    }

    func shouldReleaseModifierEvent(keyCode eventKeyCode: UInt16, modifierFlags eventModifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard kind == .modifierOnly else {
            return false
        }

        let normalizedFlags = Self.normalizedModifierFlags(eventModifierFlags, forKeyCode: eventKeyCode)

        if keyCode == Self.genericModifierKeyCode {
            return !normalizedFlags.isSuperset(of: modifierFlags)
        }

        return keyCode == eventKeyCode
    }

    func isInterruptedByAdditionalKeyDown(keyCode eventKeyCode: UInt16) -> Bool {
        switch kind {
        case .modifierOnly:
            return true
        case .key:
            return keyCode != eventKeyCode
        }
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    static func modifierKeyCodeForSingleModifierEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> UInt16? {
        guard modifiers.shortcutSingleModifierCount == 1, isModifierKeyCode(keyCode) else {
            return nil
        }

        return keyCode
    }

    static func normalizedModifierFlags(_ flags: NSEvent.ModifierFlags, forKeyCode keyCode: UInt16?) -> NSEvent.ModifierFlags {
        var normalizedFlags = flags.shortcutNormalized

        if let keyCode, isFunctionKeyCode(keyCode) {
            normalizedFlags.remove(.function)
        }

        return normalizedFlags
    }

    static func isFunctionKeyCode(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(keyCode)
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Function)
    ]

    private static let functionKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1),
        UInt16(kVK_F2),
        UInt16(kVK_F3),
        UInt16(kVK_F4),
        UInt16(kVK_F5),
        UInt16(kVK_F6),
        UInt16(kVK_F7),
        UInt16(kVK_F8),
        UInt16(kVK_F9),
        UInt16(kVK_F10),
        UInt16(kVK_F11),
        UInt16(kVK_F12),
        UInt16(kVK_F13),
        UInt16(kVK_F14),
        UInt16(kVK_F15),
        UInt16(kVK_F16),
        UInt16(kVK_F17),
        UInt16(kVK_F18),
        UInt16(kVK_F19),
        UInt16(kVK_F20)
    ]

    private static func sideSpecificModifierName(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        guard modifiers.shortcutSingleModifierCount == 1 else {
            return nil
        }

        switch keyCode {
        case UInt16(kVK_Shift):
            return "Left ⇧"
        case UInt16(kVK_RightShift):
            return "Right ⇧"
        case UInt16(kVK_Control):
            return "Left ⌃"
        case UInt16(kVK_RightControl):
            return "Right ⌃"
        case UInt16(kVK_Option):
            return "Left ⌥"
        case UInt16(kVK_RightOption):
            return "Right ⌥"
        case UInt16(kVK_Command):
            return "Left ⌘"
        case UInt16(kVK_RightCommand):
            return "Right ⌘"
        case UInt16(kVK_Function):
            return "Fn"
        default:
            return nil
        }
    }

    private static func keyName(for keyCode: UInt16) -> String {
        if let specialName = specialKeyNames[keyCode] {
            return specialName
        }

        if let layoutCharacter = characterForCurrentKeyboardLayout(keyCode: keyCode) {
            return layoutCharacter.uppercased()
        }

        return qwertyFallbackKeyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static func characterForCurrentKeyboardLayout(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
            UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else {
            return nil
        }

        let result = String(utf16CodeUnits: chars, count: length)
        guard !result.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }

        return result
    }

    private static let qwertyFallbackKeyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/"
    ]

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20",
        UInt16(kVK_ANSI_Keypad0): "Keypad 0",
        UInt16(kVK_ANSI_Keypad1): "Keypad 1",
        UInt16(kVK_ANSI_Keypad2): "Keypad 2",
        UInt16(kVK_ANSI_Keypad3): "Keypad 3",
        UInt16(kVK_ANSI_Keypad4): "Keypad 4",
        UInt16(kVK_ANSI_Keypad5): "Keypad 5",
        UInt16(kVK_ANSI_Keypad6): "Keypad 6",
        UInt16(kVK_ANSI_Keypad7): "Keypad 7",
        UInt16(kVK_ANSI_Keypad8): "Keypad 8",
        UInt16(kVK_ANSI_Keypad9): "Keypad 9",
        UInt16(kVK_ANSI_KeypadDecimal): "Keypad .",
        UInt16(kVK_ANSI_KeypadDivide): "Keypad /",
        UInt16(kVK_ANSI_KeypadMultiply): "Keypad *",
        UInt16(kVK_ANSI_KeypadMinus): "Keypad -",
        UInt16(kVK_ANSI_KeypadPlus): "Keypad +",
        UInt16(kVK_ANSI_KeypadEnter): "Keypad Enter",
        UInt16(kVK_ANSI_KeypadEquals): "Keypad ="
    ]
}

private extension NSEvent.ModifierFlags {
    static let shortcutRelevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function]

    var shortcutNormalized: NSEvent.ModifierFlags {
        intersection(Self.shortcutRelevant)
    }

    var shortcutDisplayTokens: [String] {
        var tokens: [String] = []

        if contains(.control) {
            tokens.append("⌃")
        }

        if contains(.option) {
            tokens.append("⌥")
        }

        if contains(.shift) {
            tokens.append("⇧")
        }

        if contains(.command) {
            tokens.append("⌘")
        }

        if contains(.function) {
            tokens.append("Fn")
        }

        return tokens
    }

    var shortcutSingleModifierCount: Int {
        [
            NSEvent.ModifierFlags.control,
            .option,
            .shift,
            .command,
            .function
        ].filter { contains($0) }.count
    }

    static func shortcutFlags(fromCarbonModifiers carbonModifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if carbonModifiers & Int(controlKey) != 0 {
            flags.insert(.control)
        }

        if carbonModifiers & Int(optionKey) != 0 {
            flags.insert(.option)
        }

        if carbonModifiers & Int(shiftKey) != 0 {
            flags.insert(.shift)
        }

        if carbonModifiers & Int(cmdKey) != 0 {
            flags.insert(.command)
        }

        if carbonModifiers & (1 << 17) != 0 {
            flags.insert(.function)
        }

        return flags
    }
}
