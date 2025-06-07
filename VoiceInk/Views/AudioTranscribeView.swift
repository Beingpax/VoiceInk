import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct AudioTranscribeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperState: WhisperState
    @StateObject private var transcriptionManager = AudioTranscriptionManager.shared
    @State private var isDropTargeted = false
    @State private var selectedAudioURL: URL?
    @State private var isAudioFileSelected = false
    @State private var isEnhancementEnabled = false
    @State private var selectedPromptId: UUID?
    @State private var isMeetingFile: Bool = false // Added for meeting toggle
    
    var body: some View {
        VStack(spacing: 0) {
            if transcriptionManager.isProcessing {
                processingView
            } else {
                dropZoneView
            }
            
            Divider()
                .padding(.vertical)
            
            // Show current transcription result
            if let transcription = transcriptionManager.currentTranscription {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Transcription Result")
                            .font(.headline)
                        
                        if let enhancedText = transcription.enhancedText {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Enhanced")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        AnimatedCopyButton(textToCopy: enhancedText)
                                        AnimatedSaveButton(textToSave: enhancedText)
                                    }
                                }
                                Text(enhancedText)
                                    .textSelection(.enabled)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Original")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        AnimatedCopyButton(textToCopy: transcription.text)
                                        AnimatedSaveButton(textToSave: transcription.text)
                                    }
                                }
                                Text(transcription.text)
                                    .textSelection(.enabled)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Transcription")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        AnimatedCopyButton(textToCopy: transcription.text)
                                        AnimatedSaveButton(textToSave: transcription.text)
                                    }
                                }
                                Text(transcription.text)
                                    .textSelection(.enabled)
                            }
                        }
                        
                        HStack {
                            Text("Duration: \(formatDuration(transcription.duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Error", isPresented: .constant(transcriptionManager.errorMessage != nil)) {
            Button("OK", role: .cancel) {
                transcriptionManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = transcriptionManager.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var dropZoneView: some View {
        VStack(spacing: 16) {
            if isAudioFileSelected {
                VStack(spacing: 16) {
                    Text("Audio file selected: \(selectedAudioURL?.lastPathComponent ?? "")")
                        .font(.headline)

                    // Meeting Recording Toggle
                    Toggle("This is a meeting recording", isOn: $isMeetingFile)
                        .toggleStyle(.switch)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                    
                    // AI Enhancement Settings
                    if let enhancementService = whisperState.getEnhancementService() {
                        VStack(spacing: 16) {
                            // AI Enhancement and Prompt in the same row
                            HStack(spacing: 16) {
                                Toggle("AI Enhancement", isOn: $isEnhancementEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: isEnhancementEnabled) { oldValue, newValue in
                                        enhancementService.isEnhancementEnabled = newValue
                                    }
                                
                                if isEnhancementEnabled {
                                    Divider()
                                        .frame(height: 20)
                                    
                                    // Prompt Selection
                                    HStack(spacing: 8) {
                                        Text("Prompt:")
                                            .font(.subheadline)
                                        
                                        Menu {
                                            ForEach(enhancementService.allPrompts) { prompt in
                                                Button {
                                                    enhancementService.setActivePrompt(prompt)
                                                    selectedPromptId = prompt.id
                                                } label: {
                                                    HStack {
                                                        Image(systemName: prompt.icon.rawValue)
                                                            .foregroundColor(.accentColor)
                                                        Text(prompt.title)
                                                        if selectedPromptId == prompt.id {
                                                            Spacer()
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(enhancementService.allPrompts.first(where: { $0.id == selectedPromptId })?.title ?? "Select Prompt")
                                                    .foregroundColor(.primary)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color(.controlBackgroundColor))
                                            )
                                        }
                                        .fixedSize()
                                        .disabled(!isEnhancementEnabled)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.windowBackgroundColor).opacity(0.4))
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .onAppear {
                            // Initialize local state from enhancement service
                            isEnhancementEnabled = enhancementService.isEnhancementEnabled
                            selectedPromptId = enhancementService.selectedPromptId
                        }
                    }
                    
                    // Action Buttons in a row
                    HStack(spacing: 12) {
                        Button("Start Transcription") {
                            if let url = selectedAudioURL {
                                transcriptionManager.startProcessing(
                                    url: url,
                                    modelContext: modelContext,
                                    whisperState: whisperState,
                                    isMeeting: isMeetingFile // Pass the toggle state
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Choose Different File") {
                            selectedAudioURL = nil
                            isAudioFileSelected = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.windowBackgroundColor).opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    style: StrokeStyle(
                                        lineWidth: 2,
                                        dash: [8]
                                    )
                                )
                                .foregroundColor(isDropTargeted ? .blue : .gray.opacity(0.5))
                        )
                    
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundColor(isDropTargeted ? .blue : .gray)
                        
                        Text("Drop audio file here")
                            .font(.headline)
                        
                        Text("or")
                            .foregroundColor(.secondary)
                        
                        Button("Choose File") {
                            selectFile()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(32)
                }
                .frame(height: 200)
                .padding(.horizontal)
            }
            
            Text("Supported formats: WAV, MP3, M4A, AIFF")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onDrop(of: [.audio, .fileURL], isTargeted: $isDropTargeted) { providers in
            Task {
                await handleDroppedFile(providers)
            }
            return true
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            Text(transcriptionManager.processingPhase.message)
                .font(.headline)
            Text(transcriptionManager.messageLog)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio,
            .wav,
            .mp3,
            .mpeg4Audio,
            .aiff
        ]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedAudioURL = url
                isAudioFileSelected = true
            }
        }
    }
    
    private func handleDroppedFile(_ providers: [NSItemProvider]) async {
        guard let provider = providers.first else { return }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            try? await provider.loadItem(forTypeIdentifier: UTType.audio.identifier) { item, error in
                if let url = item as? URL {
                    Task { @MainActor in
                        selectedAudioURL = url
                        isAudioFileSelected = true
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
} 
