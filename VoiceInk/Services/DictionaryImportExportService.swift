import Foundation
import AppKit
import UniformTypeIdentifiers

struct DictionaryExportData: Codable {
    let version: String
    let dictionaryItems: [String]
    let wordReplacements: [String: String]
    let exportDate: Date
}

class DictionaryImportExportService {
    static let shared = DictionaryImportExportService()
    private let dictionaryItemsKey = "CustomDictionaryItems"
    private let wordReplacementsKey = "wordReplacements"

    private init() {}

    func exportDictionary() {
        var vocabularyWords: [String] = []
        if let data = UserDefaults.standard.data(forKey: dictionaryItemsKey),
           let items = try? JSONDecoder().decode([VocabularyWord].self, from: data) {
            vocabularyWords = items.map { $0.word }
        }

        let wordReplacements = UserDefaults.standard.dictionary(forKey: wordReplacementsKey) as? [String: String] ?? [:]

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

    func importDictionary() {
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

                    var existingItems: [VocabularyWord] = []
                    if let data = UserDefaults.standard.data(forKey: self.dictionaryItemsKey),
                       let items = try? JSONDecoder().decode([VocabularyWord].self, from: data) {
                        existingItems = items
                    }

                    let existingWordsLower = Set(existingItems.map { $0.word.lowercased() })
                    let originalExistingCount = existingItems.count
                    var newWordsAdded = 0

                    for importedWord in importedData.dictionaryItems {
                        if !existingWordsLower.contains(importedWord.lowercased()) {
                            existingItems.append(VocabularyWord(word: importedWord))
                            newWordsAdded += 1
                        }
                    }

                    if let encoded = try? JSONEncoder().encode(existingItems) {
                        UserDefaults.standard.set(encoded, forKey: self.dictionaryItemsKey)
                    }

                    var existingReplacements = UserDefaults.standard.dictionary(forKey: self.wordReplacementsKey) as? [String: String] ?? [:]

                    var replacementToOriginals: [String: Set<String>] = [:]

                    for (originals, replacement) in existingReplacements {
                        let replacementLower = replacement.lowercased()
                        let words = originals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        replacementToOriginals[replacementLower, default: []].formUnion(words)
                    }

                    for (originals, replacement) in importedData.wordReplacements {
                        let replacementLower = replacement.lowercased()
                        let words = originals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        replacementToOriginals[replacementLower, default: []].formUnion(words)
                    }

                    var mergedReplacements: [String: String] = [:]
                    for (replacementLower, originals) in replacementToOriginals {
                        var uniqueOriginals: [String] = []
                        var seenLower = Set<String>()

                        for original in originals {
                            let originalLower = original.lowercased()
                            if !seenLower.contains(originalLower) {
                                uniqueOriginals.append(original)
                                seenLower.insert(originalLower)
                            }
                        }

                        let mergedKey = uniqueOriginals.sorted().joined(separator: ", ")

                        let replacement = existingReplacements.first(where: { $0.value.lowercased() == replacementLower })?.value
                            ?? importedData.wordReplacements.first(where: { $0.value.lowercased() == replacementLower })?.value
                            ?? replacementLower

                        mergedReplacements[mergedKey] = replacement
                    }

                    UserDefaults.standard.set(mergedReplacements, forKey: self.wordReplacementsKey)

                    var message = "Dictionary data imported successfully from \(url.lastPathComponent).\n\n"
                    message += "Vocabulary Words: \(newWordsAdded) added, \(originalExistingCount) kept\n"
                    message += "Word Replacements: Merged into \(mergedReplacements.count) total rules"

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
