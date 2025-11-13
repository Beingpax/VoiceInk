import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct DictionaryExportData: Codable {
    let version: String
    let dictionaryItems: [String]
    let wordReplacements: [WordReplacementExportData]
    let exportDate: Date
}

struct WordReplacementExportData: Codable {
    let originalVariants: String
    let replacement: String
}

class DictionaryImportExportService {
    static let shared = DictionaryImportExportService()

    private init() {}

    func exportDictionary(modelContext: ModelContext) {
        // Fetch vocabulary words
        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        let vocabularyWords = (try? modelContext.fetch(vocabularyDescriptor))?.map { $0.word } ?? []

        // Fetch word replacements
        let replacementDescriptor = FetchDescriptor<WordReplacement>(sortBy: [SortDescriptor(\.originalVariants)])
        let wordReplacements = (try? modelContext.fetch(replacementDescriptor))?.map {
            WordReplacementExportData(originalVariants: $0.originalVariants, replacement: $0.replacement)
        } ?? []

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        let exportData = DictionaryExportData(
            version: version,
            dictionaryItems: vocabularyWords,
            wordReplacements: wordReplacements,
            exportDate: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let jsonData = try encoder.encode(exportData)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = "VoiceInk_Dictionary.json"
            savePanel.title = "Export Dictionary Data"
            savePanel.message = "Choose a location to save your dictionary items and word replacements."

            DispatchQueue.main.async {
                if savePanel.runModal() == .OK {
                    if let url = savePanel.url {
                        do {
                            try jsonData.write(to: url)
                            self.showAlert(title: "Export Successful", message: "Dictionary data exported successfully to \(url.lastPathComponent).")
                        } catch {
                            self.showAlert(title: "Export Error", message: "Could not save dictionary data: \(error.localizedDescription)")
                        }
                    }
                } else {
                    self.showAlert(title: "Export Canceled", message: "Export operation was canceled.")
                }
            }
        } catch {
            self.showAlert(title: "Export Error", message: "Could not encode dictionary data: \(error.localizedDescription)")
        }
    }

    func importDictionary(modelContext: ModelContext) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Dictionary Data"
        openPanel.message = "Choose a dictionary file to import. New items will be added, existing items will be kept."

        DispatchQueue.main.async {
            if openPanel.runModal() == .OK {
                guard let url = openPanel.url else {
                    self.showAlert(title: "Import Error", message: "Could not get the file URL.")
                    return
                }

                do {
                    let jsonData = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let importedData = try decoder.decode(DictionaryExportData.self, from: jsonData)

                    // Fetch existing vocabulary words
                    let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
                    let existingWords = try? modelContext.fetch(vocabularyDescriptor)
                    let existingWordsSet = Set(existingWords?.map { $0.word.lowercased() } ?? [])
                    var newWordsAdded = 0

                    // Import vocabulary words
                    for word in importedData.dictionaryItems {
                        if !existingWordsSet.contains(word.lowercased()) {
                            let vocabularyWord = VocabularyWord(word: word)
                            modelContext.insert(vocabularyWord)
                            newWordsAdded += 1
                        }
                    }

                    // Fetch existing replacements
                    let replacementDescriptor = FetchDescriptor<WordReplacement>()
                    let existingReplacements = try? modelContext.fetch(replacementDescriptor)
                    let existingReplacementsSet = Set(existingReplacements?.map { "\($0.originalVariants.lowercased())|\($0.replacement.lowercased())" } ?? [])
                    var newReplacementsAdded = 0

                    // Import word replacements
                    for importedReplacement in importedData.wordReplacements {
                        let key = "\(importedReplacement.originalVariants.lowercased())|\(importedReplacement.replacement.lowercased())"
                        if !existingReplacementsSet.contains(key) {
                            let wordReplacement = WordReplacement(
                                originalVariants: importedReplacement.originalVariants,
                                replacement: importedReplacement.replacement
                            )
                            modelContext.insert(wordReplacement)
                            newReplacementsAdded += 1
                        }
                    }

                    try modelContext.save()

                    var message = "Dictionary data imported successfully from \(url.lastPathComponent).\n\n"
                    message += "Vocabulary Words: \(newWordsAdded) added, \(existingWords?.count ?? 0) existing\n"
                    message += "Word Replacements: \(newReplacementsAdded) added, \(existingReplacements?.count ?? 0) existing"

                    self.showAlert(title: "Import Successful", message: message)

                } catch {
                    self.showAlert(title: "Import Error", message: "Error importing dictionary data: \(error.localizedDescription). The file might be corrupted or not in the correct format.")
                }
            } else {
                self.showAlert(title: "Import Canceled", message: "Import operation was canceled.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
