import SwiftUI
import UniformTypeIdentifiers

struct SaveIconButton: View {
    let textToSave: String
    @State private var saved = false

    var body: some View {
        Menu {
            Button("Save as TXT") {
                saveFile(as: .plainText, extension: "txt")
            }
            Button("Save as MD") {
                saveFile(as: .text, extension: "md")
            }
        } label: {
            Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(saved ? .green : .secondary)
                .frame(width: 28, height: 28)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Save to file")
    }

    private func saveFile(as contentType: UTType, extension fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(generateFileName()).\(fileExtension)"
        panel.title = "Save Transcription"

        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            do {
                let content = fileExtension == "md" ? formatAsMarkdown(textToSave) : textToSave
                try content.write(to: url, atomically: true, encoding: .utf8)
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { saved = false }
                }
            } catch {
                print("Failed to save file: \(error.localizedDescription)")
            }
        }
    }

    private func generateFileName() -> String {
        let cleanedText = textToSave
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let words = cleanedText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wordCount = min(words.count, words.count <= 3 ? words.count : (words.count <= 6 ? 6 : 8))
        let selectedWords = Array(words.prefix(wordCount))

        if selectedWords.isEmpty { return "transcription" }

        let fileName = selectedWords.joined(separator: "-")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return fileName.isEmpty ? "transcription" : String(fileName.prefix(50))
    }

    private func formatAsMarkdown(_ text: String) -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        return """
        # Transcription

        **Date:** \(timestamp)

        \(text)
        """
    }
}
