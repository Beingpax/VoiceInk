import SwiftUI

/// What the ambient light is saying, when light alone cannot say it.
///
/// Three things genuinely need words: an instruction you must act on, a decision about what leaves
/// your machine, and a result you might want to take back. Everything else the glow already covers.
enum AmbientCaptionKind: Equatable {
    case problem(String)
    case context(String)
    case countdown(Int)
    case result(RecorderResultPeek)

    var isInteractive: Bool {
        if case .result = self { return true }
        if case .countdown = self { return true }
        return false
    }
}

/// The panel for ambient mode — deliberately not a panel.
///
/// A capsule with a border and a fill would just be the mini recorder wearing a glow, and would
/// undo the entire premise: ambient exists so there is no chrome sitting on top of your work. So
/// this has **no container at all**. It is illuminated text hanging under the notch, lit by the
/// same light the border is made of — as though the halo condensed enough to be read.
///
/// Three rules keep it from drifting back into being a panel:
///   * no fill, no border, no shadow — only a soft bloom behind the glyphs
///   * it inherits the ambient state colour rather than owning one
///   * it grows out of the notch, so it reads as the light thickening rather than a window opening
struct AmbientCaption: View {
    let kind: AmbientCaptionKind
    let tint: Color
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onKeepRecording: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            content
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(bloom)
        .fixedSize()
    }

    /// Light behind the words rather than a surface under them. An ellipse blurred well past its
    /// own bounds has no discernible edge, which is what stops it becoming a container.
    private var bloom: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.55))
                .blur(radius: 26)
                .padding(-14)

            Ellipse()
                .fill(tint.opacity(0.16))
                .blur(radius: 22)
                .padding(-6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .problem(let message):
            captionText(message, weight: .medium)

        case .context(let message):
            captionText(message, weight: .regular)

        case .countdown(let seconds):
            captionText(
                String(format: String(localized: "Silent — stopping in %lld"), Int64(seconds)),
                weight: .medium
            )
            AmbientCaptionButton(title: "Keep recording", tint: tint, action: onKeepRecording)

        case .result(let peek):
            Text(peek.pastedText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 460)
                .shadow(color: tint.opacity(0.5), radius: 9)

            HStack(spacing: 14) {
                Text(peek.duration.formatTiming())
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.4))

                AmbientCaptionButton(title: "Undo", tint: tint, action: onUndo)
                AmbientCaptionButton(title: "Retry", tint: tint, action: onRetry)
            }
        }
    }

    private func captionText(_ message: String, weight: Font.Weight) -> some View {
        Text(message)
            .font(.system(size: 12.5, weight: weight))
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: tint.opacity(0.65), radius: 10)
            .lineLimit(1)
    }
}

/// Text that happens to be tappable. No capsule, no fill — an underline on hover is enough to say
/// it is a control, and anything more would start rebuilding the panel this design removes.
private struct AmbientCaptionButton: View {
    let title: LocalizedStringKey
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
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
