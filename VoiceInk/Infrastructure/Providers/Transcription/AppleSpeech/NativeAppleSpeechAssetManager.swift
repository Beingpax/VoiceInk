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
    case reservationLimitReached
    case failed(String)
}

enum NativeAppleSpeechAssetManager {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleSpeechAssetManager")

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
            logger.error(
                "Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': requires macOS 26 or later."
            )
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
                    if await releaseOneReservation(toMakeRoomFor: localeIdentifier) {
                        do {
                            guard let retryContext = await assetContext(for: localeIdentifier) else {
                                return .notSupported
                            }

                            return try await installAssetOnce(for: retryContext)
                        } catch {
                            if !isReservationLimitError(error) {
                                return .failed(error.localizedDescription)
                            }
                        }
                    }

                    logger.warning(
                        "Apple Speech asset download still requires reservation replacement for '\(localeIdentifier, privacy: .public)'."
                    )
                    return .reservationLimitReached
                }

                logger.error(
                    "Apple Speech asset download failed for '\(localeIdentifier, privacy: .public)': \(error, privacy: .public)."
                )
                return .failed(error.localizedDescription)
            }
        #else
            logger.error(
                "Apple Speech asset download unavailable for '\(localeIdentifier, privacy: .public)': ENABLE_NATIVE_SPEECH_ANALYZER is not active."
            )
            return .assetManagementUnavailable
        #endif
    }

    static func prepareAssetForUse(for localeIdentifier: String) async -> NativeAppleSpeechAssetState {
        let installedState = await installAsset(for: localeIdentifier)
        guard installedState == .downloaded else {
            return installedState
        }

        guard #available(macOS 26, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
            guard let context = await assetContext(for: localeIdentifier) else {
                return .notSupported
            }

            guard await reserveLocaleIfNeeded(for: context) else {
                return .reservationLimitReached
            }

            return .downloaded
        #else
            return .assetManagementUnavailable
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
            let isInstalled: Bool

            var state: NativeAppleSpeechAssetState {
                if isInstalled {
                    return .downloaded
                }

                return NativeAppleSpeechAssetManager.assetState(for: status)
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
            let installedLocales = await SpeechTranscriber.installedLocales
            let isInstalled = installedLocales.contains {
                $0.identifier(.bcp47) == resolvedIdentifier
            }

            // Prefer installedLocales because AssetInventory status can become stale.
            let status: AssetInventory.Status
            if isInstalled {
                status = .installed
            } else {
                status = await AssetInventory.status(forModules: [transcriber])
            }

            return AssetContext(
                locale: supportedLocale,
                localeIdentifier: resolvedIdentifier,
                displayName: languageDisplayName(for: resolvedIdentifier),
                transcriber: transcriber,
                status: status,
                isInstalled: isInstalled
            )
        }

        @available(macOS 26, *)
        private static func installAssetOnce(
            for context: AssetContext
        ) async throws -> NativeAppleSpeechAssetState {
            if context.isInstalled || context.status == .unsupported {
                return context.state
            }

            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [context.transcriber])
            else {
                return await assetState(for: context.localeIdentifier)
            }

            try await request.downloadAndInstall()
            return await assetState(for: context.localeIdentifier)
        }

        @available(macOS 26, *)
        static func reserveLocaleIfNeeded(for context: AssetContext) async -> Bool {
            let reservedLocales = await AssetInventory.reservedLocales
            guard !reservedLocales.contains(where: { $0.identifier(.bcp47) == context.localeIdentifier }) else {
                return true
            }

            do {
                let reserved = try await AssetInventory.reserve(locale: context.locale)

                guard reserved else {
                    logger.warning(
                        "Apple Speech asset reservation returned false for '\(context.localeIdentifier, privacy: .public)'. Continuing with the installed language assets."
                    )
                    return true
                }

                return true
            } catch {
                if isReservationLimitError(error) {
                    logger.warning(
                        "Apple Speech reservation limit reached for '\(context.localeIdentifier, privacy: .public)'. Replacing one existing reservation automatically."
                    )

                    guard await releaseOneReservation(toMakeRoomFor: context.localeIdentifier) else {
                        return false
                    }

                    do {
                        try await AssetInventory.reserve(locale: context.locale)
                        return true
                    } catch {
                        return !isReservationLimitError(error)
                    }
                }

                logger.warning(
                    "Apple Speech asset reservation failed for '\(context.localeIdentifier, privacy: .public)': \(error, privacy: .public). Continuing with the installed language assets."
                )
                return true
            }
        }

        @available(macOS 26, *)
        private static func releaseOneReservation(toMakeRoomFor localeIdentifier: String) async -> Bool {
            let reservedLocales = await AssetInventory.reservedLocales
            let requestedIdentifier =
                await supportedLocale(for: localeIdentifier)?.identifier(.bcp47)
                ?? Locale(identifier: localeIdentifier).identifier(.bcp47)

            guard
                let localeToRelease = reservedLocales.first(where: {
                    $0.identifier(.bcp47) != requestedIdentifier
                })
            else {
                return false
            }

            return await AssetInventory.release(reservedLocale: localeToRelease)
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
