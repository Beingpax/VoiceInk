import SwiftUI
import SwiftData

struct ScratchpadView: View {
    @EnvironmentObject private var manager: DailyScratchpadManager
    @EnvironmentObject private var whisperState: WhisperState
    @State private var searchText = ""
    @State private var showingSearch = false
    
    var body: some View {
        Group {
            if let currentDate = manager.currentViewDate {
                ScratchpadEditorView(manager: manager, date: currentDate)
            } else {
                cardView
            }
        }
        .background(Color(.controlBackgroundColor))
        .onAppear {
            manager.restoreLastView()
        }
    }
    
    private var cardView: some View {
        VStack(spacing: 0) {
            headerView
            
            if showingSearch {
                searchBar
            }
            
            if filteredScratchpads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredScratchpads) { scratchpad in
                            ScratchpadCardView(scratchpad: scratchpad) {
                                openEditor(for: scratchpad.date)
                            }
                        }
                    }
                    .padding(24)
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scratchpad")
                    .font(.system(size: 24, weight: .bold))
                Text("Daily voice memos and notes")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showingSearch.toggle() }) {
                Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search across all days...", text: $searchText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(12)
        .background(CardBackground(isSelected: false))
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No voice memos yet")
                .font(.system(size: 24, weight: .semibold, design: .default))
            
            Text("Use the record button or keyboard shortcut to start capturing voice memos")
                .font(.system(size: 18, weight: .regular, design: .default))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CardBackground(isSelected: false))
        .padding(24)
    }
    
    private var filteredScratchpads: [DailyScratchpad] {
        if searchText.isEmpty {
            return manager.scratchpads
        } else {
            return manager.scratchpads.filter { 
                $0.content.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    private func openEditor(for date: String) {
        manager.setCurrentViewDate(date)
    }
}

struct ScratchpadCardView: View {
    let scratchpad: DailyScratchpad
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if scratchpad.isToday {
                            Text("Today")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(scratchpad.entryCount) entries")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text(scratchpad.lastModified, style: .time)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(scratchpad.previewText)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .background(CardBackground(isSelected: false))
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = dateFormatter.date(from: scratchpad.date) {
            return formatter.string(from: date)
        }
        
        return scratchpad.date
    }
}

#Preview {
    let container = try! ModelContainer(for: Transcription.self)
    return ScratchpadView()
        .environmentObject(DailyScratchpadManager())
        .environmentObject(WhisperState(modelContext: container.mainContext))
}