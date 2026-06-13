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
            return String(format: String(localized: "Custom command exited with status %d: %@"), status, String(details.prefix(300)))
        }
    }
}

enum CustomCommandDeliveryRunner {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomCommandDeliveryRunner")

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

        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()
        let outputDrainGroup = DispatchGroup()
        let inputWriteGroup = DispatchGroup()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: CustomCommandDeliveryError.launchFailed(error.localizedDescription))
            return
        }

        let timeoutDeadline = DispatchTime.now() + timeout
        startDraining(outputPipe.fileHandleForReading, into: outputBuffer, group: outputDrainGroup)
        startDraining(errorPipe.fileHandleForReading, into: errorBuffer, group: outputDrainGroup)
        startWritingStandardInput(context.standardInput, to: inputPipe.fileHandleForWriting, group: inputWriteGroup)

        let waitResult = semaphore.wait(timeout: timeoutDeadline)
        if waitResult == .timedOut {
            terminate(process, semaphore: semaphore)
            closePipeHandles(inputPipe: inputPipe, outputPipe: outputPipe, errorPipe: errorPipe)
            _ = waitForGroup(outputDrainGroup, timeout: 2)
            _ = waitForGroup(inputWriteGroup, timeout: 1)
            continuation.resume(throwing: CustomCommandDeliveryError.timeout(seconds: timeout))
            return
        }

        if !waitForGroup(outputDrainGroup, timeout: 5) {
            logger.error("Custom command output drains did not finish before the grace period elapsed")
            closePipeHandles(inputPipe: inputPipe, outputPipe: outputPipe, errorPipe: errorPipe)
            _ = waitForGroup(outputDrainGroup, timeout: 1)
        }
        _ = waitForGroup(inputWriteGroup, timeout: 1)

        let stdout = outputBuffer.stringValue()
        let stderr = errorBuffer.stringValue()

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

    private static func startDraining(_ handle: FileHandle, into buffer: LockedDataBuffer, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? handle.close()
                group.leave()
            }

            buffer.append(handle.readDataToEndOfFile())
        }
    }

    private static func startWritingStandardInput(_ input: String, to handle: FileHandle, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? handle.close()
                group.leave()
            }

            guard let inputData = input.data(using: .utf8),
                  !inputData.isEmpty else {
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
           semaphore.wait(timeout: .now() + 1) == .timedOut {
            logger.error("Custom command process \(process.processIdentifier, privacy: .public) did not exit after SIGKILL")
        }
    }

    private static func processTreeTargets(rootPID: pid_t) -> [pid_t] {
        Array(descendants(of: rootPID).reversed()) + [rootPID]
    }

    private static func signalTargets(_ pids: [pid_t], signal: Int32) {
        for pid in pids {
            if kill(pid, signal) != 0 && errno != ESRCH {
                logger.error("Failed to signal custom command process \(pid, privacy: .public): errno \(errno, privacy: .public)")
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
        let outputBuffer = LockedDataBuffer()
        let outputDrainGroup = DispatchGroup()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        startDraining(outputPipe.fileHandleForReading, into: outputBuffer, group: outputDrainGroup)
        process.waitUntilExit()
        _ = waitForGroup(outputDrainGroup, timeout: 1)

        guard process.terminationStatus == 0 else {
            return []
        }

        let output = outputBuffer.stringValue()
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func closePipeHandles(inputPipe: Pipe, outputPipe: Pipe, errorPipe: Pipe) {
        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }

    private static func waitForGroup(_ group: DispatchGroup, timeout: TimeInterval) -> Bool {
        group.wait(timeout: .now() + timeout) == .success
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
