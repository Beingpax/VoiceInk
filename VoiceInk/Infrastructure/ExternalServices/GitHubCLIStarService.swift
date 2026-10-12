import Foundation

// Stars the VoiceInk repo via the gh CLI when available, since GUI apps don't inherit shell PATH.
enum GitHubCLIStarService {
    private static let repoSlug = "Beingpax/VoiceInk"

    enum RemoteStarState {
        case starred
        case notStarred
        case unavailable
    }

    static func checkRemoteStarState() async -> RemoteStarState {
        guard let ghPath = await resolveGhPath() else { return .unavailable }
        guard let result = await run(ghPath, ["api", "--include", "user/starred/\(repoSlug)"]) else {
            return .unavailable
        }
        if result.output.range(of: #"HTTP/\S+\s+(200|204)\b"#, options: .regularExpression) != nil {
            return .starred
        }
        if result.output.range(of: #"HTTP/\S+\s+404\b"#, options: .regularExpression) != nil {
            return .notStarred
        }
        return .unavailable
    }

    static func star() async -> Bool {
        guard let ghPath = await resolveGhPath() else { return false }
        guard let result = await run(ghPath, ["api", "-X", "PUT", "user/starred/\(repoSlug)"]) else {
            return false
        }
        return result.exitCode == 0
    }

    // MARK: - gh binary resolution

    private static var cachedGhPath: String?
    private static var didResolveGhPath = false

    private static func resolveGhPath() async -> String? {
        if didResolveGhPath { return cachedGhPath }
        let resolved = await findGhPath()
        cachedGhPath = resolved
        didResolveGhPath = true
        return resolved
    }

    private static func findGhPath() async -> String? {
        let knownInstallPaths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/opt/local/bin/gh",
        ]
        if let found = knownInstallPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Reuses the shared, bounded PATH resolver (sources .zshrc via an interactive-login fallback)
        // instead of shelling out separately here.
        return await Task.detached(priority: .utility) {
            let path = ShellCommandEnvironment.preferredPATH(fallback: ProcessInfo.processInfo.environment["PATH"])
            return path.split(separator: ":")
                .map { "\($0)/gh" }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
        }.value
    }

    // MARK: - process execution

    private struct ProcessResult {
        let exitCode: Int32
        let output: String
    }

    private static func run(_ executablePath: String, _ arguments: [String]) async -> ProcessResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: execute(executablePath: executablePath, arguments: arguments))
            }
        }
    }

    private static let processTimeoutSeconds: TimeInterval = 8

    private static func execute(executablePath: String, arguments: [String]) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Bounds a hung gh call (bad network/proxy) so callers still fall back instead of hanging forever.
        let timeoutWorkItem = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + processTimeoutSeconds, execute: timeoutWorkItem)

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }
}
