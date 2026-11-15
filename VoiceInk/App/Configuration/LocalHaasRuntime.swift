import Combine
import Foundation

@MainActor
final class LocalHaasRuntime: ObservableObject {
    static let shared = LocalHaasRuntime()
    @Published private(set) var isReady = false
    @Published private(set) var isDownloading = false
    @Published private(set) var completedFiles = 0
    @Published private(set) var totalFiles = 6
    @Published private(set) var errorMessage: String?
    let runtimeURL: URL
    let modelsURL: URL
    private let store: LocalHaasModelStore
    private var verifiedThisLaunch = false
    private var installTask: Task<Void, Error>?
    private var requests: [UUID: LocalHaasProcess] = [:]

    init(runtimeURL: URL? = nil, modelsURL: URL? = nil, session: URLSession = .shared) {
        self.runtimeURL = runtimeURL ?? Bundle.main.resourceURL!.appendingPathComponent("LocalHaas")
        self.modelsURL = modelsURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "VoiceInk")
            .appendingPathComponent("LocalHaas/Models-v1")
        let manifest = try? Data(contentsOf: self.runtimeURL.appendingPathComponent("models.json"))
        let files = manifest.flatMap { try? JSONDecoder().decode([LocalHaasModelFile].self, from: $0) } ?? []
        self.store = LocalHaasModelStore(root: self.modelsURL, files: files, session: session)
        totalFiles = files.count
    }

    var hasBundledRuntime: Bool {
        FileManager.default.isExecutableFile(atPath: runtimeURL.appendingPathComponent("python/bin/python3.13").path)
            && FileManager.default.fileExists(atPath: runtimeURL.appendingPathComponent("libspeech.4.dylib").path)
    }

    func refreshStatus() async {
        let installed = await store.isReady()
        if !isDownloading { isReady = hasBundledRuntime && installed }
    }

    func prepare() async throws {
        if let installTask { try await installTask.value; return }
        guard hasBundledRuntime else {
            errorMessage = LocalHaasError.runtimeMissing.localizedDescription
            throw LocalHaasError.runtimeMissing
        }
        if isReady && verifiedThisLaunch { return }
        isDownloading = true
        errorMessage = nil
        let store = self.store
        let task = Task { [weak self] in
            try await store.install { [weak self] completed, total in
                Task { @MainActor in
                    self?.completedFiles = completed
                    self?.totalFiles = total
                }
            }
        }
        installTask = task
        defer { installTask = nil; isDownloading = false }
        do {
            try await task.value
            isReady = true
            verifiedThisLaunch = true
        } catch {
            let wasCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            errorMessage = wasCancelled ? "ダウンロードを中止しました。再試行できます。" : error.localizedDescription
            throw error
        }
    }

    func cancelDownload() { installTask?.cancel() }

    func stopAll() {
        cancelDownload()
        requests.values.forEach { $0.cancel() }
    }

    func transcribe(audioURL: URL, timeout: TimeInterval) async throws -> String {
        try await prepare()
        try Task.checkCancellation()
        let ticket = LocalHaasProcess()
        let id = UUID()
        requests[id] = ticket
        defer { requests.removeValue(forKey: id) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("haas-\(id)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = try await ticket.run(executable: runtimeURL.appendingPathComponent("python/bin/python3.13"),
            arguments: ["-I", "-B", runtimeURL.appendingPathComponent("transcribe.py").path,
                        "--models", modelsURL.path, "--audio", audioURL.path],
            output: temporary.appendingPathComponent("result.json"), timeout: timeout)
        struct Result: Decodable { let text: String; let punctuation: String }
        let result = try JSONDecoder().decode(Result.self, from: data)
        guard ["applied", "unchanged"].contains(result.punctuation) else { throw LocalHaasError.workerFailed }
        return result.text
    }
}
