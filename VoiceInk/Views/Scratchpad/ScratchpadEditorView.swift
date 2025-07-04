import SwiftUI
import SwiftData

struct ScratchpadEditorView: View {
    @ObservedObject var manager: DailyScratchpadManager
    @EnvironmentObject private var whisperState: WhisperState
    let date: String
    
    @State private var content: String = ""
    @State private var hasUnsavedChanges = false
    @State private var autoSaveTask: Task<Void, Never>?
    
    private var currentScratchpad: DailyScratchpad? {
        manager.getScratchpad(for: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            editorView
        }
        .background(Color(.controlBackgroundColor))
        .onAppear {
            loadCurrentContent()
        }
        .onDisappear {
            saveChanges()
        }
        .onChange(of: manager.scratchpads) { _, _ in
            loadCurrentContent()
        }
    }
    
    private var headerView: some View {
        HStack {
            // Back button styled to match record button
            Button(action: { manager.setCurrentViewDate(nil) }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary)
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Centered date section
            VStack(spacing: 2) {
                Text(formattedDate)
                    .font(.system(size: 18, weight: .semibold))
                
                if isToday {
                    Text("Today")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if hasUnsavedChanges {
                    Text("Unsaved")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Button(action: { 
                    Task {
                        await whisperState.startScratchpadRecording()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 16))
                        Text("Record")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(whisperState.isRecording || whisperState.isTranscribing)
                .opacity((whisperState.isRecording || whisperState.isTranscribing) ? 0.6 : 1.0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.controlBackgroundColor))
    }
    
    private var editorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if content.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No entries for this day yet")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Use the record button or keyboard shortcut to add voice memos")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
                } else {
                    TextEditor(text: $content)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .onChange(of: content) { _, newValue in
                            hasUnsavedChanges = true
                            debounceAutoSave()
                        }
                        .frame(minHeight: 400)
                }
            }
            .padding(20)
        }
        .background(Color(.textBackgroundColor))
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = dateFormatter.date(from: date) {
            return formatter.string(from: date)
        }
        
        return date
    }
    
    private var isToday: Bool {
        date == DailyScratchpad.todayString
    }
    
    private func loadCurrentContent() {
        if let scratchpad = currentScratchpad {
            content = scratchpad.content
        } else {
            content = ""
        }
        hasUnsavedChanges = false
    }
    
    private func saveChanges() {
        guard hasUnsavedChanges else { return }
        
        if let scratchpad = currentScratchpad {
            manager.updateScratchpad(scratchpad, content: content)
        } else {
            let newScratchpad = manager.getOrCreateScratchpad(for: date)
            manager.updateScratchpad(newScratchpad, content: content)
        }
        hasUnsavedChanges = false
    }
    
    private func debounceAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !Task.isCancelled && hasUnsavedChanges {
                await MainActor.run {
                    saveChanges()
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Transcription.self)
    return ScratchpadEditorView(manager: DailyScratchpadManager(), date: "2024-01-01")
        .environmentObject(WhisperState(modelContext: container.mainContext))
}