import Foundation

struct AIEnhancementOutputFilter {
    static func filter(_ text: String) -> String {
        var processedText = text
        let patterns = [
            #"(?s)<thinking>(.*?)</thinking>"#,
            #"(?s)<think>(.*?)</think>"#,
            #"(?s)<reasoning>(.*?)</reasoning>"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(processedText.startIndex..., in: processedText)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: "")
            }
        }
        
        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 