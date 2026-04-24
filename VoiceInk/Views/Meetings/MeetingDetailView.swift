import SwiftUI
import SwiftData
import OSLog

// MARK: - Helpers

private func meetingFormatTime(_ time: TimeInterval) -> String {
    let total = Int(max(0, time))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

private func speakerDisplayFallback(_ speaker: Speaker) -> String {
    if !speaker.displayName.isEmpty { return speaker.displayName }
    // "speaker_0" → "Speaker 1", "speaker_2" → "Speaker 3", etc.
    let label = speaker.diarizerLabel
    if label.hasPrefix("speaker_"), let n = Int(label.dropFirst("speaker_".count)) {
        return "Speaker \(n + 1)"
    }
    return label
}

private let speakerPillColors: [Color] = [
    Color(red: 0.20, green: 0.47, blue: 0.95),  // blue
    Color(red: 0.85, green: 0.40, blue: 0.20),  // orange
    Color(red: 0.22, green: 0.72, blue: 0.53),  // teal
    Color(red: 0.72, green: 0.30, blue: 0.82),  // purple
    Color(red: 0.90, green: 0.65, blue: 0.10)   // amber
]

private func speakerColor(_ speaker: Speaker) -> Color {
    let idx = abs(speaker.id.hashValue) % speakerPillColors.count
    return speakerPillColors[idx]
}

// MARK: - Status Chip (local, independent of list-view's private struct)

private struct MeetingStatusChip: View {
    let label: String
    let status: MeetingStageStatus
    let onRerun: (() -> Void)?

    private var chipColor: Color {
        switch status {
        case .done:    return .green
        case .running: return .blue
        case .failed:  return .red
        case .pending: return Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                if status == .running {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                Text("\(label) \(status.rawValue)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(chipColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(chipColor.opacity(0.12))
            .clipShape(Capsule())

            if status == .failed, let rerun = onRerun {
                Button("Re-run", action: rerun)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Speaker Pill / Rename

private struct SpeakerPillView: View {
    let speaker: Speaker
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        Group {
            if isEditing {
                TextField("Name", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 60, maxWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(speakerColor(speaker))
                    .clipShape(Capsule())
                    .onAppear { editedName = speakerDisplayFallback(speaker) }
                    .onExitCommand { cancelRename() }
            } else {
                Text(speakerDisplayFallback(speaker))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(speakerColor(speaker))
                    .clipShape(Capsule())
                    .onTapGesture {
                        editedName = speakerDisplayFallback(speaker)
                        isEditing = true
                    }
                    .help("Click to rename speaker")
                    .onHover { inside in
                        if inside { NSCursor.iBeam.push() } else { NSCursor.pop() }
                    }
            }
        }
    }

    private func commitRename() {
        isEditing = false
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Fall back to derived label; set displayName to empty so fallback kicks in
            speaker.displayName = ""
        } else {
            speaker.displayName = trimmed
        }
        try? modelContext.save()
    }

    private func cancelRename() {
        isEditing = false
    }
}

// MARK: - Segment Row

private struct SegmentRowView: View {
    let segment: Segment
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Speaker pill
            if let speaker = segment.speaker {
                SpeakerPillView(speaker: speaker)
            } else {
                Text("?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary)
                    .clipShape(Capsule())
            }

            // Timestamp
            Text("[\(meetingFormatTime(segment.startSec))]")
                .font(.system(size: 11).monospaced())
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            // Text
            Text(segment.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isActive
                ? Color.accentColor.opacity(0.10)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Transcript Pane

private struct TranscriptPane: View {
    let meeting: Meeting
    @ObservedObject var audioPlayer: AudioPlayerManager

    private var sortedSegments: [Segment] {
        meeting.segments.sorted { $0.startSec < $1.startSec }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(sortedSegments.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if sortedSegments.isEmpty {
                transcriptEmptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedSegments) { segment in
                            let isActive = audioPlayer.duration > 0
                                && audioPlayer.currentTime >= segment.startSec
                                && audioPlayer.currentTime < segment.endSec
                            SegmentRowView(
                                segment: segment,
                                isActive: isActive,
                                onTap: {
                                    audioPlayer.seek(to: segment.startSec)
                                    audioPlayer.play()
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Transcript not ready")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(statusDescription)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var statusDescription: String {
        switch meeting.transcriptionStage {
        case .pending: return "Transcription has not started yet."
        case .running: return "Transcription is in progress…"
        case .failed:  return "Transcription failed. Try re-running."
        case .done:    return "No segments found."
        }
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(title: String, expanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            Divider()
        }
    }
}

// MARK: - Summary Pane

private struct SummaryPane: View {
    let meeting: Meeting
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingDetailView")
    @EnvironmentObject private var pipeline: MeetingPipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            summaryContent
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        let status = meeting.summaryStage

        if status == .pending || status == .running {
            VStack(spacing: 10) {
                Spacer()
                if status == .running {
                    ProgressView()
                        .controlSize(.regular)
                }
                Text(status == .running ? "Generating summary…" : "Summary not ready")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(status == .running ? "This may take a moment." : "Processing hasn't started yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if status == .failed {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text("Summary failed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Re-run Summary") {
                    Task { await pipeline.rerunSummary(for: meeting) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if status == .done {
            let hasTldr   = !(meeting.summaryTldr ?? "").isEmpty
            let hasPoints = !meeting.summaryKeyPoints.isEmpty
            let hasItems  = !meeting.summaryActionItems.isEmpty

            if !hasTldr && !hasPoints && !hasItems {
                VStack {
                    Spacer()
                    Text("Summary is empty")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if hasTldr {
                            CollapsibleSection(title: "TL;DR") {
                                Text(meeting.summaryTldr ?? "")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if hasPoints {
                            CollapsibleSection(title: "Key Points") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(meeting.summaryKeyPoints, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("•")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                            Text(point)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.primary)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        if hasItems {
                            CollapsibleSection(title: "Action Items") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(meeting.summaryActionItems, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "circle")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 2)
                                            Text(item)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.primary)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // Unknown status fallback
            VStack {
                Spacer()
                Text("Summary status unknown (\(status))")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - Audio Player Strip

private struct MeetingAudioPlayerStrip: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    let audioAvailable: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 6) {
                if audioAvailable {
                    WaveformView(
                        samples: audioPlayer.waveformSamples,
                        currentTime: audioPlayer.currentTime,
                        duration: audioPlayer.duration,
                        isLoading: audioPlayer.isLoadingWaveform,
                        onSeek: { audioPlayer.seek(to: $0) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Text(meetingFormatTime(audioPlayer.currentTime))
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .leading)

                        Spacer()

                        // Play / Pause
                        Button(action: {
                            audioPlayer.isPlaying ? audioPlayer.pause() : audioPlayer.play()
                        }) {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        // Playback rate
                        Button(action: { audioPlayer.cyclePlaybackRate() }) {
                            Text(rateLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(audioPlayer.playbackRate == 1.0 ? .secondary : .primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(audioPlayer.playbackRate == 1.0 ? 0.06 : 0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Cycle playback speed")

                        Spacer()

                        Text(meetingFormatTime(audioPlayer.duration))
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Image(systemName: "waveform.slash")
                            .foregroundStyle(.secondary)
                        Text("No audio file available")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private var rateLabel: String {
        switch audioPlayer.playbackRate {
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default:  return "1×"
        }
    }
}

// MARK: - Main Detail View

struct MeetingDetailView: View {
    let meeting: Meeting
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingDetailView")

    @StateObject private var audioPlayer = AudioPlayerManager()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pipeline: MeetingPipeline

    private var audioAvailable: Bool {
        !meeting.audioFilePath.isEmpty
            && FileManager.default.fileExists(atPath: meeting.audioFilePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header
            headerView
                .padding(16)

            Divider()

            // 2. Body — split view
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left — Transcript (~60%)
                    TranscriptPane(meeting: meeting, audioPlayer: audioPlayer)
                        .frame(width: geo.size.width * 0.60)

                    Divider()

                    // Right — Summary (~40%)
                    SummaryPane(meeting: meeting)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // 3. Footer — audio player
            MeetingAudioPlayerStrip(audioPlayer: audioPlayer, audioAvailable: audioAvailable)
        }
        .navigationTitle(meeting.title)
        .onAppear {
            if audioAvailable {
                audioPlayer.loadAudio(from: URL(fileURLWithPath: meeting.audioFilePath))
            }
        }
        .onDisappear {
            audioPlayer.cleanup()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            if !meeting.subtitle.isEmpty {
                Text(meeting.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                MeetingStatusChip(
                    label: "Tx",
                    status: meeting.transcriptionStage,
                    onRerun: meeting.transcriptionStage == .failed ? {
                        Task { await pipeline.rerunTranscription(for: meeting) }
                    } : nil
                )
                MeetingStatusChip(
                    label: "Dx",
                    status: meeting.diarizationStage,
                    onRerun: meeting.diarizationStage == .failed ? {
                        Task { await pipeline.rerunDiarization(for: meeting) }
                    } : nil
                )
                MeetingStatusChip(
                    label: "Sm",
                    status: meeting.summaryStage,
                    onRerun: meeting.summaryStage == .failed ? {
                        Task { await pipeline.rerunSummary(for: meeting) }
                    } : nil
                )
                Spacer()
            }
        }
    }
}
