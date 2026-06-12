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
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return pathSection.isEmpty ? nil : pathSection
    }
}
