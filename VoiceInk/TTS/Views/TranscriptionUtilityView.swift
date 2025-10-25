import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TranscriptionUtilityView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var showingFileImporter = false

    private let presets: [(label: String, instruction: String)] = [
        (
            label: "Australian English",
            instruction: "Rewrite the transcript using Australian English spelling and idioms. Fix obvious transcription errors, ensure sentences read naturally, and keep the meaning intact."
        ),
        (
            label: "Professional tone",
            instruction: "Polish the transcript into a professional business document with clear paragraphs and precise wording while preserving factual details."
        ),
        (
            label: "Meeting minutes",
            instruction: "Transform the transcript into concise meeting minutes with clear sections for context, decisions, and next steps. Remove filler words and keep names where available."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            captureSection
            cleanupSection
            statusSection
            resultsSection
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select an audio file to transcribe, or reuse the latest transcript.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Transcription provider", selection: $viewModel.selectedTranscriptionProvider) {
                ForEach(TranscriptionProviderType.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            if !viewModel.transcriptionProviderHasCredentials(viewModel.selectedTranscriptionProvider) {
                Text("\(viewModel.selectedTranscriptionProvider.displayName) API key required in Settings.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 10) {
                Button {
                    if viewModel.isTranscriptionRecording {
                        viewModel.stopTranscriptionRecording()
                    } else {
                        viewModel.startTranscriptionRecording()
                    }
                } label: {
                    Label(viewModel.isTranscriptionRecording ? "Stop" : "Record",
                          systemImage: viewModel.isTranscriptionRecording ? "stop.fill" : "record.circle")
                        .foregroundColor(viewModel.isTranscriptionRecording ? .white : .accentColor)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isTranscriptionRecording ? .red : .accentColor)

                if viewModel.isTranscriptionRecording {
                    Button {
                        viewModel.cancelTranscriptionRecording()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    pickAudioFile()
                } label: {
                    Label("Choose audio…", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if viewModel.isTranscriptionRecording {
                HStack(spacing: 12) {
                    ProgressView(value: Double(viewModel.transcriptionRecordingLevel))
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                    Text("Recording… \(formatDuration(viewModel.transcriptionRecordingDuration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.transcriptionRecordingDuration > 0 {
                Text("Last recording: \(formatDuration(viewModel.transcriptionRecordingDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    viewModel.insertTranscriptionIntoEditor(useCleanedText: false)
                } label: {
                    Label("Use transcript", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    viewModel.insertTranscriptionIntoEditor(useCleanedText: true)
                } label: {
                    Label("Use cleaned", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled((viewModel.transcriptionCleanupResult?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cleanup instructions")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Pick a preset or provide custom guidance to polish the transcript.")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        let isActive = viewModel.transcriptionCleanupLabel == preset.label
                        Button(preset.label) {
                            viewModel.setTranscriptionCleanupPreset(instruction: preset.instruction, label: preset.label)
                        }
                        .buttonStyle(.bordered)
                        .tint(isActive ? .accentColor : .secondary)
                    }

                    Button("Clear") {
                        viewModel.clearTranscriptionCleanupPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcriptionCleanupInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            TextEditor(text: Binding(get: {
                viewModel.transcriptionCleanupInstruction
            }, set: { newValue in
                viewModel.transcriptionCleanupInstruction = newValue
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.transcriptionCleanupLabel = nil
                }
            }))
            .font(.system(size: 13))
            .frame(minHeight: 80, idealHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2))
            )
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(viewModel.transcriptionStageDescription, systemImage: "bolt.horizontal.circle")
                    .font(.subheadline)
                Spacer()
                if viewModel.isTranscriptionInProgress {
                    ProgressView(value: viewModel.transcriptionProgress)
                        .frame(width: 140)
                }
            }

            if let error = viewModel.transcriptionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.transcriptionText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcript", systemImage: "doc.text")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(viewModel.transcriptionText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(8)
                }
            }

            if let summary = viewModel.transcriptionSummary {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Summary", systemImage: "text.append")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if !summary.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(summary.summary)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }

                    if !summary.actionItems.isEmpty {
                        Divider()
                        Text("Action items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(summary.actionItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• \(item.text)")
                                    .font(.system(size: 13))
                                if let owner = item.ownerHint, !owner.isEmpty {
                                    Text("Owner: \(owner)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let due = item.dueDateHint, !due.isEmpty {
                                    Text("Timing: \(due)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if let schedule = summary.scheduleRecommendation {
                        Divider()
                        Text("Schedule recommendation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schedule.title)
                                .font(.system(size: 13))
                            if let window = schedule.startWindow {
                                Text("Window: \(window)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let duration = schedule.durationMinutes {
                                Text("Duration: \(duration) minutes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let participants = schedule.participants, !participants.isEmpty {
                                Text("Participants: \(participants.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if let cleaned = viewModel.transcriptionCleanupResult {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(cleaned.label ?? "Cleaned transcript", systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(cleaned.output)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(6)
                }
            }

            if !viewModel.transcriptionSegments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Segments", systemImage: "waveform.path")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.transcriptionSegments) { segment in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Segment \(segment.id + 1)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text("\(formatTime(segment.startTime)) – \(formatTime(segment.endTime))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(segment.text)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.primary)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }

    private func pickAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Transcribe"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.transcribeAudioFile(at: url, shouldDeleteAfterTranscription: false)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let interval = Int(seconds.rounded())
        let minutes = interval / 60
        let secs = interval % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        guard value > 0 else { return "00:00" }
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
