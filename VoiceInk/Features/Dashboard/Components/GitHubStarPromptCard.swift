import SwiftUI

struct GitHubStarPromptCard: View {
    let isBusy: Bool
    let completionState: GitHubStarPromptCoordinator.CompletionState
    let openFailed: Bool
    let onStar: () -> Void
    let onLater: () -> Void

    private var isLocked: Bool { isBusy || completionState != .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if completionState == .none {
                askContent
                    .transition(.opacity)
            } else {
                completionContent
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.Border.card, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.2), value: completionState)
    }

    private var askContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Help people discover VoiceInk")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text("If VoiceInk has been useful, a star on GitHub helps others find it.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button(action: onStar) {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        } else {
                            Image(systemName: openFailed ? "exclamationmark.triangle.fill" : "star")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(openFailed ? .orange : .primary)
                        }

                        Text(openFailed ? "Couldn't open — try again" : "Star on GitHub")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .animation(.easeInOut(duration: 0.15), value: openFailed)

                Button(action: onLater) {
                    Text("Later")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .disabled(isLocked)

                Spacer(minLength: 0)
            }
        }
    }

    private var completionContent: some View {
        HStack(spacing: 8) {
            Image(systemName: completionState == .starred ? "checkmark.circle.fill" : "arrow.up.right.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(completionState == .starred ? AppTheme.Sidebar.license : .secondary)

            Text(completionState == .starred ? "Starred — thank you!" : "GitHub opened")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    // A frosted, elevated material so the card reads as floating above the Dashboard, not blending into it.
    private var cardBackground: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .withinWindow)
            AppTheme.Surface.materialCard
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
