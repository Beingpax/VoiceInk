import Foundation
import OSLog
import SwiftData

actor AutoLearnService {
    static let shared = AutoLearnService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearn")
    private let accessibilityRuntime = AutoLearnAXRuntime()
    private let focusObserver = AutoLearnFocusObserver()
    private let pendingQueue: AutoLearnPendingQueue
    private let reviewProposalStore: AutoLearnReviewProposalStore
    private let defaults: UserDefaults
    private var suggestionsDidChange: @MainActor @Sendable ([AutoLearnSuggestion]) -> Void = { _ in }

    private var replacementStore: WordReplacementStore?
    private var lifecycleGeneration: UInt64 = 0
    private var snapshotCancellationGeneration: UInt64 = 0
    private var activeToken: AutoLearnPasteToken?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration: UInt64 = 0
    private var claimedCandidateIDs = Set<UUID>()
    private var preparationTask: Task<Void, Error>?
    private var isPrepared = false
    private var isRepairingData = false
    private var suggestionSettingsGeneration: UInt64 = 0
    private var isUpdatingSuggestionThreshold = false

    init(defaults: UserDefaults = .standard,
        pendingQueue: AutoLearnPendingQueue = AutoLearnPendingQueue(),
        reviewProposalStore: AutoLearnReviewProposalStore = AutoLearnReviewProposalStore()) {
        self.defaults = defaults
        self.pendingQueue = pendingQueue
        self.reviewProposalStore = reviewProposalStore
    }

    private var isEnabled: Bool { defaults.bool(forKey: AutoLearnSettings.isEnabledKey) }
    private var minimumCorrections: Int {
        AutoLearnSettings.clampedMinimumCorrections(defaults.integer(forKey: AutoLearnSettings.minimumCorrectionsKey))
    }

    func configure(modelContainer: ModelContainer,
        onSuggestionsChanged: @escaping @MainActor @Sendable ([AutoLearnSuggestion]) -> Void = { _ in }) async {
        guard replacementStore == nil else { return }
        suggestionsDidChange = onSuggestionsChanged
        replacementStore = WordReplacementStore(modelContainer: modelContainer)
        do {
            try await prepareForReview()
            await suggestionThresholdDidChange()
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to prepare Auto Learn reviews")
        }
    }

    private func prepareForReview() async throws {
        guard !isPrepared else { return }
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task<Void, Error> {
            defer { preparationTask = nil }
            if !defaults.bool(forKey: AutoLearnSettings.legacyBacklogDiscardedKey) {
                try await pendingQueue.discardAll()
                try await reviewProposalStore.discardAll()
                defaults.set(true, forKey: AutoLearnSettings.legacyBacklogDiscardedKey)
                AutoLearnSettings.clearFailure(defaults: defaults)
            }
            try await pendingQueue.recoverInterruptedReviews()
            isPrepared = true
        }
        preparationTask = task
        try await task.value
    }

    func settingDidChange(isEnabled: Bool) async {
        guard isEnabled == self.isEnabled, !isRepairingData else { return }
        if isEnabled {
            do {
                try await prepareForReview()
                await suggestionThresholdDidChange()
            } catch {
                AutoLearnSettings.recordFailure(error, defaults: defaults)
            }
            return
        }
        suggestionSettingsGeneration &+= 1
        let generation = suggestionSettingsGeneration
        isUpdatingSuggestionThreshold = false
        await cancelReviewTask()
        guard suggestionSettingsGeneration == generation else { return }
        lifecycleGeneration &+= 1
        await discardActiveSession()
        guard suggestionSettingsGeneration == generation else { return }
        if !self.isEnabled { await suggestionsDidChange([]) }
    }

    func suggestionThresholdDidChange() async {
        guard !isRepairingData else { return }
        suggestionSettingsGeneration &+= 1
        let generation = suggestionSettingsGeneration
        isUpdatingSuggestionThreshold = true
        await cancelReviewTask()
        guard suggestionSettingsGeneration == generation else { return }
        guard isPrepared else {
            isUpdatingSuggestionThreshold = false
            return
        }
        do {
            try await updateSuggestions(settingsGeneration: generation)
            guard suggestionSettingsGeneration == generation else { return }
            isUpdatingSuggestionThreshold = false
            AutoLearnSettings.clearFailure(defaults: defaults)
            await refreshSuggestionPanel()
            await schedulePendingReview()
        } catch {
            guard suggestionSettingsGeneration == generation else { return }
            isUpdatingSuggestionThreshold = false
            await suggestionsDidChange([])
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to update Auto Learn suggestion threshold")
        }
    }

    @discardableResult
    private func updateSuggestions(
        _ suggestions: [AutoLearnReviewDecision] = [],
        candidates: [AutoLearnReviewCandidate] = [],
        settingsGeneration: UInt64
    ) async throws -> Int {
        guard let replacementStore else { return 0 }
        let counted = try await reviewProposalStore.countedSuggestions()
        let eligible = try await replacementStore.unsavedSuggestions(counted + suggestions)
        try Task.checkCancellation()
        guard suggestionSettingsGeneration == settingsGeneration else {
            throw CancellationError()
        }
        return try await reviewProposalStore.update(
            decisions: suggestions, candidates: candidates,
            minimumCorrections: minimumCorrections,
            eligibleDecisions: eligible)
    }

    func applySuggestion(_ suggestion: AutoLearnSuggestion) async throws {
        guard isPrepared, isEnabled, let replacementStore else { return }
        guard let current = try await reviewProposalStore.matching(suggestion) else {
            await refreshSuggestionPanel()
            return
        }

        if try await replacementStore.apply(current) {
            await MainActor.run {
                NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
            }
        }
        try await reviewProposalStore.removeApprovedSuggestion(current)
        await refreshSuggestionPanel()
    }

    func dismissSuggestion(_ suggestion: AutoLearnSuggestion) async throws {
        guard isPrepared, isEnabled else { return }
        try await reviewProposalStore.dismiss(suggestion)
        await refreshSuggestionPanel()
    }

    func checkDataHealth() async throws -> AutoLearnDataHealth {
        let health: AutoLearnDataHealth
        do {
            health = try await AutoLearnDataRepair.health(
                pendingQueue: pendingQueue, proposalStore: reviewProposalStore)
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults, isDataHealthFailure: true)
            throw error
        }
        if health.needsRepair {
            AutoLearnSettings.recordFailure(AutoLearnDataRepair.Failure.damagedData, defaults: defaults,
                isDataHealthFailure: true)
        } else {
            if defaults.bool(forKey: AutoLearnSettings.dataHealthFailureKey) {
                AutoLearnSettings.clearFailure(defaults: defaults, includingDataHealthFailure: true)
            }
            if !isPrepared, !isRepairingData, isEnabled, replacementStore != nil {
                do {
                    try await prepareForReview()
                    await suggestionThresholdDidChange()
                } catch {
                    AutoLearnSettings.recordFailure(error, defaults: defaults)
                    throw error
                }
            }
        }
        return health
    }

    func repairData() async throws {
        guard !isRepairingData else { return }
        isRepairingData = true
        defer { isRepairingData = false }
        suggestionSettingsGeneration &+= 1
        isUpdatingSuggestionThreshold = false
        if let preparationTask { _ = try? await preparationTask.value }
        isPrepared = false
        lifecycleGeneration &+= 1
        await discardActiveSession()
        await cancelReviewTask()
        await suggestionsDidChange([])
        do {
            try await AutoLearnDataRepair.repair(pendingQueue: pendingQueue, proposalStore: reviewProposalStore)
            try await prepareForReview()
            claimedCandidateIDs = []
            AutoLearnSettings.clearFailure(defaults: defaults, includingDataHealthFailure: true)
            isRepairingData = false
            if isEnabled { await suggestionThresholdDidChange() }
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            throw error
        }
    }

    func recordingDidStart() async {
        guard isEnabled else { return }
        if let token = activeToken {
            await completeSession(token: token)
        }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func pasteDidFinish(text: String, processID: pid_t?, commandPosted: Bool) async -> UInt64? {
        guard isEnabled,
            isPrepared, !isRepairingData,
            replacementStore != nil,
            commandPosted,
            let processID
        else {
            return nil
        }

        // Finalize the previous session after Command-V so Accessibility and
        // SwiftData work do not delay the paste.
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let previousToken = resetObservation()

        guard lifecycleGeneration == generation, isEnabled else { return nil }

        deadlineTask = Task { [weak self] in
            if let previousToken {
                // `finishSnapshot` drops the session, so the pending capture is
                // cancelled before a new one can be started.
                await self?.persistFinishedSession(token: previousToken)
            }
            await self?.beginObservation(
                text: text,
                processID: processID,
                generation: generation
            )
        }
        return generation
    }

    func cancelForAutoSend(generation: UInt64) async {
        guard isEnabled else { return }
        guard lifecycleGeneration == generation else { return }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func shutdown() async {
        suggestionSettingsGeneration &+= 1
        isUpdatingSuggestionThreshold = false
        lifecycleGeneration &+= 1
        await cancelReviewTask()
        await discardActiveSession()
        await suggestionsDidChange([])
    }

    func focusMayHaveChanged(token: AutoLearnPasteToken) {
        guard isEnabled, activeToken == token else { return }
        focusFinalizationTask?.cancel()
        focusFinalizationTask = Task { [weak self] in
            await self?.finalizeIfFocusLeft(token: token)
        }
    }

    private func beginObservation(
        text: String,
        processID: pid_t,
        generation: UInt64
    ) async {
        guard await sleep(nanoseconds: AutoLearnLimits.verificationDelayNanoseconds),
            !Task.isCancelled,
            lifecycleGeneration == generation,
            isEnabled
        else { return }

        guard let token = await accessibilityRuntime.capturePastedText(
                text: text,
                processID: processID
            )
        else { return }

        guard lifecycleGeneration == generation,
            !Task.isCancelled,
            isEnabled
        else {
            await accessibilityRuntime.discard(token: token)
            return
        }

        activeToken = token
        focusObserver.start(processID: processID, token: token) { token in
            Task {
                await AutoLearnService.shared.focusMayHaveChanged(token: token)
            }
        }
        scheduleDeadline(
            token: token,
            after: AutoLearnLimits.observationDurationNanoseconds
        )
    }

    @discardableResult
    private func resetObservation() -> AutoLearnPasteToken? {
        let token = activeToken
        deadlineTask?.cancel()
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()
        activeToken = nil
        return token
    }

    private func discardActiveSession() async {
        snapshotCancellationGeneration &+= 1
        let token = resetObservation()
        if let token {
            await accessibilityRuntime.discard(token: token)
        } else {
            await accessibilityRuntime.discard()
        }
    }

    private func completeSession(token: AutoLearnPasteToken) async {
        guard activeToken == token else { return }
        resetObservation()
        await persistFinishedSession(token: token)
    }

    private func persistFinishedSession(token: AutoLearnPasteToken) async {
        let cancellationGeneration = snapshotCancellationGeneration
        let snapshot = await accessibilityRuntime.finishSnapshot(token: token)
        guard snapshotCancellationGeneration == cancellationGeneration else { return }
        await persistSnapshot(snapshot)
    }

    private func finalizeIfFocusLeft(token: AutoLearnPasteToken) async {
        guard await sleep(nanoseconds: AutoLearnLimits.focusChangeGraceNanoseconds),
            !Task.isCancelled,
            activeToken == token,
            isEnabled
        else {
            return
        }

        guard !(await accessibilityRuntime.targetIsFocused(token: token)) else { return }
        await completeSession(token: token)
    }

    private func scheduleDeadline(token: AutoLearnPasteToken, after delay: UInt64) {
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            guard let self,
                await self.sleep(nanoseconds: delay),
                !Task.isCancelled
            else { return }
            await self.finalizeAtDeadline(token: token)
        }
    }

    private func finalizeAtDeadline(token: AutoLearnPasteToken) async {
        guard activeToken == token, isEnabled else { return }
        await completeSession(token: token)
    }

    private func persistSnapshot(_ snapshot: AutoLearnFieldSnapshot?) async {
        guard isEnabled, isPrepared,
            let snapshot
        else { return }

        guard let revision = FinalSnapshotDiffEngine.revision(from: snapshot) else { return }
        let candidates = CorrectionDiffEngine.candidates(from: revision)
        guard !candidates.isEmpty else { return }

        do {
            let insertedCount = try await pendingQueue.enqueue(candidates)
            if insertedCount > 0 {
                logger.notice(
                    "Queued \(insertedCount, privacy: .public) Auto Learn candidate(s) for review"
                )
                await schedulePendingReview()
            }
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to queue Auto Learn candidates")
        }
    }

    private func schedulePendingReview() async {
        guard isPrepared, !isUpdatingSuggestionThreshold, reviewTask == nil,
            isEnabled, replacementStore != nil else { return }
        let count: Int
        do {
            try await releaseAllClaimsToQueue()
            count = try await pendingQueue.pendingCount()
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to prepare pending Auto Learn corrections")
            return
        }
        guard count > 0, !isUpdatingSuggestionThreshold, reviewTask == nil,
            isEnabled else { return }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        reviewTask = Task { [weak self] in
            await self?.processPendingReview(generation: generation)
        }
    }

    private func processPendingReview(generation: UInt64) async {
        while true {
            guard !Task.isCancelled, reviewGeneration == generation,
                isEnabled, replacementStore != nil else {
                try? await releaseAllClaimsToQueue()
                finishReviewTask(generation: generation)
                return
            }

            let reviewID = UUID()
            do {
                guard let candidate = try await pendingQueue.claimNext() else {
                    finishReviewTask(generation: generation)
                    await schedulePendingReview()
                    return
                }
                let candidates = [candidate]
                let candidateIDs: Set<UUID> = [candidate.candidateID]
                claimedCandidateIDs.formUnion(candidateIDs)

                let suggestions = try await AutoLearnLocalReviewer().review(candidate, reviewID: reviewID)
                try Task.checkCancellation()
                guard reviewGeneration == generation, isEnabled else {
                    throw CancellationError()
                }
                let queuedSuggestions = try await updateSuggestions(
                    suggestions, candidates: candidates, settingsGeneration: suggestionSettingsGeneration)
                try Task.checkCancellation()
                guard reviewGeneration == generation, isEnabled else {
                    throw CancellationError()
                }
                try await pendingQueue.remove(candidateIDs)
                claimedCandidateIDs.subtract(candidateIDs)
                AutoLearnSettings.clearFailure(defaults: defaults)
                logger.notice("Auto Learn review completed reviewID=\(reviewID.uuidString, privacy: .public) suggestions=\(suggestions.count, privacy: .public) queuedSuggestions=\(queuedSuggestions, privacy: .public)")

                await refreshSuggestionPanel()
            } catch {
                try? await releaseAllClaimsToQueue()
                if !Task.isCancelled, !(error is CancellationError), reviewGeneration == generation {
                    AutoLearnSettings.recordFailure(error, defaults: defaults)
                }
                finishReviewTask(generation: generation)
                log(error, message: "Auto Learn review interrupted; correction remains queued reviewID=\(reviewID)")
                return
            }
        }
    }

    private func releaseAllClaimsToQueue() async throws {
        guard !claimedCandidateIDs.isEmpty else { return }
        let claimedIDs = claimedCandidateIDs
        try await pendingQueue.release(claimedIDs)
        claimedCandidateIDs.subtract(claimedIDs)
    }

    private func finishReviewTask(generation: UInt64) {
        guard reviewGeneration == generation else { return }
        reviewTask = nil
    }

    private func cancelReviewTask() async {
        reviewGeneration &+= 1
        let cancellationGeneration = reviewGeneration
        let cancelledTask = reviewTask
        cancelledTask?.cancel()
        if let cancelledTask {
            await cancelledTask.value
        }
        guard reviewGeneration == cancellationGeneration else { return }
        reviewTask = nil

        do {
            try await releaseAllClaimsToQueue()
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to release an Auto Learn correction")
        }
    }

    private func refreshSuggestionPanel() async {
        guard isPrepared else { return }
        do {
            let suggestions = try await reviewProposalStore.all()
            await suggestionsDidChange(isEnabled ? suggestions : [])
        } catch {
            AutoLearnSettings.recordFailure(error, defaults: defaults)
            log(error, message: "Failed to load Auto Learn suggestions")
            await suggestionsDidChange([])
        }
    }

    private func log(_ error: Error, message: String) {
        let nsError = error as NSError
        logger.error(
            "\(message, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }

    private func sleep(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return true
        } catch {
            return false
        }
    }
}
