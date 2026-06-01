import Foundation

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let useSystemInstructions: Bool
    
    func toCustomPrompt(id: UUID = UUID()) -> CustomPrompt {
        CustomPrompt(
            id: id,
            title: title,
            promptText: promptText,
            useSystemInstructions: useSystemInstructions
        )
    }
}

enum PromptTemplates {
    static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let chatPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let emailPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let rewritePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let assistantPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }

    static var seedPrompts: [CustomPrompt] {
        all.map { $0.toCustomPrompt(id: $0.id) }
    }
    
    static func createTemplatePrompts() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: defaultPromptId,
                title: "Default",
                promptText: """
                    - Clean up the <USER_MESSAGE> text for clarity and natural flow while preserving meaning and the original tone.
                    - Use informal, plain language unless the <USER_MESSAGE> clearly uses a professional tone; in that case, match it.
                    - Fix obvious grammar, remove fillers and stutters, collapse repetitions, and keep names and numbers.
                    - Handle backtracking and self-corrections: When the speaker corrects themselves mid-sentence using phrases like "scratch that", "actually", "sorry not that", "I mean", "wait no", or similar corrections, remove the incorrect part and keep only the corrected version. Example: "The meeting is on Tuesday, sorry not that, actually Wednesday" → "The meeting is on Wednesday."
                    - Respect formatting commands: When the speaker explicitly says "new line" or "new paragraph", insert the appropriate line break or paragraph break at that point.
                    - Automatically detect and format lists properly: if the <USER_MESSAGE> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Apply smart formatting: Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20'), convert common abbreviations to proper format (e.g., 'vs' → 'vs.', 'etc' → 'etc.'), and format dates, times, and measurements consistently.
                    - Keep the original intent and nuance.
                    - Organize into short paragraphs of 2–4 sentences for readability.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the cleaned text.
                    - Don't add any information not available in the <USER_MESSAGE> text ever.
                    """,
                useSystemInstructions: true
            ),
            TemplatePrompt(
                id: chatPromptId,
                title: "Chat",
                promptText: """
                    - Rewrite the <USER_MESSAGE> text as a chat message: informal, concise, and conversational.
                    - Keep emotive markers and emojis if present; don't invent new ones.
                    - Lightly fix grammar, remove fillers and repeated words, and improve flow without changing meaning.
                    - Keep the original tone; only be professional if the <USER_MESSAGE> already is.
                    - Automatically detect and format lists properly: if the <USER_MESSAGE> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Format like a modern chat message - short lines, natural breaks, emoji-friendly.
                    - Do not add greetings, sign-offs, or commentary.
                    - Output only the chat message.
                    - Don't add any information not available in the <USER_MESSAGE> text ever.
                    """,
                useSystemInstructions: true
            ),
            
            TemplatePrompt(
                id: emailPromptId,
                title: "Email",
                promptText: """
                    - Rewrite the <USER_MESSAGE> text as a complete email with proper formatting: include a greeting (Hi), body paragraphs (2-4 sentences each), and closing (Thanks).
                    - Use clear, friendly, non-formal language unless the <USER_MESSAGE> is clearly professional—in that case, match that tone.
                    - Improve flow and coherence; fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
                    - Automatically detect and format lists properly: if the <USER_MESSAGE> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Do not invent new content, but structure it as a proper email format.
                    - Don't add any information not available in the <USER_MESSAGE> text ever.
                    """,
                useSystemInstructions: true
            ),
            TemplatePrompt(
                id: rewritePromptId,
                title: "Rewrite",
                promptText: """
                    - If <CURRENTLY_SELECTED_TEXT> is provided, rewrite that selected text.
                    - Treat <USER_MESSAGE> as the user's rewrite instruction and follow it first.
                    - If <USER_MESSAGE> asks for a specific tone, length, format, audience, or style, prioritize that over the default cleanup rules.
                    - If no selected text is provided, rewrite the <USER_MESSAGE> text directly.
                    - Improve clarity, flow, grammar, and wording only in ways that support the user's instruction.
                    - Preserve the original meaning, voice, facts, names, numbers, and dates unless the user explicitly asks to change them.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the rewritten text.
                    - Don't add any information not available in the selected text or <USER_MESSAGE> text ever.
                    """,
                useSystemInstructions: false
            ),
            TemplatePrompt(
                id: assistantPromptId,
                title: "Assistant",
                promptText: """
                    - Answer the user's <USER_MESSAGE> directly and helpfully.
                    - Use any provided context only when it is relevant to the user's request.
                    - Be concise by default, but include enough detail to fully answer the question.
                    - If the user asks for steps, options, or a comparison, structure the response clearly.
                    - Do not claim access to information that is not present in the request or context.
                    """,
                useSystemInstructions: false
            )
        ]
    }
}
