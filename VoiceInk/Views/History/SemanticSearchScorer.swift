import Foundation

struct SemanticSearchScorer {
    // Basic conceptual mappings for high ROI offline semantic feel
    private static let conceptGroups: [[String]] = [
        ["code", "programming", "swift", "python", "javascript", "function", "compile", "bug", "error", "issue", "develop", "repository", "github"],
        ["money", "price", "billing", "invoice", "cost", "charge", "payment", "revenue", "budget", "salary", "invoice"],
        ["meeting", "call", "schedule", "calendar", "zoom", "meet", "discuss", "appointment", "standup", "sprint"],
        ["design", "ui", "ux", "color", "layout", "font", "css", "mockup", "figma", "visual", "aesthetic", "sketch"],
        ["audio", "sound", "voice", "microphone", "recording", "volume", "music", "noise", "whisper", "hertz"]
    ]
    
    static func matches(searchText: String, text: String) -> Bool {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        
        let target = text.lowercased()
        
        // 1. Direct match (baseline)
        if target.contains(query) { return true }
        
        // 2. CONCEPTUAL SEMANTIC FALLBACK (if enabled)
        if UserDefaults.standard.bool(forKey: "superchargeSemanticHistorySearch") {
            // Find concept groups matching the query word or target words
            for group in conceptGroups {
                // If query is in this conceptual bucket
                if group.contains(where: { query.contains($0) || $0.contains(query) }) {
                    // Check if target contains any other words in the same conceptual bucket
                    for word in group {
                        if target.contains(word) {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
}
