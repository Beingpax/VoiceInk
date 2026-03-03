import SwiftUI
import KeyboardShortcuts

struct KeyboardShortcutView: View {
    let shortcut: KeyboardShortcuts.Shortcut?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if let shortcut = shortcut {
            HStack(spacing: 6) {
                ForEach(shortcutComponents(from: shortcut), id: \.self) { component in
                    KeyCapView(text: component)
                }
            }
        } else {
            KeyCapView(text: "Not Set")
                .foregroundColor(.secondary)
        }
    }
    
    private func shortcutComponents(from shortcut: KeyboardShortcuts.Shortcut) -> [String] {
        var components: [String] = []
        
        // Add modifiers
        if shortcut.modifiers.contains(.command) { components.append("⌘") }
        if shortcut.modifiers.contains(.option) { components.append("⌥") }
        if shortcut.modifiers.contains(.shift) { components.append("⇧") }
        if shortcut.modifiers.contains(.control) { components.append("⌃") }
        
        // Add key
        if let key = shortcut.key {
            components.append(keyToString(key))
        }
        
        return components
    }
    
    private func keyToString(_ key: KeyboardShortcuts.Key) -> String {
        switch key {
        case .space: return "Space"
        case .return: return "↩"
        case .escape: return "⎋"
        case .tab: return "⇥"
        case .delete: return "⌫"
        case .home: return "↖"
        case .end: return "↘"
        case .pageUp: return "⇞"
        case .pageDown: return "⇟"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .period: return "."
        case .comma: return ","
        case .semicolon: return ";"
        case .quote: return "'"
        case .slash: return "/"
        case .backslash: return "\\"
        case .minus: return "-"
        case .equal: return "="
        case .keypad0: return "0"
        case .keypad1: return "1"
        case .keypad2: return "2"
        case .keypad3: return "3"
        case .keypad4: return "4"
        case .keypad5: return "5"
        case .keypad6: return "6"
        case .keypad7: return "7"
        case .keypad8: return "8"
        case .keypad9: return "9"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        default:
              return String(key.rawValue).uppercased()
        }
    }
}

struct KeyCapView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    private var keyColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : .white
    }
    
    private var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [
                keyColor,
                keyColor.opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.15 : 0.5),
                .white.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .center
        )
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? .black : .gray
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 25, weight: .semibold, design: .rounded))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    // Main key surface
                    RoundedRectangle(cornerRadius: 8)
                        .fill(surfaceGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(highlightGradient)
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.2 : 0.6),
                                    shadowColor.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            // Main shadow
            .shadow(
                color: shadowColor.opacity(0.3),
                radius: 3,
                x: 0,
                y: 2
            )
            // Bottom edge shadow
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                shadowColor.opacity(0.0),
                                shadowColor.opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: 1)
                    .blur(radius: 2)
                    .mask(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .black],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .clipped()
            )
            // Inner shadow effect
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                        lineWidth: 1
                    )
                    .blur(radius: 1)
                    .offset(x: -1, y: -1)
                    .mask(RoundedRectangle(cornerRadius: 8))
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .onTapGesture {
                withAnimation {
                    isPressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPressed = false
                    }
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        KeyboardShortcutView(shortcut: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder))
        KeyboardShortcutView(shortcut: nil)
    }
    .padding()
} 
