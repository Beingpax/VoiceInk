import AVFoundation
import AppKit
import OSLog
import UniformTypeIdentifiers

/// Writes a time range of a recording out as a standalone audio file, optionally alongside the
/// transcript text so a clip can be shared as a self-contained pair.
enum AudioClipExporter {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AudioClipExporter"
    )

    enum ExportError: Error {
        case cancelled
        case unreadableSource
        case exportFailed
    }

    @MainActor
    static func export(
        source: URL,
        range: WaveformRange,
        transcriptText: String?
    ) async throws {
        let destination = try await presentSavePanel(suggestedName: suggestedName(for: source))

        try await writeClip(source: source, range: range, to: destination)

        if let transcriptText, !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sidecar = destination.deletingPathExtension().appendingPathExtension("txt")
            try? transcriptText.write(to: sidecar, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    // MARK: - Save panel

    @MainActor
    private static func presentSavePanel(suggestedName: String) async throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = String(localized: "Export Clip")

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }
        return url
    }

    private static func suggestedName(for source: URL) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        return "\(base)-clip.wav"
    }

    // MARK: - Writing

    /// Reads the selected frame range out of the source and writes it to a new file. Done off the
    /// main actor because it touches the whole range of the file.
    private static func writeClip(source: URL, range: WaveformRange, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let inputFile = try? AVAudioFile(forReading: source) else {
                throw ExportError.unreadableSource
            }

            let format = inputFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = inputFile.length

            let startFrame = max(0, AVAudioFramePosition(range.lower * sampleRate))
            let endFrame = min(totalFrames, AVAudioFramePosition(range.upper * sampleRate))
            guard endFrame > startFrame else {
                throw ExportError.exportFailed
            }

            let outputFile = try AVAudioFile(
                forWriting: destination,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )

            inputFile.framePosition = startFrame

            let chunkSize: AVAudioFrameCount = 8192
            var remaining = AVAudioFrameCount(endFrame - startFrame)

            while remaining > 0 {
                let framesToRead = min(chunkSize, remaining)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                    throw ExportError.exportFailed
                }

                try inputFile.read(into: buffer, frameCount: framesToRead)
                guard buffer.frameLength > 0 else { break }

                try outputFile.write(from: buffer)
                remaining -= buffer.frameLength
            }
        }.value
    }
}
