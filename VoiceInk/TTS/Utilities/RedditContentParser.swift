import Foundation

enum RedditContentParser {
    private static let maxCommentCount = 80

    enum ParserError: Error {
        case invalidPayload
        case missingPost
        case emptyThread
    }

    static func buildThreadText(from data: Data) throws -> String {
        let listings: [RedditListing]
        do {
            listings = try JSONDecoder().decode([RedditListing].self, from: data)
        } catch {
            throw ParserError.invalidPayload
        }

        guard let postNode = listings.first?.data.children.first(where: { $0.kind == "t3" })?.data else {
            throw ParserError.missingPost
        }

        let commentListing = listings.dropFirst().first
        let comments = commentListing.map { extractComments(from: $0) } ?? []

        let thread = composeThread(from: postNode, comments: comments)
        guard !thread.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.emptyThread
        }

        return thread
    }

    private static func composeThread(from post: RedditNode, comments: [RedditComment]) -> String {
        var sections: [String] = []

        if let title = normalizedText(post.title) {
            sections.append(title)
        }

        if let author = normalizedText(post.author) {
            sections.append("Posted by u/\(author)")
        }

        if let body = normalizedPostBody(post.selftext) {
            sections.append(body)
        } else if let link = normalizedText(post.url) {
            sections.append("Link: \(link)")
        }

        let commentLines = formatComments(comments)
        if !commentLines.isEmpty {
            sections.append((["Comments:"] + commentLines).joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private static func formatComments(_ comments: [RedditComment]) -> [String] {
        var remaining = maxCommentCount
        var truncated = false
        var lines: [String] = []
        append(comments: comments,
               depth: 0,
               remaining: &remaining,
               truncated: &truncated,
               into: &lines)
        if truncated {
            lines.append("...comments truncated for brevity.")
        }
        return lines
    }

    private static func append(comments: [RedditComment],
                               depth: Int,
                               remaining: inout Int,
                               truncated: inout Bool,
                               into lines: inout [String]) {
        guard remaining > 0 else {
            truncated = truncated || !comments.isEmpty
            return
        }

        for (index, comment) in comments.enumerated() {
            guard remaining > 0 else {
                truncated = true
                break
            }

            remaining -= 1

            let author = comment.author ?? "[deleted]"
            let prefix = String(repeating: ">", count: depth + 1)
            lines.append("\(prefix) u/\(author): \(comment.body)")

            if !comment.replies.isEmpty {
                append(comments: comment.replies,
                       depth: depth + 1,
                       remaining: &remaining,
                       truncated: &truncated,
                       into: &lines)
            }

            if remaining == 0 && index < comments.count - 1 {
                truncated = true
                break
            }
        }
    }

    private static func extractComments(from listing: RedditListing) -> [RedditComment] {
        listing.data.children.compactMap { child in
            guard child.kind == "t1" else { return nil }
            return buildComment(from: child.data)
        }
    }

    private static func buildComment(from node: RedditNode) -> RedditComment? {
        guard let body = normalizedCommentBody(node.body) else { return nil }
        let replies = node.replies?.listing.map { extractComments(from: $0) } ?? []
        return RedditComment(author: normalizedText(node.author), body: body, replies: replies)
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let raw = text else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedPostBody(_ text: String?) -> String? {
        guard let raw = text else { return nil }
        let cleaned = raw.replacingOccurrences(of: "\r", with: "\n")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedCommentBody(_ text: String?) -> String? {
        guard let raw = text else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "[deleted]" || trimmed == "[removed]" {
            return nil
        }
        let singleLine = trimmed
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let collapsed = singleLine.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RedditListing: Decodable {
    let kind: String?
    let data: RedditListingData
}

private struct RedditListingData: Decodable {
    let children: [RedditChild]
}

private struct RedditChild: Decodable {
    let kind: String
    let data: RedditNode
}

private struct RedditNode: Decodable {
    let title: String?
    let selftext: String?
    let author: String?
    let body: String?
    let url: String?
    let replies: RedditReplies?
}

private enum RedditReplies: Decodable {
    case listing(RedditListing)
    case empty

    var listing: RedditListing? {
        switch self {
        case .listing(let listing):
            return listing
        case .empty:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .empty
            return
        }

        if let listing = try? container.decode(RedditListing.self) {
            self = .listing(listing)
            return
        }

        if let stringValue = try? container.decode(String.self), stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .empty
            return
        }

        self = .empty
    }
}

private struct RedditComment {
    let author: String?
    let body: String
    let replies: [RedditComment]
}
