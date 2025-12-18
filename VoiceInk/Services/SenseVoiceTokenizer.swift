import Foundation

struct SenseVoiceTokenizer {
    private let idToPiece: [Int: String]
    private let blankId: Int
    private let sosId: Int
    private let eosId: Int

    init(tokensFileURL: URL) throws {
        let contents = try String(contentsOf: tokensFileURL, encoding: .utf8)
        var mapping: [Int: String] = [:]
        var detectedBlankId: Int?
        var detectedSosId: Int?
        var detectedEosId: Int?

        contents.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let components = trimmed.split(separator: " ")
            guard let last = components.last, let id = Int(last) else { return }
            let token = components.dropLast().joined(separator: " ")
            mapping[id] = token

            let lowerToken = token.lowercased()
            if lowerToken == "<blank>" || lowerToken == "<blk>" || lowerToken == "[blank]" {
                detectedBlankId = id
            } else if lowerToken == "<s>" || lowerToken == "<sos>" || lowerToken == "[cls]" {
                detectedSosId = id
            } else if lowerToken == "</s>" || lowerToken == "<eos>" || lowerToken == "[sep]" {
                detectedEosId = id
            }
        }

        self.idToPiece = mapping
        self.blankId = detectedBlankId ?? 0
        self.sosId = detectedSosId ?? 1
        self.eosId = detectedEosId ?? 2
    }

    func decode(ids: [Int]) -> String {
        guard !ids.isEmpty else { return "" }
        
        // CTC collapse: remove consecutive duplicate token IDs
        var collapsedIds: [Int] = []
        var previousId: Int?
        for id in ids {
            if id != previousId {
                collapsedIds.append(id)
                previousId = id
            }
        }
        
        var pieces: [String] = []

        for id in collapsedIds {
            if id == blankId || id == sosId || id == eosId {
                continue
            }
            if let piece = idToPiece[id] {
                if piece.hasPrefix("<|") && piece.hasSuffix("|>") {
                    continue
                }
                if piece.hasPrefix("<") && piece.hasSuffix(">") {
                    continue
                }
                if piece.hasPrefix("[") && piece.hasSuffix("]") {
                    continue
                }
                pieces.append(piece)
            }
        }

        let joined = pieces.joined()
        return joined
            .replacingOccurrences(of: "▁", with: " ")
            .replacingOccurrences(of: "@@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
