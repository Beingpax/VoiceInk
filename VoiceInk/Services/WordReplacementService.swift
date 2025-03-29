import Foundation

class WordReplacementService {
    static let shared = WordReplacementService()
    
    private init() {}
    
    func applyReplacements(to text: String) -> String {
        let replacements = UserDefaults.standard.wordReplacements
        guard !replacements.isEmpty else {
            return text // No replacements to apply
        }
        
        var modifiedText = text
        
        // Apply each replacement (case-insensitive, whole word)
        for (original, replacement) in replacements {
            // Create a regular expression that matches the word boundaries
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: original))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                modifiedText = regex.stringByReplacingMatches(
                    in: modifiedText,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }
        
        return modifiedText
    }
}
