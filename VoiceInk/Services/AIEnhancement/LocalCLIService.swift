import Foundation

enum LocalCLITemplate: String, CaseIterable, Identifiable {
    case pi
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: return "Pi"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var commandTemplate: String {
        switch self {
        case .pi:
            return "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        case .claude:
            return "claude -p \"$VOICEINK_FULL_PROMPT\""
        case .codex:
            return "codex exec \"$VOICEINK_FULL_PROMPT\""
        }
    }
}

final class LocalCLIService {
    static let commandTemplateKey = "localCLICommandTemplate"
    static let selectedTemplateKey = "localCLISelectedTemplate"
    static let timeoutSecondsKey = "localCLITimeoutSeconds"
    static let defaultTimeoutSeconds: Double = 45
    private static let shellPathQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.localcli.path")
    private static var cachedInteractiveLoginPATH: String?

    var commandTemplate: String {
        didSet {
            UserDefaults.standard.set(commandTemplate, forKey: Self.commandTemplateKey)
        }
    }

    var selectedTemplate: LocalCLITemplate {
        didSet {
            UserDefaults.standard.set(selectedTemplate.rawValue, forKey: Self.selectedTemplateKey)
        }
    }

    var timeoutSeconds: Double {
        didSet {
            let clamped = max(5, timeoutSeconds)
            if clamped != timeoutSeconds {
                timeoutSeconds = clamped
                return
            }
            UserDefaults.standard.set(timeoutSeconds, forKey: Self.timeoutSecondsKey)
        }
    }

    var isConfigured: Bool {
        !commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let savedTemplateRaw = UserDefaults.standard.string(forKey: Self.selectedTemplateKey) ?? ""
        selectedTemplate = LocalCLITemplate(rawValue: savedTemplateRaw) ?? .pi

        commandTemplate = UserDefaults.standard.string(forKey: Self.commandTemplateKey) ?? ""

        let savedTimeout = UserDefaults.standard.double(forKey: Self.timeoutSecondsKey)
        timeoutSeconds = savedTimeout > 0 ? savedTimeout : Self.defaultTimeoutSeconds
    }

    func loadTemplate(_ template: LocalCLITemplate) {
        selectedTemplate = template
        commandTemplate = template.commandTemplate
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        guard isConfigured else {
            throw LocalCLIError.commandNotConfigured
        }

        let fullPrompt = Self.makeFullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return try await executeCommand(
            commandTemplate: commandTemplate,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            fullPrompt: fullPrompt,
            timeout: timeoutSeconds
        )
    }

    static func makeFullPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        <SYSTEM_PROMPT>
        \(systemPrompt)
        </SYSTEM_PROMPT>

        <USER_PROMPT>
        \(userPrompt)
        </USER_PROMPT>
        """
    }

    private func executeCommand(
        commandTemplate: String,
        systemPrompt: String,
        userPrompt: String,
        fullPrompt: String,
        timeout: Double
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", commandTemplate]

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = Self.preferredPATH(fallback: environment["PATH"])
                environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
                environment["VOICEINK_USER_PROMPT"] = userPrompt
                environment["VOICEINK_FULL_PROMPT"] = fullPrompt
                process.environment = environment

                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LocalCLIError.executionFailed(error.localizedDescription))
                    return
                }

                if let inputData = fullPrompt.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                }
                try? inputPipe.fileHandleForWriting.close()

                let semaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    if process.isRunning {
                        process.terminate()
                        _ = semaphore.wait(timeout: .now() + 2)
                    }
                    continuation.resume(throwing: LocalCLIError.timeout(seconds: timeout))
                    return
                }

                let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = Self.cleanOutput(String(data: stdoutData, encoding: .utf8) ?? "")
                let stderr = Self.cleanOutput(String(data: stderrData, encoding: .utf8) ?? "")

                if process.terminationStatus != 0 {
                    let looksLikeCommandNotFound = process.terminationStatus == 127 ||
                        stderr.lowercased().contains("command not found")
                    if looksLikeCommandNotFound {
                        continuation.resume(throwing: LocalCLIError.commandNotFound(stderr.isEmpty ? commandTemplate : stderr))
                    } else {
                        continuation.resume(throwing: LocalCLIError.nonZeroExit(status: Int(process.terminationStatus), stderr: stderr))
                    }
                    return
                }

                guard !stdout.isEmpty else {
                    continuation.resume(throwing: LocalCLIError.emptyOutput)
                    return
                }

                continuation.resume(returning: stdout)
            }
        }
    }

    private static func preferredPATH(fallback: String?) -> String {
        shellPathQueue.sync {
            if let cachedInteractiveLoginPATH {
                return cachedInteractiveLoginPATH
            }

            if let discovered = discoverPATHFromInteractiveLoginShell() {
                cachedInteractiveLoginPATH = discovered
                return discovered
            }

            return fallback?.isEmpty == false ? fallback! : "/usr/bin:/bin:/usr/sbin:/sbin"
        }
    }

    private static func discoverPATHFromInteractiveLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-ilc",
            "echo __VOICEINK_PATH_START__; print -r -- $PATH; echo __VOICEINK_PATH_END__"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        let waitResult = semaphore.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let startMarker = "__VOICEINK_PATH_START__"
        let endMarker = "__VOICEINK_PATH_END__"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex)
        else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pathSection.isEmpty else {
            return nil
        }

        return pathSection
    }

    private static func cleanOutput(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LocalCLIError: Error, LocalizedError {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }
            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        }
    }
}
