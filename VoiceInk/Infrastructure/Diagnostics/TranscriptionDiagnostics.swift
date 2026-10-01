import Foundation
import OSLog

enum TranscriptionDiagnostics {
    @TaskLocal static var recording: Recording?
    static var recordingID: String? { recording?.id }
    @TaskLocal private static var pendingOperation: PendingOperation?

    final class Recording: @unchecked Sendable {
        let id = String(UUID().uuidString.prefix(8))
        private struct State {
            var facts: [String: String] = [:]
            var timings: [String: TimeInterval] = [:]
            var lastError: String?
        }
        private let state = OSAllocatedUnfairLock(initialState: State())

        func add(_ key: String, _ value: String) {
            state.withLock { $0.facts[key] = value }
        }

        fileprivate func addTiming(_ operation: String, elapsed: TimeInterval) {
            // The summary already contains total elapsed time and input duration.
            guard operation != "transcription", operation != "audio-metadata" else { return }
            state.withLock { $0.timings[operation, default: 0] += elapsed }
        }

        fileprivate func shouldLog(_ error: String) -> Bool {
            state.withLock {
                guard $0.lastError != error else { return false }
                $0.lastError = error
                return true
            }
        }

        fileprivate var summary: String {
            state.withLock {
                let facts = $0.facts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                let timings = $0.timings.sorted { $0.key < $1.key }
                    .map { "\($0.key):\(String(format: "%.3f", $0.value))s" }.joined(separator: ",")
                return (facts + ["timings=[\(timings)]"]).joined(separator: " ")
            }
        }
    }

    private final class PendingOperation: @unchecked Sendable {
        struct State {
            var childCount = 0
            var finished = false
        }
        let state = OSAllocatedUnfairLock(initialState: State())
    }

    // Notice-level app logs remain available in production even when SDK info logs don't.
    static func measure<Result>(
        _ operation: String,
        logger: Logger,
        details: String = "",
        body: () async throws -> Result
    ) async throws -> Result {
        let id = recordingID ?? String(UUID().uuidString.prefix(8))
        let recording = recording
        let start = ProcessInfo.processInfo.systemUptime
        let parent = pendingOperation
        parent?.state.withLock { $0.childCount += 1 }
        let current = PendingOperation()
        // Use a dispatch timer so a blocked Swift task doesn't also block status logging.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler {
            current.state.withLock { state in
                guard !state.finished, state.childCount == 0 else { return }
                logger.notice("ASR id=\(id, privacy: .public) \(operation, privacy: .public) still pending elapsed=\(ProcessInfo.processInfo.systemUptime - start, format: .fixed(precision: 1), privacy: .public)s \(details, privacy: .public)")
            }
        }
        timer.resume()
        func stopStatus() {
            current.state.withLock { $0.finished = true }
            timer.cancel()
        }
        defer {
            stopStatus()
            recording?.addTiming(operation, elapsed: ProcessInfo.processInfo.systemUptime - start)
            parent?.state.withLock { $0.childCount -= 1 }
        }
        do {
            let result = try await $pendingOperation.withValue(current) { try await body() }
            stopStatus()
            return result
        } catch {
            stopStatus()
            if !(error is CancellationError) {
                let failure = errorDetails(error)
                // Keep the original error once, rather than repeat it at every nested stage.
                if recording?.shouldLog(failure) ?? true {
                    logger.error("ASR id=\(id, privacy: .public) \(operation, privacy: .public) failed elapsed=\(ProcessInfo.processInfo.systemUptime - start, format: .fixed(precision: 3), privacy: .public)s \(details, privacy: .public) \(failure, privacy: .public)")
                }
            }
            throw error
        }
    }

    static func configuration(
        model: any TranscriptionModel, context: TranscriptionRequestContext, realtime: Bool, id: String
    ) {
        guard model.provider == .fluidAudio else { return }
        let revisionURL = Bundle.main.url(forResource: "FluidAudioRevision", withExtension: "txt")
        let revision = (revisionURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "unknown")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let precision = FluidAudioModelManager.isNemotronModel(named: model.name) ? "SDK-default"
            : FluidAudioModelManager.isParakeetUnifiedModel(named: model.name)
                ? String(describing: FluidAudioModelManager.parakeetUnifiedPrecision) : "int8"
        let units = FluidAudioModelManager.diagnosticComputeUnits
        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionDiagnostics")
        logger.notice("ASR id=\(id, privacy: .public) configuration sdk=\(revision, privacy: .public) model=\(model.name, privacy: .public) precisionSelector=\(precision, privacy: .public) requestedComputeUnits=\(units, privacy: .public) realtime=\(realtime, privacy: .public) vad=\(UserDefaults.standard.bool(forKey: "IsVADEnabled"), privacy: .public) language=\(context.language ?? "auto", privacy: .public)")
    }

    static func transcribe(
        audioURL: URL, model: any TranscriptionModel, recording: Recording,
        body: () async throws -> String
    ) async throws -> String {
        try await $recording.withValue(recording) {
            guard model.provider == .fluidAudio else { return try await body() }
            let start = ProcessInfo.processInfo.systemUptime
            var status = "failed"
            var result = ""
            defer {
                logger.notice("ASR id=\(recording.id, privacy: .public) summary status=\(status, privacy: .public) elapsed=\(ProcessInfo.processInfo.systemUptime - start, format: .fixed(precision: 3), privacy: .public)s \(result, privacy: .public) \(recording.summary, privacy: .public)")
            }
            do {
                let text = try await measure("transcription", logger: logger) {
                    let duration = try await measure("audio-metadata", logger: logger) {
                        await AudioFileMetadata.duration(for: audioURL)
                    }
                    recording.add("inputSeconds", String(format: "%.3f", duration))
                    return try await body()
                }
                status = "completed"
                result = "chars=\(text.count) empty=\(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
                return text
            } catch {
                if error is CancellationError { status = "canceled" }
                throw error
            }
        }
    }

    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionDiagnostics")

    static func errorDetails(_ error: Error, includeUnderlying: Bool = true) -> String {
        var pending = [error as NSError]
        var seen = Set<ObjectIdentifier>()
        var details: [String] = []
        // Bound traversal and output; don't dump userInfo, audio paths or transcript content.
        while !pending.isEmpty, details.count < 8 {
            let current = pending.removeFirst()
            guard seen.insert(ObjectIdentifier(current)).inserted else { continue }
            let reason = includeUnderlying ? current.localizedFailureReason.map { " reason=\($0)" } ?? "" : ""
            details.append("\(current.domain)(\(current.code)): \(current.localizedDescription)\(reason)")
            guard includeUnderlying else { break }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
            if let underlying = current.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                pending.append(contentsOf: underlying.prefix(8))
            }
        }
        let description = details.joined(separator: " <- ")
            .replacingOccurrences(of: #"(?:file://)?/(?:Users|Volumes|private|var|tmp)/[^\s\"'<>]+"#,
                                  with: "<path>", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
        return String(description.prefix(4096))
    }
}
