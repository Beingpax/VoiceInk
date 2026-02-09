import SwiftUI

enum TranscriptionTab: String, CaseIterable {
    case original = "Original"
    case enhanced = "Enhanced"
}

struct TranscriptionResultView: View {
    let transcription: Transcription
    
    @State private var selectedTab: TranscriptionTab = .original
    
    private var availableTabs: [TranscriptionTab] {
        var tabs: [TranscriptionTab] = [.original]
        if transcription.enhancedText != nil {
            tabs.append(.enhanced)
        }
        return tabs
    }
    
    private var textForSelectedTab: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Result")
                .font(.headline)
            
            if availableTabs.count > 1 {
                HStack(spacing: 2) {
                    ForEach(availableTabs, id: \.self) { tab in
                        TabButton(
                            title: tab.rawValue,
                            isSelected: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }
                    Spacer()
                    AnimatedCopyButton(textToCopy: textForSelectedTab)
                    AnimatedSaveButton(textToSave: textForSelectedTab)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            } else {
                HStack {
                    Spacer()
                    AnimatedCopyButton(textToCopy: textForSelectedTab)
                    AnimatedSaveButton(textToSave: textForSelectedTab)
                }
            }
            
            ScrollView {
                Text(textForSelectedTab)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private struct TabButton: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .contentShape(.capsule)
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
}
