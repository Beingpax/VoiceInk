import SwiftUI

/// Soft dark backing for text that has to stay readable over whatever is on screen.
///
/// Not a container — it has no edge. An ellipse blurred well past its own bounds gives contrast
/// without ever resolving into a shape, which is the line this whole surface walks: legible enough
/// to read, formless enough not to be a panel.
struct AmbientTextBloom: ViewModifier {
    var tint: Color = .clear
    var opacity: Double = 0.55

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Ellipse()
                        .fill(Color.black.opacity(opacity))
                        .blur(radius: 26)
                        .padding(-14)

                    Ellipse()
                        .fill(tint.opacity(0.14))
                        .blur(radius: 22)
                        .padding(-6)
                }
            }
    }
}

extension View {
    func ambientTextBloom(tint: Color = .clear, opacity: Double = 0.55) -> some View {
        modifier(AmbientTextBloom(tint: tint, opacity: opacity))
    }
}

/// The facts about the take in progress, and the one action that is not a keyboard shortcut.
///
/// Four things the panel shows and ambient did not: how long you have been talking, whether the
/// text will be enhanced before it lands, which microphone is being used, and a way out. All four
/// are state you cannot otherwise discover without stopping — and the enhancement one changes what
/// comes out of the take, which makes it the most consequential thing that used to be invisible.
///
/// It reads as one sentence of small type rather than a row of controls, because a row of controls
/// is a toolbar, and a toolbar is the thing this surface exists to avoid.
struct AmbientTakeBar: View {
    let elapsed: TimeInterval
    let isEnhancementEnabled: Bool
    /// Named only when the input is failing — a quiet or dead mic is usually the wrong device, and
    /// the rest of the time the name is noise.
    let deviceName: String?
    let tint: Color
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(clock)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))

            separator

            Label {
                Text(isEnhancementEnabled ? "Enhanced" : "Raw")
            } icon: {
                Image(systemName: isEnhancementEnabled ? "sparkles" : "text.alignleft")
            }
            .font(.system(size: 10.5, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isEnhancementEnabled ? tint : Color.white.opacity(0.6))

            if let deviceName {
                separator
                Text(deviceName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            separator

            AmbientTextButton(title: "⎋ Cancel", tint: tint, action: onCancel)
        }
        .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
    }

    private var clock: String {
        let total = Int(elapsed.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var separator: some View {
        Circle()
            .fill(Color.white.opacity(0.28))
            .frame(width: 2.5, height: 2.5)
    }
}

/// Text that happens to be tappable. An underline on hover is enough to say it is a control, and
/// anything more starts rebuilding the panel this design removes.
struct AmbientTextButton: View {
    let title: LocalizedStringKey
    let tint: Color
    var weight: Font.Weight = .semibold
    var size: CGFloat = 11
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.7), radius: isHovering ? 10 : 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(tint.opacity(isHovering ? 0.8 : 0))
                        .frame(height: 1)
                        .offset(y: 3)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AppTheme.Motion.quick, value: isHovering)
    }
}
