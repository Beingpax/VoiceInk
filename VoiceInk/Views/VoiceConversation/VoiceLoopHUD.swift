import SwiftUI

struct VoiceLoopHUD: View {
    @ObservedObject var manager: VoiceConversationManager

    @State private var isTranscriptExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            // State indicator row
            HStack(spacing: 8) {
                stateIcon
                    .font(.title2)
                    .foregroundStyle(stateColor)

                Text(stateLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                // Expand/collapse transcript
                if !manager.history.messages.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTranscriptExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isTranscriptExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Current activity text
            if !currentDisplayText.isEmpty {
                Text(currentDisplayText)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(isTranscriptExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Expanded transcript
            if isTranscriptExpanded {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(manager.history.messages) { message in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: message.role == .user ? "person.fill" : "brain")
                                    .font(.system(size: 10))
                                    .foregroundStyle(message.role == .user ? .blue : .purple)
                                    .frame(width: 14)

                                Text(message.content)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)

                                if message.role == .assistant {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.content, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy response")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Computed Properties

    private var stateIcon: some View {
        Group {
            switch manager.state {
            case .idle:
                Image(systemName: "waveform")
            case .listening:
                Image(systemName: "mic.fill")
            case .thinking:
                ProgressView()
                    .controlSize(.small)
            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
            }
        }
    }

    private var stateLabel: String {
        switch manager.state {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }

    private var stateColor: Color {
        switch manager.state {
        case .idle: return .secondary
        case .listening: return .red
        case .thinking: return .orange
        case .speaking: return .blue
        }
    }

    private var currentDisplayText: String {
        switch manager.state {
        case .listening:
            return manager.currentTranscript.isEmpty ? "" : manager.currentTranscript
        case .thinking:
            return manager.currentTranscript
        case .speaking:
            return manager.lastAssistantResponse
        case .idle:
            return manager.lastAssistantResponse
        }
    }
}
