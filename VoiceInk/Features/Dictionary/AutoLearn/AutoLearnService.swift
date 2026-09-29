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
    private var reviewer: AutoLearnAIReviewer?
    private var lifecycleGeneration: UInt64 = 0
    private var snapshotCancellationGeneration: UInt64 = 0
    private var activeToken: AutoLearnPasteToken?
    private var activeGeneration: UInt64?
    private var activeProcessID: pid_t?
    private var activeLanguageCode: String?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration: UInt64 = 0
    private var claimedCandidateIDs = Set<UUID>()
    private var providerAvailabilityObserver: NSObjectProtocol?

    private init() {}

    func configure(modelContainer: ModelContainer, reviewer: AutoLearnAIReviewer) async {
        guard replacementStore == nil else { return }
        let store = WordReplacementStore(modelContainer: modelContainer)
        replacementStore = store
        self.reviewer = reviewer
        observeProviderAvailability()
        do {
            try await pendingQueue.recoverInterruptedReviews()
            await notifyQueueChanged()
            await schedulePendingReview()
        } catch {
            log(error, message: "Failed to recover queued Auto Learn reviews")
        }
    }

    /// Retries deferred reviews when `.AppSettingsDidChange` signals that a
    /// provider or Ollama connection may be available.
    private func observeProviderAvailability() {
        guard providerAvailabilityObserver == nil else { return }
        providerAvailabilityObserver = NotificationCenter.default.addObserver(
            forName: .AppSettingsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await AutoLearnService.shared.serviceConfigurationDidChange()
            }
        }
    }

    func serviceConfigurationDidChange() async {
        guard AutoLearnSettings.isEnabled else { return }
        guard (try? await pendingQueue.pendingCount()) ?? 0 > 0 else { return }
        await schedulePendingReview()
    }

    func settingDidChange(isEnabled: Bool) async {
        await cancelReviewTask()
        if isEnabled {
            await schedulePendingReview()
            return
        }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func reviewScheduleDidChange() async {
        await cancelReviewTask()
        guard AutoLearnSettings.isEnabled else { return }
        await schedulePendingReview()
    }

    func reviewMethodDidChange() async {
        await cancelReviewTask()
        if !AutoLearnSettings.isAIReviewEnabled,
            UserDefaults.standard.bool(forKey: AutoLearnSettings.isAIReviewFailureKey) {
            AutoLearnSettings.clearFailure()
        }
        guard AutoLearnSettings.isEnabled else { return }
        await schedulePendingReview()
    }

    private func reviewIsAvailable() async -> Bool {
        guard replacementStore != nil else { return false }
        if !AutoLearnSettings.isAIReviewEnabled { return true }
        return await reviewer?.hasAvailableProvider == true
    }

    private func reviewPendingNow() async {
        guard AutoLearnSettings.isEnabled else { return }
        guard reviewTask == nil else { return }
        await cancelReviewTask()
        await schedulePendingReview()
    }

    func preparePendingReviewForApproval() async {
        logger.notice("Manual Auto Learn review requested enabled=\(AutoLearnSettings.isEnabled, privacy: .public)")
        guard AutoLearnSettings.isEnabled else { return }
        await cancelReviewTask()
        await startPendingReviewForApproval()
    }

    private func startPendingReviewForApproval() async {
        guard await reviewIsAvailable() else {
            logger.notice("Manual Auto Learn review deferred: no provider available")
            return
        }
        let pendingCount: Int
        do {
            pendingCount = try await pendingQueue.pendingCount()
        } catch {
            log(error, message: "Manual Auto Learn review could not read the pending queue")
            return
        }
        guard pendingCount > 0 else {
            logger.notice("Manual Auto Learn review skipped reason=noPendingCandidates")
            return
        }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        reviewTask = Task { [weak self] in
            await self?.processPendingReviewBatch(
                generation: generation,
                stagesForApproval: true
            )
        }
        await reviewTask?.value
    }

    func reviewProposals() async throws -> [AutoLearnReviewProposal] {
        try await reviewProposalStore.all()
    }

    func reviewProposalCount() async throws -> Int {
        let proposals = try await reviewProposalStore.all()
        return proposals.count
    }

    func applyReviewProposals(
        _ selections: [AutoLearnReviewSelection]
    ) async throws -> AutoLearnMutationSummary {
        guard let replacementStore, !selections.isEmpty else { return .empty }
        let selectionsByID = Dictionary(
            uniqueKeysWithValues: selections.map { ($0.proposalID, $0) }
        )
        let proposals = try await reviewProposalStore.all().filter {
            selectionsByID[$0.id] != nil
        }
        guard !proposals.isEmpty else { return .empty }

        let candidates = Dictionary(
            proposals.map { ($0.candidateID, $0.reviewCandidate) },
            uniquingKeysWith: { first, _ in first }
        ).values.map { $0 }
        let decisions = proposals.compactMap { proposal -> AutoLearnReviewDecision? in
            guard let selection = selectionsByID[proposal.id] else { return nil }
            let action: AutoLearnReviewAction
            switch (selection.includesReplacement, selection.includesVocabulary) {
            case (true, true):
                action = .addReplacementAndVocabulary
            case (true, false):
                action = .addReplacementOnly
            case (false, true):
                action = .addVocabularyOnly
            case (false, false):
                return nil
            }
            return AutoLearnReviewDecision(
                candidateID: proposal.candidateID,
                learningAction: action,
                incorrectTextToReplace: action == .addVocabularyOnly
                    ? nil
                    : selection.incorrectTextToReplace,
                correctedVocabularyTerm: selection.correctedVocabularyTerm
            )
        }
        guard !decisions.isEmpty else { return .empty }
        let summary = try await replacementStore.apply(decisions, candidates: candidates)
        try await reviewProposalStore.remove(Set(proposals.map(\.id)))
        await notifyReviewProposalsChanged()

        if summary.hasChanges {
            await MainActor.run {
                NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
            }
            await showLearnedNotification(for: summary)
        }
        return summary
    }

    func dismissReviewProposals(_ proposalIDs: Set<UUID>) async throws {
        try await reviewProposalStore.remove(proposalIDs)
        await notifyReviewProposalsChanged()
    }

    func updateReviewProposal(
        proposalID: UUID,
        incorrectTextToReplace: String?,
        correctedVocabularyTerm: String
    ) async throws {
        try await reviewProposalStore.update(
            proposalID: proposalID,
            incorrectTextToReplace: incorrectTextToReplace,
            correctedVocabularyTerm: correctedVocabularyTerm
        )
    }

    func retryPendingReviews() async {
        if AutoLearnSettings.reviewSchedule == .manually {
            await preparePendingReviewForApproval()
        } else {
            await reviewPendingNow()
        }
    }

    func pendingReviewCount() async throws -> Int {
        try await pendingQueue.pendingCount()
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
            replacementStore != nil,
            commandPosted,
            let processID
        else {
            return nil
        }

        // Finalize the previous session after Command-V so Accessibility and
        // SwiftData work do not delay the paste.
        let previousToken = activeToken
        let previousLanguageCode = activeLanguageCode
        let languageCode = UserDefaults.standard.string(forKey: "SelectedLanguage")
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
        activeLanguageCode = nil

        guard lifecycleGeneration == generation, AutoLearnSettings.isEnabled else { return nil }

        deadlineTask = Task { [weak self] in
            if let previousToken {
                // `finishSnapshot` drops the session, so the pending capture is
                // cancelled before a new one can be started.
                await self?.persistFinishedSession(token: previousToken, languageCode: previousLanguageCode)
            }
            await self?.beginObservation(
                text: text,
                processID: processID,
                languageCode: languageCode,
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
        lifecycleGeneration &+= 1
        await cancelReviewTask()
        await discardActiveSession()
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
        languageCode: String?,
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
        activeLanguageCode = languageCode
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
        activeLanguageCode = nil
        if let token {
            await accessibilityRuntime.discard(token: token)
        } else {
            await accessibilityRuntime.discard()
        }
    }

    private func completeSession(token: AutoLearnPasteToken, persist: Bool) async {
        guard activeToken == token, activeGeneration != nil else { return }
        let languageCode = activeLanguageCode
        deadlineTask?.cancel()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil
        activeLanguageCode = nil
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()

        if persist {
            await persistFinishedSession(token: token, languageCode: languageCode)
        } else {
            await accessibilityRuntime.discard(token: token)
        }
    }

    private func persistFinishedSession(token: AutoLearnPasteToken, languageCode: String?) async {
        let cancellationGeneration = snapshotCancellationGeneration
        let snapshot = await accessibilityRuntime.finishSnapshot(token: token)
        guard snapshotCancellationGeneration == cancellationGeneration else { return }
        await persistSnapshot(snapshot, languageCode: languageCode)
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

    private func persistSnapshot(_ snapshot: AutoLearnFieldSnapshot?, languageCode: String?) async {
        guard AutoLearnSettings.isEnabled,
            let snapshot
        else { return }

        guard let revision = FinalSnapshotDiffEngine.revision(from: snapshot) else { return }
        let candidates = CorrectionDiffEngine.candidates(from: revision).map { candidate in
            var candidate = candidate
            candidate.languageCode = languageCode
            return candidate
        }
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
        guard reviewTask == nil,
            AutoLearnSettings.isEnabled,
            replacementStore != nil
        else {
            return
        }

        // A provider that is still starting up is not a failure. Leave the
        // candidates queued; the next paste, setting change, or retry arms it.
        guard await reviewIsAvailable() else {
            logger.notice("Auto Learn review deferred: no provider available")
            return
        }

        let pendingCandidateCount = (try? await pendingQueue.pendingCount()) ?? 0
        guard pendingCandidateCount > 0 else {
            return
        }

        let schedule = AutoLearnSettings.reviewSchedule
        guard schedule != .manually else {
            logger.notice(
                "Auto Learn review waiting schedule=manually pending=\(pendingCandidateCount, privacy: .public)"
            )
            return
        }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        logger.notice(
            "Auto Learn review started schedule=\(schedule.rawValue, privacy: .public) pending=\(pendingCandidateCount, privacy: .public)"
        )
        reviewTask = Task { [weak self] in
            await self?.processPendingReviewBatch(generation: generation)
        }
    }

    private func processPendingReviewBatch(
        generation: UInt64,
        stagesForApproval: Bool = false
    ) async {
        guard !Task.isCancelled,
            reviewGeneration == generation,
            AutoLearnSettings.isEnabled
        else {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            return
        }

        guard let replacementStore else {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            return
        }

        let candidates: [AutoLearnReviewCandidate]
        do {
            candidates = try await pendingQueue.claimPending(
                limit: AutoLearnLimits.maximumReviewBatchCandidates
            )
        } catch {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            log(error, message: "Failed to load queued Auto Learn candidates")
            return
        }

        guard !candidates.isEmpty else {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            await notifyQueueChanged()
            return
        }

        let candidateIDs = Set(candidates.map(\.candidateID))
        claimedCandidateIDs.formUnion(candidateIDs)
        let batchID = UUID()
        let usesAIReview = AutoLearnSettings.isAIReviewEnabled
        let mode = stagesForApproval ? "manualApproval" : "automatic"
        logger.notice("Auto Learn batch claimed batchID=\(batchID.uuidString, privacy: .public) mode=\(mode, privacy: .public) candidates=\(candidates.count, privacy: .public)")
        let reviewResult: AutoLearnReviewResult
        do {
            try Task.checkCancellation()
            guard reviewGeneration == generation else { throw CancellationError() }
            if usesAIReview, let reviewer {
                reviewResult = try await reviewer.review(candidates, batchID: batchID)
            } else if !usesAIReview {
                let knownTerms = try await replacementStore.knownTerms()
                let localReviewer = await AutoLearnLocalReviewer()
                reviewResult = try await localReviewer.review(candidates, knownTerms: knownTerms, batchID: batchID)
            } else {
                try await releaseAllClaimsToQueue()
                await finishReviewTask(generation: generation)
                return
            }
            let replacementAndVocabularyCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .addReplacementAndVocabulary
            }.count
            let vocabularyOnlyCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .addVocabularyOnly
            }.count
            let replacementOnlyCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .addReplacementOnly
            }.count
            let rejectedCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .rejectCorrection
            }.count
            logger.notice(
                "Auto Learn review evaluated batchID=\(batchID.uuidString, privacy: .public) usesAIReview=\(usesAIReview, privacy: .public) replacementAndVocabulary=\(replacementAndVocabularyCount, privacy: .public) replacementOnly=\(replacementOnlyCount, privacy: .public) vocabularyOnly=\(vocabularyOnlyCount, privacy: .public) rejected=\(rejectedCount, privacy: .public) unresolved=\(reviewResult.unresolvedReviews.count, privacy: .public) needsApproval=\(reviewResult.approvalDecisions.count, privacy: .public)"
            )
        } catch {
            try? await releaseAllClaimsToQueue()
            if !Task.isCancelled, !(error is CancellationError), reviewGeneration == generation,
                AutoLearnSettings.isAIReviewEnabled == usesAIReview {
                AutoLearnSettings.recordFailure(error, isAIReviewFailure: usesAIReview)
            }
            await finishReviewTask(generation: generation)
            log(error, message: "Auto Learn review failed batchID=\(batchID.uuidString) mode=\(mode) queueDisposition=retained cancelled=\(Task.isCancelled)")
            return
        }

        guard !Task.isCancelled, reviewGeneration == generation,
            AutoLearnSettings.isEnabled, AutoLearnSettings.isAIReviewEnabled == usesAIReview else {
            try? await releaseAllClaimsToQueue()
            logger.notice("Auto Learn batch cancelled batchID=\(batchID.uuidString, privacy: .public) mode=\(mode, privacy: .public) queueDisposition=retained")
            await finishReviewTask(generation: generation)
            return
        }

        do {
            if stagesForApproval {
                try await reviewProposalStore.append(
                    decisions: reviewResult.reviewDecisions + reviewResult.approvalDecisions,
                    candidates: candidates
                )
                try await pendingQueue.remove(candidateIDs)
                releaseClaim(candidateIDs)
                logBatchRemoval(batchID: batchID, mode: mode, candidates: candidates.count, result: reviewResult)
                await notifyQueueChanged()
                await notifyReviewProposalsChanged()
                AutoLearnSettings.clearFailure()

                if try await pendingQueue.pendingCount() > 0 {
                    await processPendingReviewBatch(
                        generation: generation,
                        stagesForApproval: true
                    )
                    return
                }

                try await releaseAllClaimsToQueue()
                await notifyQueueChanged()
                await finishReviewTask(generation: generation)
                return
            }

            // Persist uncertain local names for explicit review even when the
            // schedule is Immediate. They must never silently become rules.
            if !reviewResult.approvalDecisions.isEmpty {
                try await reviewProposalStore.append(decisions: reviewResult.approvalDecisions, candidates: candidates)
                await notifyReviewProposalsChanged()
            }
            guard !Task.isCancelled, reviewGeneration == generation,
                AutoLearnSettings.isAIReviewEnabled == usesAIReview else {
                try await releaseAllClaimsToQueue()
                await finishReviewTask(generation: generation)
                return
            }
            let summary = try await replacementStore.apply(
                reviewResult.reviewDecisions,
                candidates: candidates
            )
            try await pendingQueue.remove(candidateIDs)
            releaseClaim(candidateIDs)
            logBatchRemoval(batchID: batchID, mode: mode, candidates: candidates.count, result: reviewResult)
            await notifyQueueChanged()
            // Cleared only after the queue and dictionary are consistent, so a
            // failure in this block still surfaces to the user.
            AutoLearnSettings.clearFailure()
            if summary.hasChanges {
                logger.notice(
                    "Auto Learn apply completed batchID=\(batchID.uuidString, privacy: .public) replacementsCreated=\(summary.createdCount, privacy: .public) replacementsUpdated=\(summary.updatedCount, privacy: .public) vocabularyCreated=\(summary.vocabularyCount, privacy: .public)"
                )
                await MainActor.run {
                    NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
                }
                await showLearnedNotification(for: summary)
            } else {
                logger.notice("Auto Learn apply completed batchID=\(batchID.uuidString, privacy: .public) dictionaryChanges=0")
            }

            if try await pendingQueue.pendingCount() > 0 {
                // The schedule controls when a review run starts. Once started,
                // drain the backlog sequentially in bounded batches.
                await processPendingReviewBatch(generation: generation)
                return
            }

            try await releaseAllClaimsToQueue()
            await notifyQueueChanged()
            await finishReviewTask(generation: generation)
        } catch {
            try? await releaseAllClaimsToQueue()
            if !Task.isCancelled, !(error is CancellationError), reviewGeneration == generation {
                AutoLearnSettings.recordFailure(error)
            }
            await finishReviewTask(generation: generation)
            log(error, message: "Auto Learn commit failed batchID=\(batchID.uuidString) mode=\(mode) queueDisposition=retained")
        }
    }

    private func logBatchRemoval(batchID: UUID, mode: String, candidates: Int, result: AutoLearnReviewResult) {
        logger.notice("Auto Learn batch removed batchID=\(batchID.uuidString, privacy: .public) mode=\(mode, privacy: .public) queueDisposition=removed candidates=\(candidates, privacy: .public) decisions=\(result.reviewDecisions.count, privacy: .public) unresolvedRemoved=\(result.unresolvedReviews.count, privacy: .public)")
        if !result.unresolvedReviews.isEmpty {
            logger.warning("Auto Learn unresolved candidates removed batchID=\(batchID.uuidString, privacy: .public) count=\(result.unresolvedReviews.count, privacy: .public)")
        }
    }

    /// Forgets the in-flight batch; cancellation consumes its claim before a
    /// replacement batch can populate the set.
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

    /// Cancels the active batch and returns its claims so rapid disable/re-enable
    /// cannot strand them. Releasing is idempotent.
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

    private func notifyReviewProposalsChanged() async {
        let proposals = try? await reviewProposalStore.all()
        let count = proposals?.count ?? 0
        await MainActor.run {
            NotificationCenter.default.post(
                name: .autoLearnReviewProposalsDidChange,
                object: count
            )
        }
    }

    private func showLearnedNotification(for summary: AutoLearnMutationSummary) async {
        let corrections = summary.learnedCorrections
        guard !corrections.isEmpty else { return }

        if corrections.count == 1, let correction = corrections.first {
            let notificationTitle: String
            if correction.vocabularyCreationDate != nil {
                notificationTitle = String(
                    localized: "Added “\(correction.correctedVocabularyTerm)” to Dictionary"
                )
            } else {
                notificationTitle = String(
                    localized: "Learned “\(correction.incorrectTextToReplace)” → “\(correction.correctedVocabularyTerm)”"
                )
            }
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: notificationTitle,
                    type: .success,
                    duration: 4,
                    actionButton: (
                        label: String(localized: "Undo"),
                        action: {
                            Task {
                                await AutoLearnService.shared.undo(correction)
                            }
                        }
                    )
                )
            }
        } else {
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Learned \(corrections.count) corrections"),
                    type: .success
                )
            }
        }
    }

    private func undo(_ correction: AutoLearnAppliedCorrection) async {
        guard let replacementStore else { return }
        do {
            try await replacementStore.undo(correction)
            await MainActor.run {
                NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
            }
        } catch {
            log(error, message: "Failed to undo Auto Learn correction")
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
