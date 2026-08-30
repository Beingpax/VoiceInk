import SwiftUI

struct NativeAppleLanguageAssetControl: View {
    let localeIdentifier: String
    let isVisible: Bool
    let startsDownloadAutomatically: Bool

    init(
        localeIdentifier: String,
        isVisible: Bool,
        startsDownloadAutomatically: Bool = false
    ) {
        self.localeIdentifier = localeIdentifier
        self.isVisible = isVisible
        self.startsDownloadAutomatically = startsDownloadAutomatically
    }

    @State private var state: NativeAppleSpeechAssetState = .checking
    @State private var refreshTask: Task<Void, Never>?

    private var refreshKey: String {
        "\(isVisible)-\(localeIdentifier)"
    }

    var body: some View {
        Group {
            if isVisible {
                content
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: refreshKey, initial: true) { _, _ in
            refreshAssetState()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        statusView
            .contentShape(Rectangle())
            .help(helpText)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 24)
        case .downloaded:
            EmptyView()
        case .needsDownload:
            Button(action: downloadAsset) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(width: 28, height: 24)
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 24)
        case .notSupported:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
        case .assetManagementUnavailable:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
        case .reservationLimitReached:
            Button(action: refreshAssetState) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(width: 28, height: 24)
        case .failed(let message):
            Button(action: downloadAsset) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(width: 28, height: 24)
        }
    }

    private var helpText: String {
        switch state {
        case .checking:
            return String(localized: "Checking whether this Apple Speech language is downloaded.")
        case .downloaded:
            return String(localized: "Apple Speech language is downloaded.")
        case .needsDownload:
            return String(localized: "Download this Apple Speech language.")
        case .downloading:
            return String(localized: "Downloading assets for the selected Apple Speech language.")
        case .notSupported:
            return String(localized: "Apple Speech does not support this language.")
        case .assetManagementUnavailable:
            return String(localized: "Apple Speech language downloads are not available on this system.")
        case .reservationLimitReached:
            return String(localized: "Apple Speech could not replace a language reservation automatically. Try again.")
        case .failed(let message):
            return String(
                format: String(localized: "Apple Speech language download failed: %@"),
                message
            )
        }
    }

    private func refreshAssetState() {
        guard isVisible else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }

        let localeIdentifier = localeIdentifier
        state = .checking
        refreshTask?.cancel()
        refreshTask = Task {
            let resolvedState = await NativeAppleSpeechAssetManager.assetState(for: localeIdentifier)

            guard !Task.isCancelled else {
                return
            }

            if startsDownloadAutomatically
                && (resolvedState == .downloaded || resolvedState == .needsDownload || resolvedState == .downloading)
            {
                state = resolvedState == .downloaded ? .checking : .downloading
                let preparedState = await NativeAppleSpeechAssetManager.prepareAssetForUse(for: localeIdentifier)

                guard !Task.isCancelled else {
                    return
                }

                state = preparedState
                return
            }

            state = resolvedState
        }
    }

    private func downloadAsset() {
        let localeIdentifier = localeIdentifier
        state = .downloading
        refreshTask?.cancel()

        refreshTask = Task {
            let resolvedState = await NativeAppleSpeechAssetManager.installAsset(for: localeIdentifier)

            guard !Task.isCancelled else {
                return
            }

            state = resolvedState
        }
    }
}
