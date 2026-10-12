import Foundation

struct DictionaryArchive: Codable, Sendable {
    // This identifier and schema version are independent of the app version so
    // dictionary files remain portable across VoiceInk releases.
    static let formatIdentifier = "voiceink.dictionary"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String?
    let vocabulary: [DictionaryVocabularyEntry]
    let replacements: [DictionaryReplacementEntry]

    init(
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        vocabulary: [DictionaryVocabularyEntry],
        replacements: [DictionaryReplacementEntry]
    ) {
        self.format = Self.formatIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.vocabulary = vocabulary
        self.replacements = replacements
    }

}

struct DictionaryVocabularyEntry: Codable, Sendable {
    let term: String
    let createdAt: Date?
}

struct DictionaryReplacementEntry: Codable, Sendable {
    /// Each source is one discrete phrase. Commas are rejected because the
    /// persisted dictionary uses commas as its source separator.
    let sources: [String]
    let replacement: String
    let createdAt: Date?
}

enum DictionaryImportMode: String, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: Self { self }
}

struct DictionaryImportPayload: Identifiable, Sendable {
    let id = UUID()
    let archive: DictionaryArchive
}

struct DictionaryImportSummary: Sendable {
    let vocabularyToImport: Int
    let replacementRulesToImport: Int
    let replacementSourcesToImport: Int
    let duplicateVocabularyCount: Int
    let duplicateReplacementCount: Int
    let conflictingReplacementCount: Int
    let invalidEntryCount: Int
    let commaContainingSourceCount: Int
    let cyclicReplacementCount: Int
    let vocabularyToRemove: Int
    let replacementsToRemove: Int

    var skippedEntryCount: Int {
        duplicateVocabularyCount
            + duplicateReplacementCount
            + conflictingReplacementCount
            + invalidEntryCount
            + commaContainingSourceCount
            + cyclicReplacementCount
    }

    var hasImportableEntries: Bool {
        vocabularyToImport > 0 || replacementRulesToImport > 0
    }
}

struct DictionaryImportResult: Sendable {
    let summary: DictionaryImportSummary

    var message: String {
        var lines = [
            String(localized: "Imported \(summary.vocabularyToImport) vocabulary entries."),
            String(localized: "Imported \(summary.replacementRulesToImport) word replacement rules."),
        ]

        if summary.vocabularyToRemove + summary.replacementsToRemove > 0 {
            let removedVocabulary = String(
                localized: "\(summary.vocabularyToRemove) previous vocabulary entries"
            )
            let removedReplacements = String(
                localized: "\(summary.replacementsToRemove) previous word replacements"
            )
            lines.append(
                String(
                    format: String(localized: "Removed %@ and %@."),
                    removedVocabulary,
                    removedReplacements
                )
            )
        }

        if summary.skippedEntryCount > 0 {
            lines.append(
                String(
                    localized:
                        "Skipped \(summary.skippedEntryCount) duplicate, conflicting, invalid, or cyclic entries."
                )
            )
        }

        return lines.joined(separator: "\n")
    }
}

enum DictionaryArchiveError: LocalizedError {
    case invalidFile
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case noImportableEntries
    case dictionaryChanged
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return String(localized: "This file does not contain a valid VoiceInk dictionary.")
        case .unsupportedFormat(let format):
            return String(format: String(localized: "Unsupported dictionary format: %@"), format)
        case .unsupportedVersion(let version):
            return String(
                format: String(localized: "This dictionary uses unsupported schema version %d."),
                version
            )
        case .noImportableEntries:
            return String(localized: "No valid entries are available to import.")
        case .dictionaryChanged:
            return String(localized: "The dictionary changed while preparing the import. Review it and try again.")
        case .saveFailed(let error):
            return String(
                format: String(localized: "The dictionary could not be saved: %@"),
                error.localizedDescription
            )
        }
    }
}

extension DictionaryImportExportService {
    static func encodeArchive(_ archive: DictionaryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    static func decodeArchiveData(_ data: Data) throws -> DictionaryImportPayload {
        DictionaryImportPayload(archive: try decodeArchive(from: data))
    }

    private static func decodeArchive(from data: Data) throws -> DictionaryArchive {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let root = json as? [String: Any]
        else {
            throw DictionaryArchiveError.invalidFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let format = root["format"] as? String else {
            throw DictionaryArchiveError.invalidFile
        }
        guard format == DictionaryArchive.formatIdentifier else {
            throw DictionaryArchiveError.unsupportedFormat(format)
        }

        let archive: DictionaryArchive
        do {
            archive = try decoder.decode(DictionaryArchive.self, from: data)
        } catch {
            throw DictionaryArchiveError.invalidFile
        }

        guard archive.schemaVersion == DictionaryArchive.currentSchemaVersion else {
            throw DictionaryArchiveError.unsupportedVersion(archive.schemaVersion)
        }
        return archive
    }
}
