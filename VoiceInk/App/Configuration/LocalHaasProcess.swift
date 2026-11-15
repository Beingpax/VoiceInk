import Darwin
import Foundation

/// One ticket per recognition request: cancellation cannot terminate another request.
final class LocalHaasProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false

    func cancel(timeout: Bool = false) {
        lock.lock()
        cancelled = true
        timedOut = timeout
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        lock.unlock()
    }

    func run(executable: URL, arguments: [String], output: URL, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    self.lock.lock()
                    if self.cancelled {
                        self.lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    var outputHandle: FileHandle?
                    do {
                        FileManager.default.createFile(atPath: output.path, contents: nil,
                            attributes: [.posixPermissions: 0o600])
                        let handle = try FileHandle(forWritingTo: output)
                        outputHandle = handle
                        self.process.executableURL = executable
                        self.process.arguments = arguments
                        // No user Python configuration, shell, or network-backed model discovery.
                        self.process.environment = ["PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1",
                            "HF_HUB_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false"]
                        self.process.standardInput = FileHandle.nullDevice
                        self.process.standardOutput = handle
                        self.process.standardError = FileHandle.nullDevice
                        let deadline = DispatchWorkItem { self.cancel(timeout: true) }
                        self.process.terminationHandler = { child in
                            self.process.terminationHandler = nil
                            deadline.cancel()
                            try? handle.close()
                            self.lock.lock()
                            let cancelled = self.cancelled
                            let timedOut = self.timedOut
                            self.lock.unlock()
                            if timedOut { continuation.resume(throwing: URLError(.timedOut)) }
                            else if cancelled { continuation.resume(throwing: CancellationError()) }
                            else if child.terminationStatus != 0 { continuation.resume(throwing: LocalHaasError.workerFailed) }
                            else {
                                do {
                                    let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                    guard size <= 1024 * 1024 else { throw LocalHaasError.workerFailed }
                                    continuation.resume(returning: try Data(contentsOf: output))
                                } catch { continuation.resume(throwing: error) }
                            }
                        }
                        try self.process.run()
                        self.lock.unlock()
                        DispatchQueue.global().asyncAfter(deadline: .now() + max(1, timeout), execute: deadline)
                    } catch {
                        try? outputHandle?.close()
                        self.process.terminationHandler = nil
                        self.lock.unlock()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
}
