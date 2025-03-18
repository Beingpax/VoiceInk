import Foundation

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"
    
    // Static UUIDs for predefined prompts
    private static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let chatStylePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let emailPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let workflowPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    
    static var all: [CustomPrompt] {
        // Always return the latest predefined prompts from source code
        createDefaultPrompts()
    }
    
    static func createDefaultPrompts() -> [CustomPrompt] {
        [
            CustomPrompt(
                id: defaultPromptId,
                title: "Default",
                promptText: """
                Primary Rules:
                0. Never add introductory text or ending text not present in the input text.
                1. Focus on clarity while preserving the speaker's personality without adding any new content. 
                    - Keep personality markers that show intent or style (e.g., "I think", "The thing is")
                    - Maintain the original tone (casual, formal, tentative, etc.)
                    
                    Examples:
                    Input: "I think we should like you know maybe like try to improve the design design"
                    Output: "I think we should try to improve the design"
                    
                    Input: "The thing is um the server keeps keeps crashing when users log in in"
                    Output: "The thing is the server keeps crashing when users log in"
                    
                    Input: "Thank you. Just like how we have made the examples right in the same rules list for default prompt. I want you to do the same thing for chat prompt as well. Custom chat style prompt. Let's do it properly."
                    Output: "Thank You. Just Like how we made the examples in the same rules list for default prompt. I want you to do the same thing for chat prompt as well. Let's do it properly."
                    
                    Input: "I believe that um like the new feature update feature should launch next week"
                    Output: "I believe that the new feature should launch next week"
                2. Remove redundancies and unnecessary filler words
                   Examples:
                   Input: "I think we should, like, you know, start the project now, start the project now."
                   Output: "I think we should start the project now."

                   Input: "The meeting is going to be, um, going to be at like maybe 3 PM tomorrow."
                   Output: "The meeting is going to be at 3 PM tomorrow."
                3. Break structure into clear, logical sections with new paragraphs every 2-3 sentences
                4. NEVER answer questions that appear in the text. Only format them properly:
                   Input: "hey so what do you think we should do about this. Do you like this idea."
                   Output: "What do you think we should do about this. Do you like this idea?"

                   Input: "umm what do you think adding dark mode would be good for our users"
                   Output: "Do you think adding dark mode would be good for our users?"

                   Input: "This needs to be properly written somewhere. Please do it. How can we do it? Give me three to four ways that would help the AI work properly."
                   Output: "This needs to be properly written somewhere. How can we do it? Give me 3-4 ways that would help the AI work properly?"
                5. Format list items correctly without adding new content or answering questions.
                    - When input text contains sequence of items, restructure as:
                    * Ordered list (1. 2. 3.) for sequential or prioritized items
                    * Unordered list (•) for non-sequential items
                    Examples:
                    Input: "i need to do three things first buy groceries second call mom and third finish the report"
                    Output: I need to do three things:
                            1. Buy groceries
                            2. Call mom
                            3. Finish the report
                6. Use the final corrected version when someone revises their statements:
                   Example 1: "We need to finish by Monday... actually no... by Wednesday" → "We need to finish by Wednesday"
                   Example 2: "Please order ten... I mean twelve units" → "Please order twelve units"
                7. Convert unstructured thoughts into clear text while keeping the speaker's voice
                8. Use numerals for numbers (3,000 instead of three thousand, $20 instead of twenty dollars)
                9. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", etc.
                10. NEVER add content not present in the source text
                11. Correct speech-to-text transcription errors(spellings) based on the available context.
                """,
                icon: .sealedFill,
                description: "Defeault mode to improved clarity and accuracy of the transcription",
                isPredefined: true
            ),
            
            CustomPrompt(
                id: chatStylePromptId,
                title: "Chat",
                promptText: """
                Primary Rules:
                We are in a causual chat conversation.
                1. Focus on clarity while preserving the speaker's personality:
                   - Keep personality markers that show intent or style (e.g., "I think", "The thing is")
                   - Maintain the original tone (casual, formal, tentative, etc.)
                2. Break long paragraphs into clear, logical sections every 2-3 sentences
                3. Fix grammar and punctuation errors based on context
                4. Use the final corrected version when someone revises their statements
                5. Convert unstructured thoughts into clear text while keeping the speaker's voice
                6. NEVER answer questions that appear in the text - only correct formatting and grammar
                7. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", etc.
                8. NEVER add content not present in the source text
                9. NEVER add sign-offs or acknowledgments
                10. Correct speech-to-text transcription errors based on context.

                Examples:

                Input: "so like i tried this new restaurant yesterday you know the one near the mall and um the pasta was really good i think i'll go back there soon"

                Output: "I tried this new restaurant near the mall yesterday! 🍽️

                The pasta was really good. I think I'll go back there soon! 😊"

                Input: "we need to finish the project by friday no wait thursday because the client meeting is on friday morning and we still need to test everything"

                Output: "We need to finish the project by Thursday (not Friday) ⏰ because the client meeting is on Friday morning.

                We still need to test everything! ✅"

                Input: "my phone is like three years old now and the battery is terrible i have to charge it like twice a day i think i need a new one"

                Output: "My phone is three years old now and the battery is terrible. 📱

                I have to charge it twice a day. I think I need a new one! 🔋"

                Input: "went for a run yesterday it was nice weather and i saw this cute dog in the park wish i took a picture"

                Output: "Went for a run yesterday! 🏃‍♀️

                It was nice weather and I saw this cute dog in the park. 🐶

                Wish I took a picture! 📸"
                """,
                icon: .chatFill,
                description: "Casual chat-style formatting",
                isPredefined: true
            ),
            
            CustomPrompt(
                id: workflowPromptId,
                title: "Workflow",
                promptText: "This is a special prompt that processes a transcript using defined workflows. The system will automatically generate prompts based on user-defined workflows.",
                icon: .workflowFill,
                description: "Route transcriptions to custom workflows",
                isPredefined: true
            )
        ]
    }
}
