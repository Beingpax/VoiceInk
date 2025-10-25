import Foundation

enum ArticleHTMLExtractor {
    static func extractPrimaryText(from html: String) -> String? {
        let trimmedHTML = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHTML.contains("<") else {
            return nil
        }

        guard let fragment = extractContentFragment(from: trimmedHTML) else {
            return nil
        }

        let cleanedHTML = stripNonContent(from: fragment)
        let plainText = htmlToPlainText(cleanedHTML)
        let normalized = normalizeParagraphs(in: plainText)
        let wordCount = countWords(in: normalized)

        guard wordCount >= 40 || normalized.count >= 300 else {
            return nil
        }

        return normalized
    }

    private static func extractContentFragment(from html: String) -> String? {
        if let article = firstElement(named: "article", in: html) {
            return article
        }

        if let main = firstElement(named: "main", in: html) {
            return main
        }

        if let keywordContainer = firstContainer(matching: keywordHints, in: html) {
            return keywordContainer
        }

        return nil
    }

    private static func firstElement(named tag: String, in html: String) -> String? {
        var searchStart = html.startIndex

        while searchStart < html.endIndex {
            guard let opener = html.range(of: "<\(tag)", options: [.caseInsensitive], range: searchStart..<html.endIndex) else {
                break
            }

            guard let elementRange = elementRange(for: tag, in: html, startingAt: opener.lowerBound) else {
                if let openTagEnd = closingBracketIndex(from: opener.lowerBound, in: html) {
                    searchStart = html.index(after: openTagEnd)
                } else {
                    break
                }
                continue
            }

            return String(html[elementRange])
        }

        return nil
    }

    private static func firstContainer(matching keywords: [String], in html: String) -> String? {
        let lowerKeywords = keywords.map { $0.lowercased() }
        let containerTags = ["div", "section"]

        for tag in containerTags {
            var searchStart = html.startIndex

            while searchStart < html.endIndex {
                guard let opener = html.range(of: "<\(tag)", options: [.caseInsensitive], range: searchStart..<html.endIndex) else {
                    break
                }

                guard let openTagEnd = closingBracketIndex(from: opener.lowerBound, in: html) else {
                    break
                }

                let tagSnippet = html[opener.lowerBound...openTagEnd].lowercased()
                let containsKeyword = lowerKeywords.contains(where: { tagSnippet.contains($0) })

                if containsKeyword,
                   let elementRange = elementRange(for: tag, in: html, startingAt: opener.lowerBound) {
                    return String(html[elementRange])
                }

                searchStart = html.index(after: openTagEnd)
            }
        }

        return nil
    }

    private static func elementRange(for tag: String, in html: String, startingAt index: String.Index) -> Range<String.Index>? {
        guard let openTagEnd = closingBracketIndex(from: index, in: html) else {
            return nil
        }

        var depth = 1
        var searchIndex = html.index(after: openTagEnd)
        let lowerTag = tag.lowercased()

        while searchIndex < html.endIndex {
            let openPattern = "<\(lowerTag)"
            let closePattern = "</\(lowerTag)"

            let nextOpen = html.range(of: openPattern, options: [.caseInsensitive], range: searchIndex..<html.endIndex)
            let nextClose = html.range(of: closePattern, options: [.caseInsensitive], range: searchIndex..<html.endIndex)

            guard let closeRange = nextClose else {
                return nil
            }

            if let openRange = nextOpen, openRange.lowerBound < closeRange.lowerBound {
                guard let nestedEnd = closingBracketIndex(from: openRange.lowerBound, in: html) else {
                    return nil
                }
                depth += 1
                searchIndex = html.index(after: nestedEnd)
                continue
            }

            guard let closeTagEnd = closingBracketIndex(from: closeRange.lowerBound, in: html) else {
                return nil
            }

            depth -= 1

            if depth == 0 {
                let elementEnd = html.index(after: closeTagEnd)
                return index..<elementEnd
            }

            searchIndex = html.index(after: closeTagEnd)
        }

        return nil
    }

    private static func closingBracketIndex(from index: String.Index, in html: String) -> String.Index? {
        html[index..<html.endIndex].firstIndex(of: ">")
    }

    private static func stripNonContent(from html: String) -> String {
        var mutableHTML = html
        mutableHTML = removeElements(named: [
            "script",
            "style",
            "noscript",
            "aside",
            "nav",
            "form",
            "footer",
            "svg",
            "button",
            "figure"
        ], in: mutableHTML)

        mutableHTML = removeContainers(containing: [
            "share",
            "social",
            "subscribe",
            "newsletter",
            "promo",
            "advert",
            "recommended",
            "trending",
            "related"
        ], from: mutableHTML)

        mutableHTML = removeNavigationHeaders(in: mutableHTML)

        return mutableHTML
    }

    private static func removeElements(named tags: [String], in html: String) -> String {
        var result = html

        for tag in tags {
            let pattern = "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>"
            result = regexReplace(pattern, in: result, with: "")
        }

        return result
    }

    private static func removeNavigationHeaders(in html: String) -> String {
        var result = html
        var searchStart = result.startIndex

        while searchStart < result.endIndex {
            guard let opener = result.range(of: "<header", options: [.caseInsensitive], range: searchStart..<result.endIndex) else {
                break
            }

            guard let elementRange = elementRange(for: "header", in: result, startingAt: opener.lowerBound) else {
                if let openTagEnd = closingBracketIndex(from: opener.lowerBound, in: result) {
                    searchStart = result.index(after: openTagEnd)
                } else {
                    break
                }
                continue
            }

            let headerHTML = result[elementRange]
            let lowercased = headerHTML.lowercased()
            let containsHeading = lowercased.contains("<h1") || lowercased.contains("<h2") || lowercased.contains("<h3")
            let looksLikeNavigation = lowercased.contains("<nav") || lowercased.contains("menu") || lowercased.contains("breadcrumb") || lowercased.contains("aria-label=\"breadcrumb\"")

            if !containsHeading || looksLikeNavigation {
                result.removeSubrange(elementRange)
                searchStart = elementRange.lowerBound
            } else {
                searchStart = elementRange.upperBound
            }
        }

        return result
    }

    private static func removeContainers(containing keywords: [String], from html: String) -> String {
        var result = html
        let lowerKeywords = keywords.map { $0.lowercased() }
        let tags = ["div", "section", "aside", "ul", "ol"]

        for tag in tags {
            var searchStart = result.startIndex

            while searchStart < result.endIndex {
                guard let opener = result.range(of: "<\(tag)", options: [.caseInsensitive], range: searchStart..<result.endIndex) else {
                    break
                }

                guard let openTagEnd = closingBracketIndex(from: opener.lowerBound, in: result) else {
                    break
                }

                let tagSnippet = result[opener.lowerBound...openTagEnd].lowercased()
                let matchesKeyword = lowerKeywords.contains(where: { tagSnippet.contains($0) })

                guard matchesKeyword,
                      let elementRange = elementRange(for: tag, in: result, startingAt: opener.lowerBound) else {
                    searchStart = result.index(after: openTagEnd)
                    continue
                }

                result.removeSubrange(elementRange)
                searchStart = elementRange.lowerBound
            }
        }

        return result
    }

    private static func htmlToPlainText(_ html: String) -> String {
        if let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        return html
    }

    private static func normalizeParagraphs(in text: String) -> String {
        let newlineNormalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return newlineNormalized
            .components(separatedBy: "\n\n")
            .map { block in
                block
                    .components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func countWords(in text: String) -> Int {
        text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private static func regexReplace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static var keywordHints: [String] {
        [
            "article",
            "story",
            "content",
            "storybody",
            "articlebody",
            "main",
            "body",
            "post",
            "rich-text",
            "story__body",
            "article__body",
            "storycontent",
            "articlecontent",
            "post__content"
        ]
    }
}
