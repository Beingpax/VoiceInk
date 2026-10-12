import AppKit
import SwiftUI

struct ChangeLogView: View {
    let item: ChangeLogItem
    let appVersion: String
    let onDismiss: () -> Void
    let onWatchVideo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnEnabled = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .accessibilityHidden(true)

            changeLogCard
                .padding(24)
        }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.97))
        )
        .accessibilityAddTraits(.isModal)
    }

    private var changeLogCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            videoPreview
                .padding(.top, 22)

            description
                .padding(.top, 16)

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 680)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Surface.window)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Border.card, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("What's New")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text("VoiceInk \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close What's New",
                size: 30,
                iconSize: 13,
                cornerRadius: 15,
                action: onDismiss
            )
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var videoPreview: some View {
        AsyncImage(url: item.previewImageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .empty:
                previewPlaceholder {
                    ProgressView()
                        .controlSize(.small)
                }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                previewPlaceholder {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(AppTheme.Text.secondary)
                }
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var description: some View {
        Text(item.summary)
            .font(.system(size: 14))
            .foregroundStyle(AppTheme.Text.primary.opacity(0.72))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Toggle("Auto-Learn Dictionary", isOn: $isAutoLearnEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13, weight: .medium))
                .onChange(of: isAutoLearnEnabled) { _, isEnabled in
                    Task {
                        await AutoLearnService.shared.settingDidChange(isEnabled: isEnabled)
                    }
                }

            Spacer()

            AppActionButton(
                "Watch video",
                kind: .primary,
                minWidth: 112,
                action: onWatchVideo
            )
        }
    }

    private func previewPlaceholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.black.opacity(0.88)
            content()
        }
    }
}

private struct ChangeLogPresenter: ViewModifier {
    @ObservedObject var manager: ChangeLogManager

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item = manager.presentedItem {
                    ChangeLogView(
                        item: item,
                        appVersion: appVersion,
                        onDismiss: manager.dismiss,
                        onWatchVideo: {
                            if let videoURL = item.videoURL {
                                NSWorkspace.shared.open(videoURL)
                            }
                            manager.dismiss()
                        }
                    )
                }
            }
            .animation(.easeOut(duration: 0.2), value: manager.isPresenting)
    }
}

private struct LazyChangeLogPresenter<PresentedContent: View>: View {
    @StateObject private var manager = ChangeLogManager()

    let content: PresentedContent
    let onPresentationChanged: (Bool) -> Void

    var body: some View {
        content
            .changeLogPresenter(manager: manager)
            .task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                manager.presentIfNeeded()
                onPresentationChanged(manager.isPresenting)
            }
            .onChange(of: manager.isPresenting) { _, isPresenting in
                onPresentationChanged(isPresenting)
            }
    }
}

private struct LazyChangeLogModifier: ViewModifier {
    let shouldCreateManager: Bool
    let onPresentationChanged: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if shouldCreateManager {
            LazyChangeLogPresenter(
                content: content,
                onPresentationChanged: onPresentationChanged
            )
        } else {
            content
        }
    }
}

extension View {
    func changeLogPresenter(manager: ChangeLogManager) -> some View {
        modifier(ChangeLogPresenter(manager: manager))
    }

    func lazyChangeLogPresenter(
        onPresentationChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            LazyChangeLogModifier(
                shouldCreateManager: ChangeLogManager.needsPresentation(),
                onPresentationChanged: onPresentationChanged
            )
        )
    }
}
