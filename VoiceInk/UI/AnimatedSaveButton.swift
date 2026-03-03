import SwiftUI
import UniformTypeIdentifiers

struct AnimatedSaveButton: View {
    let textToSave: String
    @State private var isSaved: Bool = false
    @State private var showingSavePanel = false
    
    var body: some View {
        Menu {
            Button("Save as TXT") {
                saveFile(as: .plainText, extension: "txt")
            }
            
            Button("Save as MD") {
                saveFile(as: .text, extension: "md")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down")
                    .font(.system(size: 12, weight: isSaved ? .bold : .regular))
                    .foregroundColor(.white)
                Text(isSaved ? "Saved" : "Save")
                    .font(.system(size: 12, weight: isSaved ? .medium : .regular))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSaved ? Color.green.opacity(0.8) : Color.orange)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSaved ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSaved)
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
                
                withAnimation {
                    isSaved = true
                }
                
                // Reset the animation after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isSaved = false
                    }
                }
            } catch {
                print("Failed to save file: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateFileName() -> String {
        // Clean the text and split into words
        let cleanedText = textToSave
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        let words = cleanedText.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        // Take first 5-8 words (depending on length)
        let wordCount = min(words.count, words.count <= 3 ? words.count : (words.count <= 6 ? 6 : 8))
        let selectedWords = Array(words.prefix(wordCount))
        
        if selectedWords.isEmpty {
            return "transcription"
        }
        
        // Create filename by joining words and cleaning invalid characters
        let fileName = selectedWords.joined(separator: "-")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        // Ensure filename isn't empty and isn't too long
        let finalFileName = fileName.isEmpty ? "transcription" : String(fileName.prefix(50))
        
        return finalFileName
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

struct AnimatedSaveButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AnimatedSaveButton(textToSave: "Hello world this is a sample transcription text")
            Text("Save Button Preview")
                .padding()
        }
        .padding()
    }
} 