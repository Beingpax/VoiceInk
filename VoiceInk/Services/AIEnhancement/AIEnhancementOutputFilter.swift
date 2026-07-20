import Foundation

struct AIEnhancementOutputFilter {
    static func filter(_ text: String) -> String {
        var processedText = text
        let patterns = [
            #"(?s)<thinking>(.*?)</thinking>"#,
            #"(?s)<think>(.*?)</think>"#,
            #"(?s)<reasoning>(.*?)</reasoning>"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(processedText.startIndex..., in: processedText)
                processedText = regex.stringByReplacingMatches(
                    in: processedText, options: [], range: range, withTemplate: "")
            }
        }

        processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        processedText = strippingLeakedPromptScaffolding(processedText)
        processedText = strippingMarkdownCodeFence(processedText)
        return strippingChatPreamble(processedText)
    }

    // Observed verbatim from a model that lost track of the system prompt and echoed its own
    // instructions back before the real answer:
    //   <TASK_INSTRUCTIONS>\n...rules the model was given...\n</TASK_INSTRUCTIONS>\n\n<OUTPUT>\nthe actual answer
    // VoiceInk's own prompt template (AIPrompts.enhancementSystemTemplate) and request
    // formatting are the only source of these exact tag names, so treating them as leaked
    // scaffolding rather than dictated content is safe.
    private static func strippingLeakedPromptScaffolding(_ text: String) -> String {
        // <OUTPUT> marks the true start of the model's answer — trust it completely and discard
        // everything before it, including any echoed (and possibly malformed/unclosed) instruction
        // blocks. This is the exact shape observed, so it's handled directly rather than relying
        // on well-formed nested tags.
        if let outputRange = text.range(of: "<OUTPUT>") {
            var remainder = String(text[outputRange.upperBound...])
            if let closeRange = remainder.range(of: "</OUTPUT>") {
                remainder = String(remainder[..<closeRange.lowerBound])
            }
            return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var processedText = text
        let scaffoldingTags = [
            "TASK_INSTRUCTIONS", "CUSTOM_VOCABULARY", "CURRENTLY_SELECTED_TEXT",
            "CLIPBOARD_CONTEXT", "CURRENT_WINDOW_CONTEXT", "USER_MESSAGE",
        ]
        for tag in scaffoldingTags {
            let pattern = "(?s)<\(tag)>.*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(processedText.startIndex..., in: processedText)
                processedText = regex.stringByReplacingMatches(
                    in: processedText, options: [], range: range, withTemplate: "")
            }
        }
        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // A response fully wrapped in a markdown code fence (```markdown\n...\n``` or ```\n...\n```,
    // observed verbatim from Apple Intelligence) is model formatting habit, not dictated content
    // — dictated speech doesn't naturally start and end with triple backticks. Anchored to the
    // whole string so a backtick the user actually dictated mid-sentence is left alone.
    private static func strippingMarkdownCodeFence(_ text: String) -> String {
        let fencePattern = #"(?s)^```[a-zA-Z]*\n(.*)\n```$"#
        guard let regex = try? NSRegularExpression(pattern: fencePattern),
            let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return text
        }
        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Small on-device models (notably Apple Intelligence) sometimes ignore "return only the
    // final text" and prefix a conversational lead-in like "Sure, here is the polished version
    // of your text:" — usually wrapping the actual result in quotes. Pasting that into the
    // user's document would be worse than no enhancement, so strip the lead-in line, and the
    // wrapping quotes only when a lead-in was present (quotes without a lead-in are treated as
    // dictated content).
    private static func strippingChatPreamble(_ text: String) -> String {
        // Two requirements keep false positives out: a conversational lead word AND a word
        // referring to the rewriting act itself. "Here are the three options:" (dictated
        // content) survives; "Here's the revised text:" (model chatter) does not.
        let preamblePattern =
            #"(?i)^(sure|certainly|okay|ok|of course|absolutely|no problem|got it|here('s| is| are)?)\b[^\n]*\b(version|text|transcript|message|polish\w*|revis\w*|rewrit\w*|clean\w*|correct\w*|edit\w*|request\w*)\b[^\n]*:\s*\n+"#

        guard let regex = try? NSRegularExpression(pattern: preamblePattern),
            let match = regex.firstMatch(of: text)
        else {
            return text
        }

        let remainder = String(text[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return text }

        return strippingWrappingQuotes(remainder)
    }

    private static func strippingWrappingQuotes(_ text: String) -> String {
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}")]

        for (opening, closing) in quotePairs {
            guard text.count >= 2,
                text.first == opening,
                text.last == closing
            else { continue }

            let interior = String(text.dropFirst().dropLast())
            guard !interior.contains(opening), !interior.contains(closing) else { continue }
            return interior.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }
}

extension NSRegularExpression {
    fileprivate func firstMatch(of text: String) -> Range<String.Index>? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = firstMatch(in: text, options: [], range: range) else { return nil }
        return Range(match.range, in: text)
    }
}
