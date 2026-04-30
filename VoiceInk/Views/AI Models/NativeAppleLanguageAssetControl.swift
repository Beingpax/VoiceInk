import SwiftUI
import os

#if canImport(Speech)
import Speech
#endif

private enum NativeAppleSpeechAssetState: Equatable {
    case checking
    case downloaded
    case needsDownload
    case downloading
    case notSupported
    case assetManagementUnavailable
    case failed(String)
}

struct NativeAppleLanguageAssetControl: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleLanguageAssetControl")

    let localeIdentifier: String
    let isVisible: Bool

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
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 24)
                .help("Checking Apple Speech language download status.")
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
            .help("Download this Apple Speech language before transcribing.")
            .accessibilityLabel("Download Apple Speech language")
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 24)
                .help("Downloading Apple Speech language.")
        case .notSupported:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
                .help("This language is not supported by Apple Speech.")
        case .assetManagementUnavailable:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
                .help("Apple Speech asset management is not available on this system.")
        case .failed(let message):
            Button(action: downloadAsset) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(width: 28, height: 24)
            .help("Retry downloading this Apple Speech language. \(message)")
            .accessibilityLabel("Retry Apple Speech language download")
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
            let resolvedState = await assetState(for: localeIdentifier)

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
            let resolvedState = await installAsset(for: localeIdentifier)

            guard !Task.isCancelled else {
                return
            }

            state = resolvedState
        }
    }

    private func assetState(for localeIdentifier: String) async -> NativeAppleSpeechAssetState {
        guard #available(macOS 26, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let locale = Locale(identifier: localeIdentifier)
        let selectedIdentifier = locale.identifier(.bcp47)
        let supportedIdentifiers = await Set(SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })

        guard supportedIdentifiers.contains(selectedIdentifier) else {
            return .notSupported
        }

        let installedIdentifiers = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return installedIdentifiers.contains(selectedIdentifier) ? .downloaded : .needsDownload
        #else
        return .assetManagementUnavailable
        #endif
    }

    private func installAsset(for localeIdentifier: String) async -> NativeAppleSpeechAssetState {
        guard #available(macOS 26, *) else {
            logger.error("Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': requires macOS 26 or later.")
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        do {
            let locale = Locale(identifier: localeIdentifier)
            let normalizedIdentifier = locale.identifier(.bcp47)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )

            let reservedLocales = await AssetInventory.reservedLocales
            for reservedLocale in reservedLocales {
                await AssetInventory.release(reservedLocale: reservedLocale)
            }

            let reserved = try await AssetInventory.reserve(locale: locale)

            guard reserved else {
                logger.error("Apple Speech asset reservation returned false for '\(normalizedIdentifier, privacy: .public)'.")
                return .failed("Could not reserve Apple Speech assets for \(normalizedIdentifier).")
            }

            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return await assetState(for: localeIdentifier)
            }

            try await request.downloadAndInstall()
            return await assetState(for: localeIdentifier)
        } catch {
            logger.error("Apple Speech asset download failed for '\(localeIdentifier, privacy: .public)': \(error.localizedDescription, privacy: .public).")
            return .failed(error.localizedDescription)
        }
        #else
        logger.error("Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': ENABLE_NATIVE_SPEECH_ANALYZER is not active.")
        return .assetManagementUnavailable
        #endif
    }
}
