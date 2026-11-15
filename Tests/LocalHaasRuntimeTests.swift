import Foundation

final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

final class CancelledDownloadProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    override func stopLoading() {}
}

@main
struct LocalHaasRuntimeTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("haas-unit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("verified model".utf8)
        let url = root.appendingPathComponent("model.bin")
        try bytes.write(to: url)
        let file = LocalHaasModelFile(path: "model.bin", url: URL(string: "https://example.invalid/model")!,
            size: Int64(bytes.count), sha256: try LocalHaasModelStore.sha256(url))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineProtocol.self]
        let offline = URLSession(configuration: config)
        let store = LocalHaasModelStore(root: root, files: [file], session: offline)
        var ready = await store.isReady()
        precondition(!ready, "Uncommitted files must not be marked ready")
        try await store.install { _, _ in }
        ready = await store.isReady()
        precondition(ready)
        try Data(repeating: 1, count: bytes.count).write(to: url)
        do {
            try await store.install { _, _ in }
            fatalError("Corrupted model must not be accepted")
        } catch { print("PASS: SHA mismatch requires replacement; offline replacement fails safely") }
        let invalid = LocalHaasModelFile(path: "../escape", url: file.url, size: 1, sha256: "bad")
        do {
            try await LocalHaasModelStore(root: root, files: [invalid], session: offline).install { _, _ in }
            fatalError("Traversal must be rejected")
        } catch LocalHaasError.invalidDownload { print("PASS: unsafe model path rejected") }
        print("PASS: verified local files install without network; completion marker required")

        // URLSession reports a cancelled download as URLError, not Swift CancellationError.
        let fixtureRuntime = root.appendingPathComponent("runtime")
        let fixturePython = fixtureRuntime.appendingPathComponent("python/bin")
        try FileManager.default.createDirectory(at: fixturePython, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixturePython.appendingPathComponent("python3.13"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        try Data().write(to: fixtureRuntime.appendingPathComponent("libspeech.4.dylib"))
        try JSONEncoder().encode([file]).write(to: fixtureRuntime.appendingPathComponent("models.json"))
        let cancellationConfig = URLSessionConfiguration.ephemeral
        cancellationConfig.protocolClasses = [CancelledDownloadProtocol.self]
        let cancellationRuntime = LocalHaasRuntime(runtimeURL: fixtureRuntime,
            modelsURL: root.appendingPathComponent("cancelled-download"),
            session: URLSession(configuration: cancellationConfig))
        do {
            try await cancellationRuntime.prepare()
            fatalError("Cancelled download must fail")
        } catch let error as URLError where error.code == .cancelled {}
        precondition(cancellationRuntime.errorMessage == "ダウンロードを中止しました。再試行できます。",
            "Cancelled URLSession download must show the Japanese retry guidance")
        precondition(!cancellationRuntime.isDownloading && !cancellationRuntime.isReady)
        print("PASS: cancelled URLSession download shows retry guidance and clears busy state")

        let ticket = LocalHaasProcess()
        let cancel = Task {
            try await ticket.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                output: root.appendingPathComponent("cancel.json"), timeout: 60)
        }
        cancel.cancel()
        do { _ = try await cancel.value; fatalError("Cancelled process must fail") }
        catch is CancellationError { print("PASS: cancellation before launch") }
        do {
            _ = try await LocalHaasProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                output: root.appendingPathComponent("timeout.json"), timeout: 1)
            fatalError("Timeout must fail")
        } catch let error as URLError where error.code == .timedOut { print("PASS: child process timeout") }

        let running = LocalHaasProcess()
        let inFlight = Task {
            try await running.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                output: root.appendingPathComponent("running.json"), timeout: 60)
        }
        let other = Task {
            try await LocalHaasProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.3"],
                output: root.appendingPathComponent("other.json"), timeout: 60)
        }
        try await Task.sleep(for: .milliseconds(150))
        inFlight.cancel()
        do { _ = try await inFlight.value; fatalError("In-flight cancellation must fail") }
        catch is CancellationError { print("PASS: cancellation during execution") }
        _ = try await other.value
        print("PASS: cancelling a request leaves an independent request running")

        if CommandLine.arguments.count >= 4 {
            let runtimePath = URL(fileURLWithPath: CommandLine.arguments[1])
            let models = URL(fileURLWithPath: CommandLine.arguments[2])
            let audio = URL(fileURLWithPath: CommandLine.arguments[3])
            let runtime = LocalHaasRuntime(runtimeURL: runtimePath, modelsURL: models)
            try await runtime.prepare()
            let service = OpenAICompatibleTranscriptionService(localRuntime: { runtime })
            let text = try await service.transcribe(audioURL: audio, model: LocalHaasSettings.model,
                context: TranscriptionRequestContext(language: "auto"), timeout: 120)
            precondition(text.contains("会議") && (text.contains("。") || text.contains("、")))
            print("PASS: first download + bundled recognition: \(text)")
            let restarted = LocalHaasRuntime(runtimeURL: runtimePath, modelsURL: models, session: offline)
            try await restarted.prepare()
            let offlineService = OpenAICompatibleTranscriptionService(localRuntime: { restarted })
            let result = try await offlineService.transcribe(audioURL: audio, model: LocalHaasSettings.model,
                context: TranscriptionRequestContext(language: "auto"), timeout: 120)
            precondition(result.contains("会議"))
            print("PASS: fresh runtime restarts offline without a download: \(result)")
        }
    }
}
