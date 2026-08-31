import AppKit
import CryptoKit
import Foundation
import os

struct TranscribeCppDownloadStatus: Sendable {
    let fractionCompleted: Double
    let message: String
    let isIndeterminate: Bool
}

private func regularFileSize(at url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values?.isRegularFile == true else { return 0 }
    return Int64(values?.fileSize ?? 0)
}

private enum TranscribeCppDownloadError: LocalizedError {
    case httpStatus(Int)
    case invalidRangeResponse
    case incompleteDownload(received: Int64, expected: Int64)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Model download returned HTTP status \(statusCode)."
        case .invalidRangeResponse:
            return "The model server returned an invalid resume response."
        case .incompleteDownload(let received, let expected):
            return "The model download ended after \(received) of \(expected) bytes."
        }
    }
}

private final class TranscribeCppDownloadOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedByteCount: Int64
    private let progressHandler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var response: HTTPURLResponse?
    private var totalBytesWritten: Int64 = 0
    private var lastReportedFraction = 0.0
    private var isCancelled = false
    private var isCompleted = false

    init(
        destinationURL: URL,
        expectedByteCount: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedByteCount = expectedByteCount
        self.progressHandler = progressHandler
    }

    func start(from sourceURL: URL) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resumeOffset = regularFileSize(at: destinationURL)
                var request = URLRequest(url: sourceURL)
                if resumeOffset > 0 {
                    request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
                }

                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)

                let shouldStart = lock.withLock {
                    guard !isCancelled, !isCompleted else { return false }
                    self.session = session
                    self.continuation = continuation
                    totalBytesWritten = resumeOffset
                    return true
                }

                if shouldStart {
                    reportProgress(for: resumeOffset)
                    task.resume()
                } else {
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(with: .failure(URLError(.badServerResponse)))
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            completionHandler(.cancel)
            finish(with: .failure(TranscribeCppDownloadError.httpStatus(httpResponse.statusCode)))
            return
        }

        let requestedOffset = lock.withLock { totalBytesWritten }
        let shouldAppend: Bool
        if requestedOffset > 0 && httpResponse.statusCode == 206 {
            guard Self.contentRange(in: httpResponse, startsAt: requestedOffset) else {
                completionHandler(.cancel)
                finish(with: .failure(TranscribeCppDownloadError.invalidRangeResponse))
                return
            }
            shouldAppend = true
        } else {
            // A 200 response means Range was ignored, so restart instead of appending duplicates.
            shouldAppend = false
        }

        do {
            let handle = try Self.openFile(at: destinationURL, appending: shouldAppend)
            lock.withLock {
                self.response = httpResponse
                fileHandle = handle
                if !shouldAppend {
                    totalBytesWritten = 0
                    lastReportedFraction = 0
                }
            }
            if requestedOffset > 0 && !shouldAppend {
                progressHandler(0)
            }
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            let progress = try lock.withLock { () throws -> Double? in
                guard !isCompleted, let fileHandle else { return nil }
                try fileHandle.write(contentsOf: data)
                totalBytesWritten += Int64(data.count)
                return progressToReport(for: totalBytesWritten)
            }
            if let progress {
                progressHandler(progress)
            }
        } catch {
            dataTask.cancel()
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(with: .failure(error))
            return
        }

        let completion = lock.withLock { (response: self.response, byteCount: totalBytesWritten) }
        guard let response = completion.response else {
            finish(with: .failure(URLError(.badServerResponse)))
            return
        }
        guard completion.byteCount == expectedByteCount else {
            finish(
                with: .failure(
                    TranscribeCppDownloadError.incompleteDownload(
                        received: completion.byteCount,
                        expected: expectedByteCount
                    )
                )
            )
            return
        }
        reportProgress(for: completion.byteCount)
        finish(with: .success(response))
    }

    private func finish(with result: Result<HTTPURLResponse, Error>) {
        let resolution = lock.withLock {
            guard !isCompleted else {
                return (
                    nil as CheckedContinuation<HTTPURLResponse, Error>?,
                    nil as URLSession?,
                    nil as FileHandle?
                )
            }

            isCompleted = true
            let continuation = self.continuation
            let session = self.session
            let fileHandle = self.fileHandle
            self.continuation = nil
            self.session = nil
            self.fileHandle = nil
            return (continuation, session, fileHandle)
        }

        try? resolution.2?.close()
        resolution.1?.finishTasksAndInvalidate()
        resolution.0?.resume(with: result)
    }

    private func cancel() {
        let session = lock.withLock {
            isCancelled = true
            return self.session
        }
        session?.invalidateAndCancel()
    }

    private func reportProgress(for byteCount: Int64) {
        let progress = lock.withLock { progressToReport(for: byteCount) }
        if let progress {
            progressHandler(progress)
        }
    }

    private func progressToReport(for byteCount: Int64) -> Double? {
        guard expectedByteCount > 0 else { return nil }
        let fraction = min(max(Double(byteCount) / Double(expectedByteCount), 0), 1)
        guard fraction == 1 || fraction - lastReportedFraction >= 0.005 else { return nil }
        lastReportedFraction = fraction
        return fraction
    }

    private static func openFile(at url: URL, appending: Bool) throws -> FileHandle {
        if !appending {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        if appending {
            try handle.seekToEnd()
        }
        return handle
    }

    private static func contentRange(in response: HTTPURLResponse, startsAt offset: Int64) -> Bool {
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range")?.lowercased() else {
            return false
        }
        return contentRange.hasPrefix("bytes \(offset)-")
    }

}

@MainActor
final class TranscribeCppModelManager: ObservableObject {
    static let shared = TranscribeCppModelManager()
    private static let maximumDownloadAttempts = 3

    @Published private var downloadStatuses: [String: TranscribeCppDownloadStatus] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private var activeDownloadIDs: [String: UUID] = [:]
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "TranscribeCppModelManager"
    )

    private init() {}

    func isModelDownloaded(_ model: TranscribeCppModel) -> Bool {
        isModelDownloaded(named: model.name)
    }

    func isModelDownloaded(named modelName: String) -> Bool {
        TranscribeCppModelCatalog.artifact(for: modelName)?.installedModelFileURL != nil
    }

    func isModelDownloading(_ model: TranscribeCppModel) -> Bool {
        activeDownloadIDs[model.name] != nil
    }

    func downloadStatus(for model: TranscribeCppModel) -> TranscribeCppDownloadStatus? {
        downloadStatuses[model.name]
    }

    func downloadModel(_ model: TranscribeCppModel) async {
        guard
            let artifact = TranscribeCppModelCatalog.artifact(for: model.name),
            activeDownloadIDs[model.name] == nil,
            !isModelDownloaded(model)
        else {
            return
        }

        let downloadID = UUID()
        activeDownloadIDs[model.name] = downloadID
        downloadStatuses[model.name] = TranscribeCppDownloadStatus(
            fractionCompleted: 0,
            message: String(localized: "Downloading..."),
            isIndeterminate: false
        )

        defer {
            if activeDownloadIDs[model.name] == downloadID {
                activeDownloadIDs[model.name] = nil
                downloadStatuses[model.name] = nil
                onModelsChanged?()
            }
        }

        let partialURL = artifact.modelDirectory.appendingPathComponent("\(artifact.fileName).partial")
        let modelName = model.name

        do {
            try FileManager.default.createDirectory(at: artifact.modelDirectory, withIntermediateDirectories: true)
            if regularFileSize(at: partialURL) > artifact.expectedFileSize {
                try? FileManager.default.removeItem(at: partialURL)
            }

            if regularFileSize(at: partialURL) < artifact.expectedFileSize {
                try await downloadArtifact(
                    artifact,
                    to: partialURL,
                    modelName: modelName,
                    downloadID: downloadID
                )
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            logger.notice("\(model.displayName, privacy: .public) download paused")
            return
        } catch {
            reportFailure(error, for: model)
            return
        }

        downloadStatuses[model.name] = TranscribeCppDownloadStatus(
            fractionCompleted: 1,
            message: String(localized: "Verifying..."),
            isIndeterminate: true
        )

        do {
            guard regularFileSize(at: partialURL) == artifact.expectedFileSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let checksum = try await Task.detached(priority: .utility) {
                try Self.sha256(of: partialURL)
            }.value
            try Task.checkCancellation()
            guard checksum == artifact.expectedSHA256 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch is CancellationError {
            logger.notice("\(model.displayName, privacy: .public) verification paused")
            return
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            reportFailure(error, for: model)
            return
        }

        do {
            // Commit the checksum first so the final model move makes the installation visible atomically.
            try artifact.expectedSHA256.write(
                to: artifact.checksumFileURL,
                atomically: true,
                encoding: .utf8
            )
            try? FileManager.default.removeItem(at: artifact.modelFileURL)
            try FileManager.default.moveItem(at: partialURL, to: artifact.modelFileURL)
            guard artifact.installedModelFileURL != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            logger.notice("\(model.displayName, privacy: .public) installed successfully")
        } catch {
            if !artifact.modelFileIsValid(in: artifact.modelDirectory) {
                try? FileManager.default.removeItem(at: artifact.modelFileURL)
                try? FileManager.default.removeItem(at: artifact.checksumFileURL)
            }
            reportFailure(error, for: model)
        }
    }

    private func downloadArtifact(
        _ artifact: TranscribeCppModelArtifact,
        to partialURL: URL,
        modelName: String,
        downloadID: UUID
    ) async throws {
        var attempt = 1

        while true {
            try Task.checkCancellation()

            let operation = TranscribeCppDownloadOperation(
                destinationURL: partialURL,
                expectedByteCount: artifact.expectedFileSize
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateDownloadProgress(fraction, for: modelName, downloadID: downloadID)
                }
            }

            do {
                _ = try await operation.start(from: artifact.downloadURL)
                return
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }

                if let downloadError = error as? TranscribeCppDownloadError,
                    case .invalidRangeResponse = downloadError
                {
                    try? FileManager.default.removeItem(at: partialURL)
                    updateDownloadProgress(0, for: modelName, downloadID: downloadID)
                } else if regularFileSize(at: partialURL) > artifact.expectedFileSize {
                    try? FileManager.default.removeItem(at: partialURL)
                    updateDownloadProgress(0, for: modelName, downloadID: downloadID)
                }

                guard attempt < Self.maximumDownloadAttempts, Self.isRetryableDownloadError(error) else {
                    throw error
                }

                logger.warning(
                    "Model download attempt \(attempt, privacy: .public) failed; resuming: \(error.localizedDescription, privacy: .public)"
                )
                try await Task.sleep(for: .seconds(attempt))
                attempt += 1
            }
        }
    }

    func deleteModel(_ model: TranscribeCppModel) {
        guard let artifact = TranscribeCppModelCatalog.artifact(for: model.name) else { return }
        objectWillChange.send()
        artifact.removeInstalledFiles()
        NotificationCenter.default.post(
            name: .transcribeCppModelDeleted,
            object: nil,
            userInfo: ["modelName": model.name]
        )
        onModelDeleted?(model.name)
        onModelsChanged?()
    }

    func showModelInFinder(_ model: TranscribeCppModel) {
        guard
            let artifact = TranscribeCppModelCatalog.artifact(for: model.name),
            let modelFileURL = artifact.installedModelFileURL
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([modelFileURL])
    }

    private func updateDownloadProgress(_ fraction: Double, for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID,
            fraction.isFinite,
            (0...1).contains(fraction)
        else {
            return
        }
        let currentFraction = downloadStatuses[modelName]?.fractionCompleted ?? 0
        guard fraction == 0 || fraction > currentFraction else { return }

        downloadStatuses[modelName] = TranscribeCppDownloadStatus(
            fractionCompleted: fraction,
            message: String(localized: "Downloading..."),
            isIndeterminate: false
        )
    }

    private func reportFailure(_ error: Error, for model: TranscribeCppModel) {
        logger.error("\(model.displayName, privacy: .public) download failed: \(error, privacy: .public)")
        NotificationManager.shared.showNotification(
            title: "\(model.displayName) download failed",
            type: .error
        )
    }

    nonisolated private static func isRetryableDownloadError(_ error: Error) -> Bool {
        if let downloadError = error as? TranscribeCppDownloadError {
            switch downloadError {
            case .invalidRangeResponse, .incompleteDownload:
                return true
            case .httpStatus(let statusCode):
                return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
            }
        }

        // Retry non-cancellation URL failures while retaining downloaded bytes.
        return error is URLError
    }

    nonisolated private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 * 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
