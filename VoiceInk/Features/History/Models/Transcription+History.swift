import Foundation

extension Transcription {
    var preferredHistoryText: String {
        enhancedHistoryText ?? text
    }

    var hasEnhancedHistoryText: Bool {
        enhancedHistoryText != nil
    }

    var historyEnhancementDetailText: String? {
        guard let enhancedText,
            !enhancedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return enhancedText
    }

    var availableHistoryAudioURL: URL? {
        guard let audioFileURL,
            let url = URL(string: audioFileURL),
            FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    var recordedHistoryModeIcon: ModeIcon? {
        guard let modeEmoji else { return nil }
        let value = modeEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.isValidEmoji ? .emoji(value) : .symbol(value)
    }

    private var enhancedHistoryText: String? {
        guard let enhancedText = historyEnhancementDetailText else { return nil }

        let normalizedLowercasedText = enhancedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isFailureMessage = Self.enhancementFailurePrefixes.contains {
            normalizedLowercasedText.hasPrefix($0)
        }

        return isFailureMessage ? nil : enhancedText
    }

    private static let enhancementFailurePrefixes: [String] = {
        let formatKey = "Enhancement failed: %@"
        let localizedBundles = Bundle.main.localizations.compactMap { localization in
            Bundle.main.path(forResource: localization, ofType: "lproj")
                .flatMap(Bundle.init(path:))
        }

        let formats = [formatKey] + ([Bundle.main] + localizedBundles)
            .map { bundle in
                bundle.localizedString(forKey: formatKey, value: formatKey, table: nil)
            }

        return formats.compactMap { format in
            guard let placeholderRange = format.range(of: "%@") else { return nil }
            return format[..<placeholderRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        .filter { !$0.isEmpty }
    }()
}
