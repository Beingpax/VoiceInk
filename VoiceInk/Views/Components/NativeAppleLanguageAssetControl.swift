import SwiftUI

struct NativeAppleLanguageAssetControl: View {
    let localeIdentifier: String
    let isVisible: Bool
    let startsDownloadAutomatically: Bool
    let allowsReservationReplacement: Bool

    init(
        localeIdentifier: String,
        isVisible: Bool,
        startsDownloadAutomatically: Bool = false,
        allowsReservationReplacement: Bool = false
    ) {
        self.localeIdentifier = localeIdentifier
        self.isVisible = isVisible
        self.startsDownloadAutomatically = startsDownloadAutomatically
        self.allowsReservationReplacement = allowsReservationReplacement
    }

    @State private var state: NativeAppleSpeechAssetState = .checking
    @State private var refreshTask: Task<Void, Never>?
    @State private var showReservationLimitPopover = false

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
        .onChange(of: state) { _, newState in
            if case .reservationLimitReached = newState, allowsReservationReplacement {
                showReservationLimitPopover = true
            } else {
                showReservationLimitPopover = false
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
            showReservationLimitPopover = false
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
            if allowsReservationReplacement {
                Button {
                    showReservationLimitPopover = true
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .frame(width: 28, height: 24)
                .popover(isPresented: $showReservationLimitPopover) {
                    reservationLimitPopover
                }
            } else {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 24)
            }
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
            if allowsReservationReplacement {
                return String(
                    localized:
                        "Apple Speech can reserve up to 5 languages. Choose one to remove before downloading the selected language."
                )
            }
            return String(
                localized: "Apple Speech can reserve up to 5 languages. Manage reserved languages in Mode settings.")
        case .failed(let message):
            return String(
                format: String(localized: "Apple Speech language download failed: %@"),
                message
            )
        }
    }

    private var reservationLimitPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Language to Remove")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(
                    String(
                        format: String(localized: "Remove one reserved language to download %@."), selectedLanguageName)
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            let reservedLocaleIdentifiers = reservationLimitLocaleIdentifiers
            if reservedLocaleIdentifiers.isEmpty {
                Text("No removable language reservations were found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 3) {
                    ForEach(reservedLocaleIdentifiers, id: \.self) { identifier in
                        reservationLimitRow(for: identifier)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func reservationLimitRow(for identifier: String) -> some View {
        Button {
            releaseReservationAndRetry(identifier)
        } label: {
            HStack(spacing: 8) {
                Text(languageDisplayName(for: identifier))
                    .lineLimit(1)

                Spacer(minLength: 10)

                Image(systemName: "minus.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            String(
                format: String(localized: "Remove %@ from reserved Apple Speech languages."),
                languageDisplayName(for: identifier)))
    }

    private var reservationLimitLocaleIdentifiers: [String] {
        guard case .reservationLimitReached(let identifiers) = state else {
            return []
        }

        return identifiers
    }

    private var selectedLanguageName: String {
        languageDisplayName(for: localeIdentifier)
    }

    private func languageDisplayName(for localeIdentifier: String) -> String {
        NativeAppleSpeechAssetManager.languageDisplayName(for: localeIdentifier)
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

            if startsDownloadAutomatically && (resolvedState == .needsDownload || resolvedState == .downloading) {
                state = .downloading
                let installedState = await NativeAppleSpeechAssetManager.installAsset(for: localeIdentifier)

                guard !Task.isCancelled else {
                    return
                }

                state = installedState
                return
            }

            state = resolvedState
        }
    }

    private func releaseReservationAndRetry(_ reservedLocaleIdentifier: String) {
        guard #available(macOS 26, *) else {
            state = .assetManagementUnavailable
            return
        }

        let localeIdentifier = localeIdentifier
        state = .downloading
        showReservationLimitPopover = false
        refreshTask?.cancel()

        refreshTask = Task {
            let released = await NativeAppleSpeechAssetManager.releaseReservedLocale(
                reservedLocaleIdentifier,
                toMakeRoomFor: localeIdentifier
            )

            guard !Task.isCancelled else {
                return
            }

            guard released else {
                state = .failed(
                    String(
                        format: String(localized: "Could not remove %@ from reserved Apple Speech languages."),
                        languageDisplayName(for: reservedLocaleIdentifier)
                    )
                )
                return
            }

            let resolvedState = await NativeAppleSpeechAssetManager.installAsset(for: localeIdentifier)

            guard !Task.isCancelled else {
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
