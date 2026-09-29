import AppKit
import Foundation
import UniformTypeIdentifiers

/// Owns native file-panel presentation so the archive and import engine stay
/// independent of AppKit and remain directly testable.
@MainActor
enum DictionaryFilePanelService {
    static func saveDictionaryData(_ data: Data) throws -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "VoiceInk_Dictionary.json"
        savePanel.title = String(localized: "Export Dictionary")
        savePanel.message = String(localized: "Export vocabulary and word replacements to a portable JSON file.")

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    static func chooseDictionaryData() throws -> Data? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = String(localized: "Import Dictionary")
        openPanel.message = String(localized: "Choose a VoiceInk dictionary JSON file.")

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        return try Data(contentsOf: url)
    }
}
