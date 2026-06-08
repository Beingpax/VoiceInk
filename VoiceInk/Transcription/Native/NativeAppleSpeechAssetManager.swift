import Foundation
import os

#if canImport(Speech)
import Speech
#endif

enum NativeAppleSpeechAssetState: Equatable {
    case checking
    case downloaded
    case needsDownload
    case downloading
    case notSupported
    case assetManagementUnavailable
    case reservationLimitReached([String])
    case failed(String)
}

enum NativeAppleSpeechAssetManager {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleSpeechAssetManager")

    static func assetState(for localeIdentifier: String) async -> NativeAppleSpeechAssetState {
        guard #available(macOS 26, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        guard let context = await assetContext(for: localeIdentifier) else {
            return .notSupported
        }

        return context.state
        #else
        return .assetManagementUnavailable
        #endif
    }

    static func installAsset(for localeIdentifier: String) async -> NativeAppleSpeechAssetState {
        guard #available(macOS 26, *) else {
            logger.error("Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': requires macOS 26 or later.")
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        do {
            guard let context = await assetContext(for: localeIdentifier) else {
                return .notSupported
            }

            return try await installAssetOnce(for: context)
        } catch {
            if isReservationLimitError(error) {
                let reservedLocales = await reservedLocaleIdentifiers(excluding: localeIdentifier)
                logger.warning("Apple Speech asset download hit locale reservation limit for '\(localeIdentifier, privacy: .public)'. Waiting for user to release a reservation.")
                return .reservationLimitReached(reservedLocales)
            }

            logger.error("Apple Speech asset download failed for '\(localeIdentifier, privacy: .public)': \(error.localizedDescription, privacy: .public).")
            return .failed(error.localizedDescription)
        }
        #else
        logger.error("Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': ENABLE_NATIVE_SPEECH_ANALYZER is not active.")
        return .assetManagementUnavailable
        #endif
    }

    static func reservedLocaleIdentifiers(excluding localeIdentifier: String? = nil) async -> [String] {
        guard #available(macOS 26, *) else {
            return []
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let requestedIdentifier: String?
        if let localeIdentifier {
            requestedIdentifier = await supportedLocale(for: localeIdentifier)?.identifier(.bcp47)
                ?? Locale(identifier: localeIdentifier).identifier(.bcp47)
        } else {
            requestedIdentifier = nil
        }

        return await AssetInventory.reservedLocales
            .map { $0.identifier(.bcp47) }
            .filter { identifier in
                if let requestedIdentifier {
                    return identifier != requestedIdentifier
                }
                return true
            }
            .sorted {
                languageDisplayName(for: $0) < languageDisplayName(for: $1)
            }
        #else
        return []
        #endif
    }

    static func releaseReservedLocale(
        _ localeIdentifier: String,
        toMakeRoomFor requestedLocaleIdentifier: String
    ) async -> Bool {
        guard #available(macOS 26, *) else {
            return false
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let normalizedIdentifier = await supportedLocale(for: localeIdentifier)?.identifier(.bcp47)
            ?? Locale(identifier: localeIdentifier).identifier(.bcp47)
        let requestedIdentifier = await supportedLocale(for: requestedLocaleIdentifier)?.identifier(.bcp47)
            ?? Locale(identifier: requestedLocaleIdentifier).identifier(.bcp47)

        guard let localeToRelease = await AssetInventory.reservedLocales.first(where: {
            $0.identifier(.bcp47) == normalizedIdentifier
        }) else {
            logger.warning("Apple Speech locale reservation '\(normalizedIdentifier, privacy: .public)' could not be found while making room for '\(requestedIdentifier, privacy: .public)'.")
            return false
        }

        let released = await AssetInventory.release(reservedLocale: localeToRelease)

        if !released {
            logger.warning("Apple Speech failed to release locale reservation '\(normalizedIdentifier, privacy: .public)' while making room for '\(requestedIdentifier, privacy: .public)'.")
        }

        return released
        #else
        return false
        #endif
    }

    static func languageDisplayName(for localeIdentifier: String) -> String {
        LanguageDictionary.appleNative[localeIdentifier]
            ?? Locale.current.localizedString(forIdentifier: localeIdentifier)
            ?? localeIdentifier
    }

    #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
    @available(macOS 26, *)
    struct AssetContext {
        let locale: Locale
        let localeIdentifier: String
        let displayName: String
        let transcriber: SpeechTranscriber
        let status: AssetInventory.Status

        var state: NativeAppleSpeechAssetState {
            NativeAppleSpeechAssetManager.assetState(for: status)
        }
    }

    @available(macOS 26, *)
    static func assetContext(for localeIdentifier: String) async -> AssetContext? {
        guard let supportedLocale = await supportedLocale(for: localeIdentifier) else {
            return nil
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let resolvedIdentifier = supportedLocale.identifier(.bcp47)
        let status = await AssetInventory.status(forModules: [transcriber])

        return AssetContext(
            locale: supportedLocale,
            localeIdentifier: resolvedIdentifier,
            displayName: languageDisplayName(for: resolvedIdentifier),
            transcriber: transcriber,
            status: status
        )
    }

    @available(macOS 26, *)
    private static func installAssetOnce(
        for context: AssetContext
    ) async throws -> NativeAppleSpeechAssetState {
        if context.status == .installed || context.status == .unsupported {
            return context.state
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [context.transcriber]) else {
            return await assetState(for: context.localeIdentifier)
        }

        try await request.downloadAndInstall()
        return await assetState(for: context.localeIdentifier)
    }

    @available(macOS 26, *)
    static func reserveLocaleIfNeeded(for context: AssetContext) async -> Bool {
        let reservedLocales = await AssetInventory.reservedLocales
        guard !reservedLocales.contains(where: { $0.identifier(.bcp47) == context.localeIdentifier }) else { return true }

        do {
            let reserved = try await AssetInventory.reserve(locale: context.locale)

            guard reserved else {
                let finalStatus = await AssetInventory.status(forModules: [context.transcriber])
                logger.warning("Apple Speech asset reservation returned false for '\(context.localeIdentifier, privacy: .public)'. Continuing because the locale is already downloaded. Status: \(String(describing: finalStatus), privacy: .public).")
                return true
            }

            return true
        } catch {
            let finalStatus = await AssetInventory.status(forModules: [context.transcriber])

            if isReservationLimitError(error) {
                logger.warning("Apple Speech reservation limit reached for '\(context.localeIdentifier, privacy: .public)'. User must release a reserved language in settings. Status: \(String(describing: finalStatus), privacy: .public).")
            } else {
                logger.warning("Apple Speech asset reservation failed for '\(context.localeIdentifier, privacy: .public)': \(error.localizedDescription, privacy: .public). Status: \(String(describing: finalStatus), privacy: .public).")
            }

            return false
        }
    }

    @available(macOS 26, *)
    private static func supportedLocale(for localeIdentifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
    }

    @available(macOS 26, *)
    private static func isReservationLimitError(_ error: Error) -> Bool {
        let message = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return message.contains("too many")
            && message.contains("locale")
            && (message.contains("allocated") || message.contains("reserved") || message.contains("maximum"))
    }

    @available(macOS 26, *)
    private static func assetState(for status: AssetInventory.Status) -> NativeAppleSpeechAssetState {
        switch status {
        case .installed:
            return .downloaded
        case .supported:
            return .needsDownload
        case .downloading:
            return .downloading
        case .unsupported:
            return .notSupported
        @unknown default:
            return .failed("Unknown Apple Speech asset status: \(String(describing: status))")
        }
    }
    #endif
}
