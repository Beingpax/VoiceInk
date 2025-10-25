import SwiftUI

struct TextEditorView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background and border
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFocused ? Color.accentColor.opacity(0.5) :
                            isHovering ? Color.secondary.opacity(0.3) :
                            Color.secondary.opacity(0.2),
                            lineWidth: isFocused ? (viewModel.isMinimalistMode ? 1.5 : 2) : 1
                        )
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
            
            // Text Editor
            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 14, weight: .regular, design: .default))
                .focused($isFocused)
                .frame(minHeight: viewModel.isMinimalistMode ? 220 : 260)
                .padding(viewModel.isMinimalistMode ? 6 : 8)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .onChange(of: viewModel.inputText) { _, newValue in
                    let limit = viewModel.currentCharacterLimit
                    guard newValue.count > limit else { return }

                    if viewModel.shouldAllowCharacterOverflow(for: newValue) {
                        return
                    }

                    viewModel.inputText = String(newValue.prefix(limit))
                }
            
            // Placeholder text
            if viewModel.inputText.isEmpty {
                Text("Enter text to convert to speech...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 0,
               maxWidth: .infinity,
               minHeight: viewModel.isMinimalistMode ? 220 : 260,
               maxHeight: .infinity,
               alignment: .topLeading)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            // Auto-focus on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .contextMenu {
            // Context menu options
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.inputText, forType: .string)
            }) {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.inputText.isEmpty)
            
            Button(action: {
                if let string = NSPasteboard.general.string(forType: .string) {
                    viewModel.inputText = string
                }
            }) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            
            Divider()
            
            Button(action: {
                viewModel.inputText = ""
            }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.inputText.isEmpty)
            
            Divider()
            
            Menu("Insert Sample Text") {
                Button("Short Sample") {
                    viewModel.inputText = "Hello! This is a sample text to demonstrate the text-to-speech functionality. The app supports multiple providers and voices, allowing you to create natural-sounding speech from any text."
                }
                
                Button("Medium Sample") {
                    viewModel.inputText = """
                    Welcome to the Text-to-Speech Converter! This powerful application transforms your written text into natural-sounding speech using advanced AI technology.
                    
                    You can choose from multiple providers including OpenAI, ElevenLabs, and Google Cloud Text-to-Speech. Each provider offers unique voices with different characteristics and languages.
                    
                    The app features comprehensive playback controls, allowing you to play, pause, adjust speed, and control volume. You can also export the generated audio in various formats for use in your projects.
                    """
                }
                
                Button("Long Sample") {
                    viewModel.inputText = """
                    The art of text-to-speech synthesis has evolved dramatically over the past decade. What once sounded robotic and unnatural has transformed into voices that are nearly indistinguishable from human speech.
                    
                    Modern TTS systems use deep learning models trained on vast amounts of human speech data. These neural networks learn the subtle patterns of human vocalization, including intonation, rhythm, and emotional expression.
                    
                    The applications are endless: from accessibility tools for the visually impaired, to audiobook narration, virtual assistants, and content creation. Educational institutions use TTS to make learning materials more accessible, while businesses employ it for customer service automation.
                    
                    As we look to the future, the boundary between synthetic and human speech continues to blur. Voice cloning technology can now recreate specific voices with remarkable accuracy, opening new possibilities for preserving voices and creating personalized experiences.
                    
                    This convergence of technology and human expression represents not just a technical achievement, but a fundamental shift in how we interact with information and each other in the digital age.
                    """
                }
            }
        }
    }
}

// Text Editor Extensions for better functionality
extension TextEditorView {
    // Helper function to count words
    private func wordCount(_ text: String) -> Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }
    
    // Helper function to estimate reading time
    private func estimatedReadingTime(_ text: String) -> String {
        let words = wordCount(text)
        let wordsPerMinute = 150 // Average reading speed
        let minutes = Double(words) / Double(wordsPerMinute)
        
        if minutes < 1 {
            return "< 1 min"
        } else if minutes < 60 {
            return "\(Int(minutes)) min"
        } else {
            let hours = Int(minutes / 60)
            let remainingMinutes = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// Preview
struct TextEditorView_Previews: PreviewProvider {
    static var previews: some View {
        TextEditorView()
            .environmentObject(TTSViewModel())
            .frame(width: 600, height: 400)
            .padding()
    }
}
