import SwiftUI

struct ShortcutPreviewView: View {
    private let components: [String]?
    @Environment(\.colorScheme) private var colorScheme

    init(shortcut: Shortcut?) {
        self.components = shortcut?.displayTokens
    }

    var body: some View {
        if let components, !components.isEmpty {
            HStack(spacing: 6) {
                ForEach(components, id: \.self) { component in
                    KeyCapView(text: component)
                }
            }
        } else {
            KeyCapView(text: String(localized: "Not Set"))
                .foregroundColor(.secondary)
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
                keyColor.opacity(0.2),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.15 : 0.5),
                .white.opacity(0.0),
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
                                    shadowColor.opacity(0.3),
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
                                shadowColor.opacity(0.9),
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
        ShortcutPreviewView(shortcut: ShortcutStore.shortcut(for: .primaryRecording))
        ShortcutPreviewView(shortcut: nil)
    }
    .padding()
}
