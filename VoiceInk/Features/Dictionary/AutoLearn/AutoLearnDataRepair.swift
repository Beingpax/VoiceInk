import Foundation

struct AutoLearnDataHealth: Sendable {
    var needsRepair = false
    var resetsDismissals = false
}

enum AutoLearnDataRepair {
    enum Failure: LocalizedError {
        case damagedData

        var errorDescription: String? {
            String(localized: "Auto-Learn data needs repair.")
        }
    }

    struct File: Sendable {
        let url: URL
        var resetsDismissals = false
        let initialData: @Sendable () throws -> Data
        let validate: @Sendable (Data) throws -> Void
    }

    static func health(pendingQueue: AutoLearnPendingQueue,
        proposalStore: AutoLearnReviewProposalStore) async throws -> AutoLearnDataHealth {
        let pending = try await pendingQueue.dataHealth()
        let proposals = try await proposalStore.dataHealth()
        return AutoLearnDataHealth(needsRepair: pending.needsRepair || proposals.needsRepair,
            resetsDismissals: pending.resetsDismissals || proposals.resetsDismissals)
    }

    static func repair(pendingQueue: AutoLearnPendingQueue,
        proposalStore: AutoLearnReviewProposalStore) async throws {
        try await pendingQueue.repairDamagedData()
        try await proposalStore.repairDamagedData()
    }

    static func health(of files: [File]) throws -> AutoLearnDataHealth {
        var health = AutoLearnDataHealth()
        for file in files where try damagedData(at: file.url, validate: file.validate) != nil {
            health.needsRepair = true
            health.resetsDismissals = health.resetsDismissals || file.resetsDismissals
        }
        return health
    }

    static func repair(_ files: [File], onRepair: () -> Void) throws {
        for file in files {
            guard let damaged = try damagedData(at: file.url, validate: file.validate) else { continue }
            let initialData = try file.initialData()
            try file.validate(initialData)
            let backup = file.url.appendingPathExtension("damaged-\(UUID().uuidString).bak")
            try damaged.write(to: backup, options: .withoutOverwriting)
            try initialData.write(to: file.url, options: .atomic)
            onRepair()
        }
    }

    private static func damagedData(at url: URL, validate: (Data) throws -> Void) throws -> Data? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            return nil
        }
        do {
            try validate(data)
            return nil
        } catch {
            let nsError = error as NSError
            guard error is DecodingError
                || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSPropertyListReadCorruptError)
            else { throw error }
            return data
        }
    }
}
