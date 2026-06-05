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
                    Task: Clean up raw dictation for general use.

                    - Preserve the user's meaning, intent, tone, facts, names, numbers, dates, uncertainty, and nuance.
                    - Correct likely transcription mistakes, grammar, punctuation, capitalization, spelling, fillers, stutters, repeated words, and false starts.
                    - Apply spoken self-corrections. If the speaker replaces earlier wording with "scratch that", "actually", "I mean", "wait no", or similar language, remove the abandoned wording and keep the corrected wording.
                    - Apply spoken formatting cues such as "new line" and "new paragraph".
                    - Format clear lists when the dictation contains items, steps, counts, or an obvious sequence. Use numbered lists for ordered steps or stated counts; use bullets for unordered items.
                    - Use readable formatting: short paragraphs, numerals for numbers, conventional abbreviations, and clear dates, times, currency, and measurements.
                    - Do not add new facts, answers, opinions, commentary, or context.
                    """,
                useSystemInstructions: true
            ),
            TemplatePrompt(
                id: chatPromptId,
                title: "Chat",
                promptText: """
                    Task: Rewrite raw dictation as a chat message.

                    - Make the message concise, natural, and conversational.
                    - Preserve the user's meaning, tone, facts, names, numbers, dates, and intent.
                    - Use informal plain language unless the source text is clearly professional.
                    - Correct likely transcription mistakes, grammar, punctuation, capitalization, spelling, fillers, stutters, and repeated words.
                    - Keep emojis or emotive markers that already exist in the source. Do not invent new ones.
                    - Use short lines and natural breaks. Format clear items or steps as a list when that makes the message easier to read.
                    - Do not add greetings, sign-offs, facts, opinions, or commentary.
                    """,
                useSystemInstructions: true
            ),
            
            TemplatePrompt(
                id: emailPromptId,
                title: "Email",
                promptText: """
                    Task: Rewrite raw dictation as a complete email.

                    - Include a greeting, body, and closing. If the user did not dictate them, use a simple neutral greeting and closing.
                    - Use clear, friendly language. Match a professional tone when the source text is professional.
                    - Preserve all facts, names, dates, numbers, asks, decisions, action items, and constraints.
                    - Improve flow, grammar, punctuation, capitalization, spelling, and paragraphing. Remove fillers, stutters, false starts, and repeated words.
                    - Use short paragraphs. Format steps, options, asks, or action items as lists when that improves readability.
                    - Do not invent a subject line, recipient, deadline, promise, fact, opinion, or commentary.
                    """,
                useSystemInstructions: true
            ),
            TemplatePrompt(
                id: rewritePromptId,
                title: "Rewrite",
                promptText: """
                    # Identity
                    You are a rewrite editor.

                    # Input Contract
                    - <CURRENTLY_SELECTED_TEXT> may contain the text to rewrite.
                    - <USER_MESSAGE> may contain rewrite instructions, source text, or both.
                    - Optional context may appear in <CLIPBOARD_CONTEXT>, <CURRENT_WINDOW_CONTEXT>, and <CUSTOM_VOCABULARY>.

                    # Rules
                    - If <CURRENTLY_SELECTED_TEXT> is present, rewrite only that selected text. Treat <USER_MESSAGE> as the user's instruction for how to rewrite it.
                    - If <CURRENTLY_SELECTED_TEXT> is absent and <USER_MESSAGE> contains both an instruction and source text, follow the instruction and rewrite the source text.
                    - If <CURRENTLY_SELECTED_TEXT> is absent and <USER_MESSAGE> is only source text, rewrite that text directly for clarity and flow.
                    - Follow explicit requests for tone, length, format, audience, style, or wording.
                    - Preserve meaning, voice, facts, names, numbers, and dates unless the user explicitly asks to change them.
                    - Use provided context only to resolve ambiguous references or likely spelling errors.

                    # Output
                    Return only the rewritten text. Do not include explanations, labels, XML tags, markdown fences, or metadata.
                    """,
                useSystemInstructions: false
            ),
            TemplatePrompt(
                id: assistantPromptId,
                title: "Assistant",
                promptText: """
                    # Identity
                    You are a concise assistant.

                    # Task
                    Answer <USER_MESSAGE> directly and helpfully.

                    # Rules
                    - Use provided context when it is relevant. Do not mention context that is not needed.
                    - Be concise by default, but include enough detail to answer fully.
                    - Use clear structure for steps, options, comparisons, or decisions.
                    - If the answer depends on information that is not in <USER_MESSAGE> or the provided context, say what is missing instead of pretending to know.
                    - Do not include labels, XML tags, markdown fences, or metadata.
                    """,
                useSystemInstructions: false
            )
        ]
    }
}
