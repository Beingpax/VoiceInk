import Foundation
import OSLog
import SwiftData

actor AutoLearnService {
    static let shared = AutoLearnService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearn")
    private let accessibilityRuntime = AutoLearnAXRuntime()
    private let focusObserver = AutoLearnFocusObserver()
    private let pendingQueue = AutoLearnPendingQueue()
    private let reviewProposalStore = AutoLearnReviewProposalStore()

    private var replacementStore: WordReplacementStore?
    private var lifecycleGeneration: UInt64 = 0
    private var snapshotCancellationGeneration: UInt64 = 0
    private var activeToken: AutoLearnPasteToken?
    private var activeGeneration: UInt64?
    private var activeProcessID: pid_t?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration: UInt64 = 0
    private var claimedCandidateIDs = Set<UUID>()
    private var preparationTask: Task<Void, Error>?
    private var isPrepared = false
    private var suggestionSettingsGeneration: UInt64 = 0
    private var isUpdatingSuggestionThreshold = false

    private init() {}

    func configure(modelContainer: ModelContainer) async {
        guard replacementStore == nil else { return }
        let store = WordReplacementStore(modelContainer: modelContainer)
        replacementStore = store
        do {
            try await prepareForReview()
            await notifyQueueChanged()
            await suggestionThresholdDidChange()
        } catch {
            AutoLearnSettings.recordFailure(error)
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
            do {
                if !UserDefaults.standard.bool(forKey: AutoLearnSettings.legacyBacklogDiscardedKey) {
                    try await pendingQueue.discardAll()
                    try await reviewProposalStore.discardAll()
                    UserDefaults.standard.set(true, forKey: AutoLearnSettings.legacyBacklogDiscardedKey)
                    AutoLearnSettings.clearFailure()
                }
                try await pendingQueue.recoverInterruptedReviews()
                isPrepared = true
                preparationTask = nil
            } catch {
                preparationTask = nil
                throw error
            }
        }
        preparationTask = task
        try await task.value
    }

    func settingDidChange(isEnabled: Bool) async {
        if isEnabled {
            await suggestionThresholdDidChange()
            return
        }
        suggestionSettingsGeneration &+= 1
        isUpdatingSuggestionThreshold = false
        await cancelReviewTask()
        lifecycleGeneration &+= 1
        await discardActiveSession()
        await MainActor.run { AutoLearnSuggestionController.shared.update([]) }
    }

    func suggestionThresholdDidChange() async {
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
            try await updateSuggestionThreshold(generation: generation)
            guard suggestionSettingsGeneration == generation else { return }
            isUpdatingSuggestionThreshold = false
            AutoLearnSettings.clearFailure()
            await refreshSuggestionPanel()
            await schedulePendingReview()
        } catch {
            guard suggestionSettingsGeneration == generation else { return }
            isUpdatingSuggestionThreshold = false
            await MainActor.run { AutoLearnSuggestionController.shared.update([]) }
            AutoLearnSettings.recordFailure(error)
            log(error, message: "Failed to update Auto Learn suggestion threshold")
        }
    }

    private func updateSuggestionThreshold(generation: UInt64) async throws {
        guard let replacementStore else { return }
        let counted = try await reviewProposalStore.countedSuggestions()
        let eligible = try await replacementStore.unsavedSuggestions(counted)
        guard suggestionSettingsGeneration == generation else { throw CancellationError() }
        try await reviewProposalStore.updateThreshold(
            minimumCorrections: AutoLearnSettings.minimumCorrections,
            eligibleDecisions: eligible)
    }

    func applyReviewProposal(_ proposalID: UUID) async throws -> AutoLearnMutationSummary {
        guard isPrepared, AutoLearnSettings.isEnabled, let replacementStore else { return .empty }
        guard let proposal = try await reviewProposalStore.all().first(where: { $0.id == proposalID }),
            proposal.learningAction == .addReplacementOnly,
            AutoLearnLocalReviewPolicy.accepts(
                source: proposal.addsReplacement ? proposal.incorrectTextToReplace ?? "" : nil,
                destination: proposal.correctedVocabularyTerm ?? "")
        else { return .empty }

        let summary = try await replacementStore.apply(
            [proposal.reviewDecision], candidates: [proposal.reviewCandidate])
        try await reviewProposalStore.remove([proposalID])
        await refreshSuggestionPanel()

        if summary.hasChanges {
            await MainActor.run {
                NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
            }
        }
        return summary
    }

    func dismissReviewProposals(_ proposalIDs: Set<UUID>) async throws {
        try await reviewProposalStore.dismiss(proposalIDs)
        await refreshSuggestionPanel()
    }

    func retryPendingReviews() async {
        do {
            try await prepareForReview()
            await suggestionThresholdDidChange()
        } catch {
            AutoLearnSettings.recordFailure(error)
            log(error, message: "Failed to prepare Auto Learn reviews")
        }
    }

    func outstandingReviewCount() async throws -> Int {
        try await pendingQueue.outstandingCount()
    }

    func recordingDidStart() async {
        guard AutoLearnSettings.isEnabled else { return }
        if let token = activeToken {
            await completeSession(token: token, persist: true)
        }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func pasteDidFinish(text: String, processID: pid_t?, commandPosted: Bool) async -> UInt64? {
        guard AutoLearnSettings.isEnabled,
            isPrepared,
            replacementStore != nil,
            commandPosted,
            let processID
        else {
            return nil
        }

        // Finalize the previous session after Command-V so Accessibility and
        // SwiftData work do not delay the paste.
        let previousToken = activeToken
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        deadlineTask?.cancel()
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil

        guard lifecycleGeneration == generation, AutoLearnSettings.isEnabled else { return nil }

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
        guard AutoLearnSettings.isEnabled else { return }
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
        await MainActor.run { AutoLearnSuggestionController.shared.update([]) }
    }

    func focusMayHaveChanged(token: AutoLearnPasteToken) {
        guard AutoLearnSettings.isEnabled, activeToken == token else { return }
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
            AutoLearnSettings.isEnabled
        else { return }

        guard let token = await accessibilityRuntime.capturePastedText(
                text: text,
                processID: processID
            )
        else { return }

        guard lifecycleGeneration == generation,
            !Task.isCancelled,
            AutoLearnSettings.isEnabled
        else {
            await accessibilityRuntime.discard(token: token)
            return
        }

        activeToken = token
        activeGeneration = generation
        activeProcessID = processID
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

    private func discardActiveSession() async {
        snapshotCancellationGeneration &+= 1
        let token = activeToken
        deadlineTask?.cancel()
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil
        if let token {
            await accessibilityRuntime.discard(token: token)
        } else {
            await accessibilityRuntime.discard()
        }
    }

    private func completeSession(token: AutoLearnPasteToken, persist: Bool) async {
        guard activeToken == token, activeGeneration != nil else { return }
        deadlineTask?.cancel()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()

        if persist {
            await persistFinishedSession(token: token)
        } else {
            await accessibilityRuntime.discard(token: token)
        }
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
            AutoLearnSettings.isEnabled
        else {
            return
        }

        guard !(await accessibilityRuntime.targetIsFocused(token: token)) else { return }
        await completeSession(token: token, persist: true)
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
        guard activeToken == token, AutoLearnSettings.isEnabled else { return }
        await completeSession(token: token, persist: true)
    }

    private func persistSnapshot(_ snapshot: AutoLearnFieldSnapshot?) async {
        guard AutoLearnSettings.isEnabled,
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
            await notifyQueueChanged()
        } catch {
            log(error, message: "Failed to queue Auto Learn candidates")
        }
    }

    private func schedulePendingReview() async {
        guard isPrepared, !isUpdatingSuggestionThreshold, reviewTask == nil,
            AutoLearnSettings.isEnabled, replacementStore != nil else { return }
        let count = (try? await pendingQueue.pendingCount()) ?? 0
        guard count > 0, !isUpdatingSuggestionThreshold, reviewTask == nil,
            AutoLearnSettings.isEnabled else { return }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        reviewTask = Task { [weak self] in
            await self?.processPendingReview(generation: generation)
        }
    }

    private func processPendingReview(generation: UInt64) async {
        while true {
            guard !Task.isCancelled, reviewGeneration == generation,
                AutoLearnSettings.isEnabled, let replacementStore else {
                try? await releaseAllClaimsToQueue()
                await finishReviewTask(generation: generation)
                return
            }

            let reviewID = UUID()
            do {
                guard let candidate = try await pendingQueue.claimNext() else {
                    await finishReviewTask(generation: generation)
                    await schedulePendingReview()
                    return
                }
                let candidates = [candidate]
                let candidateIDs: Set<UUID> = [candidate.candidateID]
                claimedCandidateIDs.formUnion(candidateIDs)

                let suggestions = try await AutoLearnLocalReviewer().review(candidate, reviewID: reviewID)
                try Task.checkCancellation()
                guard reviewGeneration == generation, AutoLearnSettings.isEnabled else {
                    throw CancellationError()
                }
                let unsavedSuggestions = try await replacementStore.unsavedSuggestions(suggestions)
                try Task.checkCancellation()
                guard reviewGeneration == generation, AutoLearnSettings.isEnabled else {
                    throw CancellationError()
                }
                let queuedSuggestions = try await reviewProposalStore.append(
                    decisions: unsavedSuggestions, candidates: candidates,
                    minimumCorrections: AutoLearnSettings.minimumCorrections)
                try await pendingQueue.remove(candidateIDs)
                releaseClaim(candidateIDs)
                await notifyQueueChanged()
                AutoLearnSettings.clearFailure()
                logger.notice("Auto Learn review completed reviewID=\(reviewID.uuidString, privacy: .public) suggestions=\(suggestions.count, privacy: .public) queuedSuggestions=\(queuedSuggestions, privacy: .public)")

                await refreshSuggestionPanel()
            } catch {
                try? await releaseAllClaimsToQueue()
                if !Task.isCancelled, !(error is CancellationError), reviewGeneration == generation {
                    AutoLearnSettings.recordFailure(error)
                }
                await finishReviewTask(generation: generation)
                log(error, message: "Auto Learn review interrupted; correction remains queued reviewID=\(reviewID)")
                return
            }
        }
    }

    private func releaseClaim(_ candidateIDs: Set<UUID>) {
        claimedCandidateIDs.subtract(candidateIDs)
    }

    private func releaseAllClaimsToQueue() async throws {
        guard !claimedCandidateIDs.isEmpty else { return }
        let claimedIDs = claimedCandidateIDs
        try await pendingQueue.release(claimedIDs)
        claimedCandidateIDs.subtract(claimedIDs)
    }

    private func finishReviewTask(generation: UInt64) async {
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

        guard !claimedCandidateIDs.isEmpty else { return }
        let claimedIDs = claimedCandidateIDs
        claimedCandidateIDs = []
        try? await pendingQueue.release(claimedIDs)
        await notifyQueueChanged()
    }

    private func notifyQueueChanged() async {
        let outstandingCount = (try? await pendingQueue.outstandingCount()) ?? 0
        await MainActor.run {
            NotificationCenter.default.post(
                name: .autoLearnQueueDidChange,
                object: outstandingCount
            )
        }
    }

    private func refreshSuggestionPanel() async {
        guard isPrepared else { return }
        guard let proposals = try? await reviewProposalStore.all() else { return }
        await MainActor.run {
            AutoLearnSuggestionController.shared.update(AutoLearnSettings.isEnabled ? proposals : [])
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
