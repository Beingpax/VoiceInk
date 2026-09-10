import Foundation

actor AutoLearnPendingQueue {
    private enum Status: String, Codable {
        case pending
        case reviewing
    }

    private struct Record: Codable {
        let id: UUID
        let source: String
        let destination: String
        var status: Status

        var candidate: AutoLearnReviewCandidate {
            AutoLearnReviewCandidate(id: id, source: source, destination: destination)
        }
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private var records: [Record] = []
    private var didLoad = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = applicationSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("auto-learn-pending.json")
    }

    func recoverInterruptedReviews() throws {
        try loadIfNeeded()
        let originalCount = records.count
        var changed = false
        for index in records.indices where records[index].status == .reviewing {
            records[index].status = .pending
            changed = true
        }
        trimToLimit()
        if changed || records.count != originalCount {
            try save()
        }
    }

    func enqueue(_ candidates: [LearnedReplacementCandidate]) throws -> Int {
        guard !candidates.isEmpty else { return 0 }
        try loadIfNeeded()

        var knownPairs = Set(
            records.map { pairKey(source: $0.source, destination: $0.destination) }
        )
        var insertedCount = 0
        for candidate in candidates {
            let source = candidate.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = candidate.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !destination.isEmpty else { continue }

            let key = pairKey(source: source, destination: destination)
            guard knownPairs.insert(key).inserted else { continue }
            records.append(
                Record(
                    id: UUID(),
                    source: source,
                    destination: destination,
                    status: .pending
                )
            )
            insertedCount += 1
        }

        if insertedCount > 0 {
            trimToLimit()
            try save()
        }
        return insertedCount
    }

    func claimPending() throws -> [AutoLearnReviewCandidate] {
        try loadIfNeeded()

        let indices = records.indices
            .filter { records[$0].status == .pending }
        guard !indices.isEmpty else { return [] }

        for index in indices {
            records[index].status = .reviewing
        }
        try save()
        return indices.map { records[$0].candidate }
    }

    func release(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try loadIfNeeded()

        var changed = false
        for index in records.indices where ids.contains(records[index].id) {
            records[index].status = .pending
            changed = true
        }
        if changed {
            try save()
        }
    }

    func remove(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try loadIfNeeded()

        let originalCount = records.count
        records.removeAll { ids.contains($0.id) }
        if records.count != originalCount {
            try save()
        }
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            didLoad = true
            return
        }

        let data = try Data(contentsOf: fileURL)
        records = try JSONDecoder().decode([Record].self, from: data)
        didLoad = true
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private func pairKey(source: String, destination: String) -> String {
        WordReplacementVariants.key(for: source) + "\u{0}"
            + WordReplacementVariants.destinationKey(for: destination)
    }

    private func trimToLimit() {
        let overflow = records.count - AutoLearnLimits.maximumPendingCandidates
        guard overflow > 0 else { return }

        let removableIDs = Set(
            records.lazy
                .filter { $0.status == .pending }
                .prefix(overflow)
                .map(\.id)
        )
        records.removeAll { removableIDs.contains($0.id) }
    }
}
