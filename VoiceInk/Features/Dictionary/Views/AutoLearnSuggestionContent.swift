import AppKit
import SwiftUI

struct AutoLearnSuggestionContent: View {
    let originalText: String?
    let correctedText: String
    let secondsRemaining: Int
    var dismissalDeadline: ContinuousClock.Instant?
    var dismissalSeconds = 10
    var isApplying = false
    var isValid = true
    var errorMessage: String?
    let onApprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Learn this correction?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if let originalText {
                    ViewThatFits(in: .vertical) {
                        originalTerms(originalText)
                        ScrollView {
                            originalTerms(originalText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 104)
                    }
                    .frame(maxHeight: 104, alignment: .topLeading)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if originalText != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Replace with")
                    }
                    Text(correctedText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 12)
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.bordered)
                Button(action: onApprove) {
                    Text("Add Correction")
                        .frame(minWidth: 104)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .environment(\.controlActiveState, .key)
                .disabled(!isValid)
            }
            .font(.system(size: 13, weight: .medium))
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .disabled(isApplying)
        }
        .padding(16)
        .frame(width: 400)
        .modifier(AutoLearnSuggestionSurface())
        .overlay(alignment: .bottom) {
            AutoLearnCountdownView(
                secondsRemaining: secondsRemaining,
                dismissalSeconds: dismissalSeconds,
                deadline: dismissalDeadline
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func originalTerms(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AutoLearnSuggestionSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background {
                AutoLearnSuggestionBackdrop()
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct AutoLearnSuggestionBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct AutoLearnCountdownView: View {
    let secondsRemaining: Int
    let dismissalSeconds: Int
    let deadline: ContinuousClock.Instant?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || deadline == nil || secondsRemaining == 0)) { _ in
            let remainingProgress = progress
            GeometryReader { geometry in
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.primary.opacity(0.4))
                            .frame(width: geometry.size.width * remainingProgress)
                    }
            }
        }
        .transaction { $0.animation = nil }
        .frame(height: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dismisses automatically")
        .accessibilityValue(Text(Duration.seconds(max(0, secondsRemaining)).formatted(.units(allowed: [.seconds]))))
    }

    private var progress: CGFloat {
        AutoLearnCountdownProgress.value(secondsRemaining: secondsRemaining, dismissalSeconds: dismissalSeconds,
            deadline: deadline, reduceMotion: reduceMotion)
    }
}

enum AutoLearnCountdownProgress {
    static func value(secondsRemaining: Int, dismissalSeconds: Int, deadline: ContinuousClock.Instant?,
        reduceMotion: Bool, now: ContinuousClock.Instant = ContinuousClock().now) -> CGFloat {
        let remainingSeconds: Double
        if !reduceMotion, let deadline {
            let remaining = now.duration(to: deadline).components
            remainingSeconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        } else {
            remainingSeconds = Double(secondsRemaining)
        }
        return CGFloat(min(1, max(0, remainingSeconds / Double(max(1, dismissalSeconds)))))
    }
}
