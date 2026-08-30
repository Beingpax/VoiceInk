import Darwin
import Foundation
import os

struct CustomCommandDeliveryContext {
    let transcript: String

    var standardInput: String {
        transcript
    }

    var environment: [String: String] {
        [
            "VOICEINK_TRANSCRIPT": transcript
        ]
    }
}

struct CustomCommandDeliveryResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum CustomCommandDeliveryError: Error, LocalizedError {
    case commandNotConfigured
    case noTextToDeliver
    case launchFailed(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return String(localized: "Custom command is empty.")
        case .noTextToDeliver:
            return String(localized: "No transcription text was available for the custom command.")
        case .launchFailed(let message):
            return String(format: String(localized: "Custom command could not start: %@"), message)
        case .timeout(let seconds):
            return String(format: String(localized: "Custom command timed out after %.0f seconds."), seconds)
        case .nonZeroExit(let status, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return String(format: String(localized: "Custom command exited with status %d."), status)
            }
            return String(
                format: String(localized: "Custom command exited with status %d: %@"), status,
                String(details.prefix(300)))
        }
    }
}

enum CustomCommandDeliveryRunner {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "CustomCommandDeliveryRunner")

    static func run(
        command: String,
        timeout: TimeInterval,
        context: CustomCommandDeliveryContext
    ) async throws -> CustomCommandDeliveryResult {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            throw CustomCommandDeliveryError.commandNotConfigured
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                execute(
                    command: trimmedCommand,
                    timeout: timeout,
                    context: context,
                    continuation: continuation
                )
            }
        }
    }

    private static func execute(
        command: String,
        timeout: TimeInterval,
        context: CustomCommandDeliveryContext,
        continuation: CheckedContinuation<CustomCommandDeliveryResult, Error>
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = ShellCommandEnvironment.commandEnvironment(
            additionalEnvironment: context.environment
        )

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputCollector = PipeOutputCollector(handle: outputPipe.fileHandleForReading)
        let errorCollector = PipeOutputCollector(handle: errorPipe.fileHandleForReading)
        let outputCollectors = [outputCollector, errorCollector]
        let inputWriteGroup = DispatchGroup()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            outputCollectors.forEach { $0.stop() }
            continuation.resume(throwing: CustomCommandDeliveryError.launchFailed(error.localizedDescription))
            return
        }

        let timeoutDeadline = DispatchTime.now() + timeout
        startWritingStandardInput(context.standardInput, to: inputPipe.fileHandleForWriting, group: inputWriteGroup)

        let waitResult = semaphore.wait(timeout: timeoutDeadline)
        if waitResult == .timedOut {
            terminate(process, semaphore: semaphore)
            try? inputPipe.fileHandleForWriting.close()
            _ = waitForCollectors(outputCollectors, timeout: 1)
            outputCollectors.forEach { $0.stop() }
            _ = waitForGroup(inputWriteGroup, timeout: 1)
            continuation.resume(throwing: CustomCommandDeliveryError.timeout(seconds: timeout))
            return
        }

        _ = waitForCollectors(outputCollectors, timeout: 2)
        outputCollectors.forEach { $0.stop() }
        _ = waitForGroup(inputWriteGroup, timeout: 1)

        let stdout = outputCollector.stringValue()
        let stderr = errorCollector.stringValue()

        guard process.terminationStatus == 0 else {
            continuation.resume(
                throwing: CustomCommandDeliveryError.nonZeroExit(
                    status: process.terminationStatus,
                    stderr: stderr
                )
            )
            return
        }

        continuation.resume(
            returning: CustomCommandDeliveryResult(
                status: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        )
    }

    private static func startWritingStandardInput(_ input: String, to handle: FileHandle, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? handle.close()
                group.leave()
            }

            guard let inputData = input.data(using: .utf8),
                !inputData.isEmpty
            else {
                return
            }

            do {
                try handle.write(contentsOf: inputData)
            } catch {
                // The command may exit before reading stdin; its exit status is handled separately.
            }
        }
    }

    private static func terminate(_ process: Process, semaphore: DispatchSemaphore) {
        guard process.isRunning else { return }

        let targets = processTreeTargets(rootPID: process.processIdentifier)
        signalTargets(targets, signal: SIGTERM)
        let didExitAfterTerminate = semaphore.wait(timeout: .now() + 2) == .success

        let remainingTargets = targets.filter(isProcessRunning)
        if !remainingTargets.isEmpty {
            signalTargets(remainingTargets, signal: SIGKILL)
        }

        if !didExitAfterTerminate,
            semaphore.wait(timeout: .now() + 1) == .timedOut
        {
            logger.error(
                "Custom command process \(process.processIdentifier, privacy: .public) did not exit after SIGKILL")
        }
    }

    private static func processTreeTargets(rootPID: pid_t) -> [pid_t] {
        Array(descendants(of: rootPID).reversed()) + [rootPID]
    }

    private static func signalTargets(_ pids: [pid_t], signal: Int32) {
        for pid in pids {
            if kill(pid, signal) != 0 && errno != ESRCH {
                logger.error(
                    "Failed to signal custom command process \(pid, privacy: .public): errno \(errno, privacy: .public)"
                )
            }
        }
    }

    private static func isProcessRunning(_ pid: pid_t) -> Bool {
        errno = 0
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func descendants(of rootPID: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue = [rootPID]
        var visited = Set<pid_t>()

        while let parentPID = queue.first {
            queue.removeFirst()
            guard visited.insert(parentPID).inserted else { continue }

            let childPIDs = children(of: parentPID)
            result.append(contentsOf: childPIDs)
            queue.append(contentsOf: childPIDs)
        }

        return result
    }

    private static func children(of parentPID: pid_t) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(parentPID)"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        let outputCollector = PipeOutputCollector(handle: outputPipe.fileHandleForReading)

        do {
            try process.run()
        } catch {
            outputCollector.stop()
            return []
        }

        process.waitUntilExit()
        _ = waitForCollectors([outputCollector], timeout: 0.5)
        outputCollector.stop()

        guard process.terminationStatus == 0 else {
            return []
        }

        let output = outputCollector.stringValue()
        return
            output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func waitForGroup(_ group: DispatchGroup, timeout: TimeInterval) -> Bool {
        group.wait(timeout: .now() + timeout) == .success
    }

    private static func waitForCollectors(_ collectors: [PipeOutputCollector], timeout: TimeInterval) -> Bool {
        let deadline = DispatchTime.now() + timeout
        return collectors.allSatisfy { $0.wait(until: deadline) }
    }
}

private final class PipeOutputCollector {
    private let handle: FileHandle
    private let buffer = LockedDataBuffer()
    private let drainTracker = PipeDrainTracker()
    private let stopLock = NSLock()
    private var stopped = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            self?.readAvailableData(from: handle)
        }
    }

    func stop() {
        stopLock.lock()
        guard !stopped else {
            stopLock.unlock()
            return
        }
        stopped = true
        stopLock.unlock()

        handle.readabilityHandler = nil
        drainTracker.finish()
    }

    func wait(until deadline: DispatchTime) -> Bool {
        drainTracker.wait(until: deadline)
    }

    func stringValue() -> String {
        buffer.stringValue()
    }

    private func readAvailableData(from handle: FileHandle) {
        let data = handle.availableData
        if data.isEmpty {
            drainTracker.finish()
        } else {
            buffer.append(data)
        }
    }
}

private final class PipeDrainTracker {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var didFinish = false

    init() {
        group.enter()
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true
        group.leave()
    }

    func wait(until deadline: DispatchTime) -> Bool {
        group.wait(timeout: deadline) == .success
    }
}

private final class LockedDataBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let value = data
        lock.unlock()
        return String(data: value, encoding: .utf8) ?? ""
    }
}
