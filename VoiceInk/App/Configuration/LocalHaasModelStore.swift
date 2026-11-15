import CryptoKit
import Foundation

struct LocalHaasModelFile: Codable, Equatable, Sendable {
    let path: String
    let url: URL
    let size: Int64
    let sha256: String
}

enum LocalHaasError: LocalizedError {
    case runtimeMissing, modelsMissing, invalidDownload(String), workerFailed, insufficientSpace
    var errorDescription: String? {
        switch self {
        case .runtimeMissing: return "HaaSの実行環境がアプリに含まれていません。アプリを再インストールしてください。"
        case .modelsMissing: return "HaaSとHorizonのモデルをダウンロードしてください。"
        case .invalidDownload(let name): return "モデルの検証に失敗しました（\(name)）。再試行してください。"
        case .workerFailed: return "ローカル音声認識に失敗しました。音声ファイルとモデルを確認してください。"
        case .insufficientSpace: return "モデルの導入には約1.4GBの空き容量が必要です。"
        }
    }
}

/// Serializes installation; downloaded bytes are never loaded as executable code.
actor LocalHaasModelStore {
    let root: URL
    let files: [LocalHaasModelFile]
    private let session: URLSession

    init(root: URL, files: [LocalHaasModelFile], session: URLSession = .shared) {
        self.root = root
        self.files = files
        self.session = session
    }

    static func sha256(_ url: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hash = SHA256()
        while let bytes = try stream.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func isReady() -> Bool {
        guard !files.isEmpty,
            let data = try? Data(contentsOf: root.appendingPathComponent("installed.json")),
            let installed = try? JSONDecoder().decode([LocalHaasModelFile].self, from: data), installed == files
        else { return false }
        return files.allSatisfy { file in
            let size = try? root.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return Int64(size ?? -1) == file.size
        }
    }

    func install(progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        guard !files.isEmpty else { throw LocalHaasError.runtimeMissing }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        if !isReady() {
            let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            let filesystem = try fm.attributesOfFileSystem(forPath: root.path)
            // Important-usage capacity can report 0 even when the filesystem has free space.
            let capacity = max(values.volumeAvailableCapacityForImportantUsage ?? 0,
                max(Int64(values.volumeAvailableCapacity ?? 0),
                    (filesystem[.systemFreeSize] as? NSNumber)?.int64Value ?? 0))
            guard capacity >= files.reduce(0, { $0 + $1.size }) * 2 else { throw LocalHaasError.insufficientSpace }
        }
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains(".."),
                file.url.scheme == "https", file.size > 0
            else { throw LocalHaasError.invalidDownload(file.path) }
            progress(index, files.count)
            let destination = root.appendingPathComponent(file.path)
            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                Int64(size) == file.size, try Self.sha256(destination) == file.sha256 {
                continue
            }
            // URLSession's temporary file is never published as an installed model until verified.
            let (temporary, response) = try await session.download(from: file.url)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                Int64(size) == file.size, try Self.sha256(temporary) == file.sha256
            else { throw LocalHaasError.invalidDownload(file.path) }
            try Task.checkCancellation()
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Stage on the destination filesystem, then replace atomically.
            let staged = destination.deletingLastPathComponent().appendingPathComponent(".download-\(UUID())")
            try fm.copyItem(at: temporary, to: staged)
            defer { try? fm.removeItem(at: staged) }
            try Task.checkCancellation()
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
        }
        try Task.checkCancellation()
        try JSONEncoder().encode(files).write(to: root.appendingPathComponent("installed.json"), options: .atomic)
        progress(files.count, files.count)
    }
}
