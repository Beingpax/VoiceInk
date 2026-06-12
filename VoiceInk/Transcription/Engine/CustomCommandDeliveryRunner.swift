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
        let outputDrain = PipeDrainTracker()
        let errorDrain = PipeDrainTracker()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputDrain.finish()
            } else {
                outputBuffer.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                errorDrain.finish()
            } else {
                errorBuffer.append(data)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            clearHandlers(outputPipe: outputPipe, errorPipe: errorPipe)
            continuation.resume(throwing: CustomCommandDeliveryError.launchFailed(error.localizedDescription))
            return
        }

        writeStandardInput(context.standardInput, to: inputPipe.fileHandleForWriting)

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            terminate(process, semaphore: semaphore)
            waitForPipeDrains(outputDrain, errorDrain)
            clearHandlers(outputPipe: outputPipe, errorPipe: errorPipe)
            continuation.resume(throwing: CustomCommandDeliveryError.timeout(seconds: timeout))
            return
        }

        waitForPipeDrains(outputDrain, errorDrain)
        clearHandlers(outputPipe: outputPipe, errorPipe: errorPipe)

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

    private static func writeStandardInput(_ input: String, to handle: FileHandle) {
        defer { try? handle.close() }

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

    private static func terminate(_ process: Process, semaphore: DispatchSemaphore) {
        guard process.isRunning else { return }

        process.terminate()
        if semaphore.wait(timeout: .now() + 2) == .success {
            return
        }

        guard process.isRunning else { return }
        if kill(process.processIdentifier, SIGKILL) != 0 {
            logger.error("Failed to SIGKILL custom command process \(process.processIdentifier, privacy: .public): errno \(errno, privacy: .public)")
            return
        }

        if semaphore.wait(timeout: .now() + 1) == .timedOut {
            logger.error("Custom command process \(process.processIdentifier, privacy: .public) did not exit after SIGKILL")
        }
    }

    private static func clearHandlers(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }

    private static func waitForPipeDrains(_ drains: PipeDrainTracker...) {
        let deadline = DispatchTime.now() + .milliseconds(500)
        drains.forEach { $0.wait(until: deadline) }
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

    func wait(until deadline: DispatchTime) {
        _ = group.wait(timeout: deadline)
    }
}
