import Foundation
import SwiftData
import AVFoundation
import OSLog
import UniformTypeIdentifiers

// Opaque progress token for future per-import progress UI.
struct ImportProgress {
    var stage: String
}

@MainActor
final class MeetingPipeline: ObservableObject {
    @Published var activeImports: [UUID: ImportProgress] = [:]

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingPipeline")
    private let modelContext: ModelContext
    private let transcriptionRegistry: TranscriptionServiceRegistry
    private let diarizationRegistry: DiarizationServiceRegistry
    private let summarizerRegistry: MeetingSummarizerRegistry
    private let engine: VoiceInkEngine

    private static let supportedAudioTypes: [UTType] = [
        .mpeg4Audio, .mp3, .wav, .aiff,
        UTType("public.aac-audio") ?? .audio,
        UTType("org.xiph.flac") ?? .audio
    ]
    private static let supportedVideoTypes: [UTType] = [
        .mpeg4Movie, .movie, .quickTimeMovie,
        UTType("public.m4v-video") ?? .movie
    ]

    init(
        modelContext: ModelContext,
        transcriptionRegistry: TranscriptionServiceRegistry,
        diarizationRegistry: DiarizationServiceRegistry = .shared,
        summarizerRegistry: MeetingSummarizerRegistry = .shared,
        engine: VoiceInkEngine
    ) {
        self.modelContext = modelContext
        self.transcriptionRegistry = transcriptionRegistry
        self.diarizationRegistry = diarizationRegistry
        self.summarizerRegistry = summarizerRegistry
        self.engine = engine
    }

    // MARK: - Public entry points

    @discardableResult
    func importMeeting(from sourceURL: URL) async -> Meeting {
        let id = UUID()
        activeImports[id] = ImportProgress(stage: "preparing")

        // Validate file type
        guard isSupported(url: sourceURL) else {
            logger.warning("Unsupported file type for: \(sourceURL.lastPathComponent, privacy: .public)")
            let bad = Meeting(
                title: sourceURL.deletingPathExtension().lastPathComponent,
                audioFilePath: "",
                durationSec: 0,
                transcriptionStatus: .failed,
                diarizationStatus: .failed,
                summaryStatus: .failed
            )
            modelContext.insert(bad)
            try? modelContext.save()
            activeImports.removeValue(forKey: id)
            return bad
        }

        // Prepare destination
        let meetingsDir = appSupportURL().appendingPathComponent("Meetings")
        do {
            try FileManager.default.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Meetings dir: \(error.localizedDescription, privacy: .public)")
        }
        let destURL = meetingsDir.appendingPathComponent("\(id.uuidString).wav")

        // Insert Meeting row FIRST so the UI shows a spinner immediately. Audio path + duration filled in after extraction.
        let title = sourceURL.deletingPathExtension().lastPathComponent
        // Start as "pending" per stage; each stage flips to "running" when it begins.
        let meeting = Meeting(
            id: id,
            title: title,
            audioFilePath: destURL.path,
            durationSec: 0,
            transcriptionStatus: .pending,
            diarizationStatus: .pending,
            summaryStatus: .pending
        )
        modelContext.insert(meeting)
        try? modelContext.save()

        // Extract/copy audio
        activeImports[id] = ImportProgress(stage: "extracting")
        let audioReady = await extractAudio(from: sourceURL, to: destURL)

        guard audioReady else {
            // Clean up the partial .wav so a re-import on the same file doesn't race against a half-written file.
            try? FileManager.default.removeItem(at: destURL)
            meeting.audioFilePath = ""
            meeting.transcriptionStage = .failed
            meeting.diarizationStage = .failed
            meeting.summaryStage = .failed
            try? modelContext.save()
            activeImports.removeValue(forKey: id)
            return meeting
        }

        meeting.durationSec = await probeDuration(url: destURL)
        try? modelContext.save()

        // Stage: transcribe
        activeImports[id] = ImportProgress(stage: "transcribing")
        meeting.transcriptionStage = .running
        try? modelContext.save()
        let transcriptSegments = await runTranscription(audioURL: destURL)
        guard let segments = transcriptSegments else {
            meeting.transcriptionStage = .failed
            meeting.diarizationStage = .failed
            meeting.summaryStage = .failed
            try? modelContext.save()
            activeImports.removeValue(forKey: id)
            return meeting
        }
        meeting.transcriptionStage = .done
        try? modelContext.save()

        // Stage: diarize
        activeImports[id] = ImportProgress(stage: "diarizing")
        meeting.diarizationStage = .running
        try? modelContext.save()
        let diarized = await runDiarization(audioURL: destURL, meeting: meeting, transcriptSegments: segments)
        if !diarized {
            meeting.diarizationStage = .failed
            meeting.summaryStage = .failed
            try? modelContext.save()
            activeImports.removeValue(forKey: id)
            return meeting
        }
        meeting.diarizationStage = .done
        try? modelContext.save()

        // Stage: summarize
        activeImports[id] = ImportProgress(stage: "summarizing")
        meeting.summaryStage = .running
        try? modelContext.save()
        await runSummary(meeting: meeting)
        try? modelContext.save()

        activeImports.removeValue(forKey: id)
        return meeting
    }

    // Reruns transcription → diarization → summary from scratch.
    func rerunTranscription(for meeting: Meeting) async {
        guard !meeting.audioFilePath.isEmpty else { return }
        let audioURL = URL(fileURLWithPath: meeting.audioFilePath)

        meeting.transcriptionStage = .running
        meeting.diarizationStage = .running
        meeting.summaryStage = .running
        deleteSegmentsAndSpeakers(for: meeting)
        try? modelContext.save()

        let transcriptSegments = await runTranscription(audioURL: audioURL)
        guard let segments = transcriptSegments else {
            meeting.transcriptionStage = .failed
            meeting.diarizationStage = .failed
            meeting.summaryStage = .failed
            try? modelContext.save()
            return
        }
        meeting.transcriptionStage = .done
        try? modelContext.save()

        let diarized = await runDiarization(audioURL: audioURL, meeting: meeting, transcriptSegments: segments)
        if !diarized {
            meeting.diarizationStage = .failed
            meeting.summaryStage = .failed
            try? modelContext.save()
            return
        }
        meeting.diarizationStage = .done
        try? modelContext.save()

        await runSummary(meeting: meeting)
        try? modelContext.save()
    }

    // Re-diarizes using existing transcript segments extracted from Segment rows.
    // Does NOT re-run transcription or summary.
    func rerunDiarization(for meeting: Meeting) async {
        guard !meeting.audioFilePath.isEmpty else { return }
        let audioURL = URL(fileURLWithPath: meeting.audioFilePath)

        // Extract TranscriptSegment values from the existing Segment rows before deleting them.
        let existing = meeting.segments.sorted { $0.startSec < $1.startSec }
        let transcriptSegments = existing.map {
            TranscriptSegment(startSec: $0.startSec, endSec: $0.endSec, text: $0.text)
        }

        meeting.diarizationStage = .running
        deleteSegmentsAndSpeakers(for: meeting)
        try? modelContext.save()

        let diarized = await runDiarization(audioURL: audioURL, meeting: meeting, transcriptSegments: transcriptSegments)
        meeting.diarizationStage = diarized ? .done : .failed
        try? modelContext.save()
    }

    // Re-runs summary only.
    func rerunSummary(for meeting: Meeting) async {
        meeting.summaryStage = .running
        try? modelContext.save()
        await runSummary(meeting: meeting)
        try? modelContext.save()
    }

    // MARK: - Stage implementations

    private func runTranscription(audioURL: URL) async -> [TranscriptSegment]? {
        let model = engine.transcriptionModelManager.currentMeetingsTranscriptionModel
        guard let model = model else {
            logger.error("No Meetings transcription model selected. Configure one in Settings → AI Models → Meetings Transcription Model.")
            return nil
        }
        let effectiveModel = transcriptionRegistry.effectiveBatchModel(for: model)
        let service = transcriptionRegistry.service(for: effectiveModel.provider)

        for attempt in 1...2 {
            do {
                let segs = try await service.transcribeWithSegments(audioURL: audioURL, model: effectiveModel)
                return segs
            } catch {
                logger.error("Transcription attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        return nil
    }

    // Returns true on success. Builds Speaker + Segment rows and inserts them.
    private func runDiarization(audioURL: URL, meeting: Meeting, transcriptSegments: [TranscriptSegment]) async -> Bool {
        let diarService = diarizationRegistry.currentService()

        var speakerSegments: [SpeakerSegment] = []
        for attempt in 1...2 {
            do {
                speakerSegments = try await diarService.diarize(audioURL: audioURL)
                break
            } catch {
                logger.error("Diarization attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                if attempt == 2 {
                    return false
                }
            }
        }

        // Build speaker map — ordered by first appearance.
        var labelToSpeaker: [String: Speaker] = [:]
        var orderedLabels: [String] = []

        for ts in transcriptSegments {
            let label = bestMatchingLabel(for: ts, in: speakerSegments)
            if labelToSpeaker[label] == nil {
                let n = orderedLabels.count + 1
                let spk = Speaker(diarizerLabel: label, displayName: "Speaker \(n)", meeting: meeting)
                modelContext.insert(spk)
                labelToSpeaker[label] = spk
                orderedLabels.append(label)
            }
        }

        // Fallback speaker for unmatched segments (silence gaps etc.)
        let fallbackSpeaker = labelToSpeaker[orderedLabels.first ?? ""] ?? {
            let spk = Speaker(diarizerLabel: "speaker_0", displayName: "Speaker 1", meeting: meeting)
            modelContext.insert(spk)
            return spk
        }()

        for ts in transcriptSegments {
            let label = bestMatchingLabel(for: ts, in: speakerSegments)
            let spk = labelToSpeaker[label] ?? fallbackSpeaker
            let seg = Segment(startSec: ts.startSec, endSec: ts.endSec, text: ts.text, speaker: spk, meeting: meeting)
            modelContext.insert(seg)
        }

        return true
    }

    private func runSummary(meeting: Meeting) async {
        let summarizer = summarizerRegistry.currentSummarizer()
        guard summarizer.isConfigured else {
            logger.warning("Meeting summarizer not configured — skipping summary")
            meeting.summaryStage = .failed
            return
        }

        let transcript = buildFormattedTranscript(meeting: meeting)

        for attempt in 1...2 {
            do {
                let summary = try await summarizer.summarize(transcript: transcript)
                meeting.title = summary.title
                meeting.subtitle = summary.subtitle
                meeting.summaryTldr = summary.tldr
                meeting.summaryKeyPoints = summary.keyPoints
                meeting.summaryActionItems = summary.actionItems
                meeting.summaryStage = .done
                return
            } catch {
                logger.error("Summary attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        meeting.summaryStage = .failed
    }

    // MARK: - Helpers

    private func isSupported(url: URL) -> Bool {
        guard let fileType = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        let all = Self.supportedAudioTypes + Self.supportedVideoTypes
        return all.contains { fileType.conforms(to: $0) }
    }

    private func extractAudio(from sourceURL: URL, to destURL: URL) async -> Bool {
        do {
            // Decode on a background executor so AVAudioFile / AVAudioConverter don't pin the main actor.
            try await Task.detached(priority: .userInitiated) {
                try await AudioExtractor.extractAudio(from: sourceURL, to: destURL)
            }.value
            return true
        } catch {
            logger.error("Audio extraction failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func probeDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let secs = CMTimeGetSeconds(duration)
        return secs.isNaN || secs.isInfinite ? 0 : secs
    }

    // Picks the diarizer label with the maximum time overlap with the transcript segment.
    // If no overlap is found (silence gap), returns the first speaker label or a default.
    private func bestMatchingLabel(for ts: TranscriptSegment, in speakerSegments: [SpeakerSegment]) -> String {
        var bestLabel = speakerSegments.first?.speakerLabel ?? "speaker_0"
        var bestOverlap = 0.0
        for ss in speakerSegments {
            let overlapStart = max(ts.startSec, ss.startSec)
            let overlapEnd = min(ts.endSec, ss.endSec)
            let overlap = max(0, overlapEnd - overlapStart)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestLabel = ss.speakerLabel
            }
        }
        return bestLabel
    }

    // Formats sorted segments as "[DisplayName mm:ss] Text" lines.
    private func buildFormattedTranscript(meeting: Meeting) -> String {
        let sorted = meeting.segments.sorted { $0.startSec < $1.startSec }
        return sorted.map { seg in
            let name = seg.speaker.map { speakerDisplayFallback($0) } ?? "Unknown"
            let ts = formatTimestamp(seg.startSec)
            return "[\(name) \(ts)] \(seg.text)"
        }.joined(separator: "\n")
    }

    private func speakerDisplayFallback(_ speaker: Speaker) -> String {
        if !speaker.displayName.isEmpty { return speaker.displayName }
        let label = speaker.diarizerLabel
        if label.hasPrefix("speaker_"), let n = Int(label.dropFirst("speaker_".count)) {
            return "Speaker \(n + 1)"
        }
        return label
    }

    private func formatTimestamp(_ secs: Double) -> String {
        let total = Int(max(0, secs))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func deleteSegmentsAndSpeakers(for meeting: Meeting) {
        // Snapshot before deleting — SwiftData mutates the relationship mid-iteration.
        for seg in Array(meeting.segments) { modelContext.delete(seg) }
        for spk in Array(meeting.speakers) { modelContext.delete(spk) }
    }

    private func appSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
    }
}
