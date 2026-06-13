import Darwin
import Foundation

enum ShellCommandEnvironment {
    private static let shellPathQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.shell.path")
    private static var cachedPreferredPATH: String?
    private static let inheritedEnvironmentKeys = [
        "HOME",
        "USER",
        "LOGNAME",
        "SHELL",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE"
    ]

    static func preferredPATH(fallback: String?) -> String {
        shellPathQueue.sync {
            if let cachedPreferredPATH {
                return cachedPreferredPATH
            }

            let fallbackPATH = fallback?.isEmpty == false ? fallback! : defaultPATH
            let loginShellPATH = discoverPATHFromShell(arguments: ["-lc", pathDiscoveryCommand])
            if let loginShellPATH,
               loginShellPATH != fallbackPATH || fallbackPATH != defaultPATH {
                cachedPreferredPATH = loginShellPATH
                return loginShellPATH
            }

            if let interactiveLoginShellPATH = discoverPATHFromShell(arguments: ["-ilc", pathDiscoveryCommand]) {
                cachedPreferredPATH = interactiveLoginShellPATH
                return interactiveLoginShellPATH
            }

            if let loginShellPATH {
                cachedPreferredPATH = loginShellPATH
                return loginShellPATH
            }

            return fallbackPATH
        }
    }

    static func commandEnvironment(
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        additionalEnvironment: [String: String] = [:]
    ) -> [String: String] {
        var environment = inheritedEnvironmentKeys.reduce(into: [String: String]()) { result, key in
            if let value = inheritedEnvironment[key], !value.isEmpty {
                result[key] = value
            }
        }

        environment["PATH"] = preferredPATH(fallback: inheritedEnvironment["PATH"])
        setDefault("HOME", NSHomeDirectory(), in: &environment)
        setDefault("USER", NSUserName(), in: &environment)
        setDefault("LOGNAME", NSUserName(), in: &environment)
        setDefault("SHELL", "/bin/zsh", in: &environment)
        setDefault("TMPDIR", NSTemporaryDirectory(), in: &environment)

        additionalEnvironment.forEach { key, value in
            environment[key] = value
        }

        return environment
    }

    private static func setDefault(_ key: String, _ value: String, in environment: inout [String: String]) {
        guard environment[key]?.isEmpty ?? true else { return }
        environment[key] = value
    }

    private static let defaultPATH = "/usr/bin:/bin:/usr/sbin:/sbin"
    private static let pathDiscoveryCommand = "echo __VOICEINK_PATH_START__; print -r -- $PATH; echo __VOICEINK_PATH_END__"

    private static func discoverPATHFromShell(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments

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

        let stdoutBuffer = ShellCommandDataBuffer()
        let drainGroup = DispatchGroup()
        drain(stdoutPipe.fileHandleForReading, into: stdoutBuffer, group: drainGroup)
        drain(stderrPipe.fileHandleForReading, into: nil, group: drainGroup)

        let waitResult = semaphore.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            terminate(process, semaphore: semaphore)
            _ = drainGroup.wait(timeout: .now() + 1)
            return nil
        }

        guard process.terminationStatus == 0 else {
            _ = drainGroup.wait(timeout: .now() + 1)
            return nil
        }

        _ = drainGroup.wait(timeout: .now() + 1)
        let output = stdoutBuffer.stringValue()
        let startMarker = "__VOICEINK_PATH_START__"
        let endMarker = "__VOICEINK_PATH_END__"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return pathSection.isEmpty ? nil : pathSection
    }

    private static func drain(_ handle: FileHandle, into buffer: ShellCommandDataBuffer?, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? handle.close()
                group.leave()
            }

            let data = handle.readDataToEndOfFile()
            buffer?.append(data)
        }
    }

    private static func terminate(_ process: Process, semaphore: DispatchSemaphore) {
        guard process.isRunning else { return }

        process.terminate()
        if semaphore.wait(timeout: .now() + 1) == .success {
            return
        }

        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
        _ = semaphore.wait(timeout: .now() + 1)
    }
}

private final class ShellCommandDataBuffer {
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
