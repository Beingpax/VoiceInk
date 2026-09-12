import Foundation
import OSLog
import SwiftData

actor AutoLearnService {
    static let shared = AutoLearnService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearn")
    private let accessibilityRuntime = AutoLearnAXRuntime()
    private let focusObserver = AutoLearnFocusObserver()
    private let pendingQueue = AutoLearnPendingQueue()

    private var replacementStore: WordReplacementStore?
    private var reviewer: AutoLearnAIReviewer?
    private var lifecycleGeneration: UInt64 = 0
    private var snapshotCancellationGeneration: UInt64 = 0
    private var activeToken: AutoLearnPasteToken?
    private var activeGeneration: UInt64?
    private var activeProcessID: pid_t?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration: UInt64 = 0
    private var reviewIsWaiting = false
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
        await cancelReviewTask(clearScheduledDate: true)
        if isEnabled {
            await schedulePendingReview()
            return
        }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func reviewScheduleDidChange() async {
        await cancelReviewTask(clearScheduledDate: true)
        guard AutoLearnSettings.isEnabled else { return }
        await schedulePendingReview()
    }

    func reviewPendingNow() async {
        guard AutoLearnSettings.isEnabled else { return }
        guard reviewTask == nil || reviewIsWaiting else { return }
        await cancelReviewTask(clearScheduledDate: true)
        await schedulePendingReview(runImmediately: true)
    }

    func retryPendingReviews() async {
        await reviewPendingNow()
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

    func pasteWillStart() async {
        guard AutoLearnSettings.isEnabled, let token = activeToken else { return }
        await completeSession(token: token, persist: true)
    }

    func pasteDidFinish(text: String, processID: pid_t?, commandPosted: Bool) async {
        guard AutoLearnSettings.isEnabled,
            replacementStore != nil,
            commandPosted,
            let processID
        else {
            return
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

        guard lifecycleGeneration == generation, AutoLearnSettings.isEnabled else { return }

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
    }

    func cancelForAutoSend() async {
        guard AutoLearnSettings.isEnabled else { return }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func shutdown() async {
        lifecycleGeneration &+= 1
        await cancelReviewTask(clearScheduledDate: false)
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
        generation: UInt64
    ) async {
        guard await sleep(nanoseconds: AutoLearnLimits.verificationDelayNanoseconds),
            !Task.isCancelled,
            lifecycleGeneration == generation,
            AutoLearnSettings.isEnabled,
            let token = await accessibilityRuntime.capturePastedText(
                text: text,
                processID: processID
            )
        else {
            return
        }

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
            let snapshot,
            let replacementStore
        else {
            return
        }

        guard let revision = FinalSnapshotDiffEngine.revision(from: snapshot) else { return }
        let candidates = CorrectionDiffEngine.candidates(from: revision)
        guard !candidates.isEmpty else { return }

        do {
            let reviewCandidates = try await replacementStore.excludingExistingSources(
                from: candidates
            )
            let insertedCount = try await pendingQueue.enqueue(reviewCandidates)
            if insertedCount > 0 {
                logger.notice(
                    "Queued \(insertedCount, privacy: .public) Auto Learn candidate(s) for AI review"
                )
                await schedulePendingReview()
            }
            await notifyQueueChanged()
        } catch {
            log(error, message: "Failed to queue Auto Learn candidates")
        }
    }

    private func schedulePendingReview(runImmediately: Bool = false) async {
        guard reviewTask == nil,
            AutoLearnSettings.isEnabled,
            replacementStore != nil,
            reviewer != nil
        else {
            return
        }

        // A provider that is still starting up is not a failure. Leave the
        // candidates queued; the next paste, setting change, or retry arms it.
        guard await reviewer?.hasAvailableProvider == true else {
            logger.notice("Auto Learn review deferred: no provider available")
            return
        }

        let pendingCandidateCount = (try? await pendingQueue.pendingCount()) ?? 0
        guard pendingCandidateCount > 0 else {
            AutoLearnSettings.setNextReviewDate(nil)
            return
        }

        let schedule = AutoLearnSettings.reviewSchedule
        guard runImmediately || schedule != .manually else {
            AutoLearnSettings.setNextReviewDate(nil)
            logger.notice(
                "Auto Learn review waiting schedule=manually pending=\(pendingCandidateCount, privacy: .public)"
            )
            return
        }

        let delay: TimeInterval
        if runImmediately || schedule == .immediately {
            AutoLearnSettings.setNextReviewDate(nil)
            delay = 0
        } else if let scheduledDate = AutoLearnSettings.nextReviewDate {
            delay = max(0, scheduledDate.timeIntervalSinceNow)
        } else if let scheduleDelay = schedule.delay {
            let scheduledDate = Date().addingTimeInterval(scheduleDelay)
            AutoLearnSettings.setNextReviewDate(scheduledDate)
            delay = scheduleDelay
        } else {
            return
        }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        reviewIsWaiting = delay > 0
        logger.notice(
            "Auto Learn review scheduled schedule=\(schedule.rawValue, privacy: .public) pending=\(pendingCandidateCount, privacy: .public) delaySeconds=\(Int(delay), privacy: .public)"
        )
        reviewTask = Task { [weak self] in
            await self?.runScheduledReview(after: delay, generation: generation)
        }
    }

    private func runScheduledReview(after delay: TimeInterval, generation: UInt64) async {
        if delay > 0 {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            guard await sleep(nanoseconds: nanoseconds), !Task.isCancelled else { return }
        }
        guard reviewGeneration == generation else { return }
        reviewIsWaiting = false
        await processPendingReviewBatch(generation: generation)
    }

    private func processPendingReviewBatch(generation: UInt64) async {
        guard !Task.isCancelled,
            reviewGeneration == generation,
            AutoLearnSettings.isEnabled
        else {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            return
        }

        guard let replacementStore, let reviewer else {
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
            AutoLearnSettings.setNextReviewDate(nil)
            await finishReviewTask(generation: generation)
            await notifyQueueChanged()
            return
        }

        let candidateIDs = Set(candidates.map(\.candidateID))
        claimedCandidateIDs.formUnion(candidateIDs)
        let reviewResult: AutoLearnReviewResult
        do {
            reviewResult = try await reviewer.review(candidates)
            let decisionsByCandidateID = Dictionary(
                uniqueKeysWithValues: reviewResult.reviewDecisions.map {
                    ($0.candidateID, $0)
                }
            )
            let unresolvedByCandidateID = Dictionary(
                uniqueKeysWithValues: reviewResult.unresolvedReviews.map {
                    ($0.candidateID, $0)
                }
            )
            // Candidate text is user content, so it stays private in the log.
            for candidate in candidates {
                guard let decision = decisionsByCandidateID[candidate.candidateID] else {
                    if let unresolved = unresolvedByCandidateID[candidate.candidateID] {
                        logger.notice(
                            "Auto Learn review result=unresolved reason=\(unresolved.reason.rawValue, privacy: .public) returnedAction=\(unresolved.learningAction?.rawValue ?? "none", privacy: .public) returnedReplacement=\(unresolved.incorrectTextToReplace ?? "none", privacy: .private) returnedVocabulary=\(unresolved.correctedVocabularyTerm ?? "none", privacy: .private) original=\(candidate.detectedOriginalText, privacy: .private) corrected=\(candidate.userCorrectedText, privacy: .private)"
                        )
                    }
                    continue
                }

                switch decision.learningAction {
                case .addReplacementAndVocabulary:
                    logger.notice(
                        "Auto Learn review result=accepted action=addReplacementAndVocabulary replacement=\(decision.incorrectTextToReplace ?? candidate.detectedOriginalText, privacy: .private) vocabulary=\(decision.correctedVocabularyTerm ?? candidate.userCorrectedText, privacy: .private) original=\(candidate.detectedOriginalText, privacy: .private) corrected=\(candidate.userCorrectedText, privacy: .private)"
                    )
                case .addVocabularyOnly:
                    logger.notice(
                        "Auto Learn review result=accepted action=addVocabularyOnly vocabulary=\(decision.correctedVocabularyTerm ?? candidate.userCorrectedText, privacy: .private) original=\(candidate.detectedOriginalText, privacy: .private) corrected=\(candidate.userCorrectedText, privacy: .private)"
                    )
                case .rejectCorrection:
                    logger.notice(
                        "Auto Learn review result=rejected action=rejectCorrection original=\(candidate.detectedOriginalText, privacy: .private) corrected=\(candidate.userCorrectedText, privacy: .private)"
                    )
                }
            }
            let replacementAndVocabularyCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .addReplacementAndVocabulary
            }.count
            let vocabularyOnlyCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .addVocabularyOnly
            }.count
            let rejectedCount = reviewResult.reviewDecisions.filter {
                $0.learningAction == .rejectCorrection
            }.count
            logger.notice(
                "Auto Learn review completed replacementAndVocabulary=\(replacementAndVocabularyCount, privacy: .public) vocabularyOnly=\(vocabularyOnlyCount, privacy: .public) rejected=\(rejectedCount, privacy: .public) unresolved=\(reviewResult.unresolvedReviews.count, privacy: .public)"
            )
        } catch {
            try? await releaseAllClaimsToQueue()
            if !Task.isCancelled {
                AutoLearnSettings.recordFailure(error)
            }
            await finishReviewTask(
                generation: generation,
                reschedule: (AutoLearnSettings.reviewSchedule.delay ?? 0) > 0
            )
            log(error, message: "Auto Learn AI review failed; candidates remain queued")
            return
        }

        guard !Task.isCancelled, AutoLearnSettings.isEnabled else {
            try? await releaseAllClaimsToQueue()
            await finishReviewTask(generation: generation)
            return
        }

        do {
            let resolvedIDs = candidateIDs.subtracting(reviewResult.unresolvedCandidateIDs)
            let summary = try await replacementStore.apply(
                reviewResult.reviewDecisions,
                candidates: candidates
            )
            try await pendingQueue.remove(resolvedIDs)
            releaseClaim(resolvedIDs)
            await notifyQueueChanged()
            // Cleared only after the queue and dictionary are consistent, so a
            // failure in this block still surfaces to the user.
            AutoLearnSettings.clearFailure()
            if summary.hasChanges {
                logger.notice(
                    "Auto Learn apply completed replacementsCreated=\(summary.createdCount, privacy: .public) replacementsUpdated=\(summary.updatedCount, privacy: .public) vocabularyCreated=\(summary.vocabularyCount, privacy: .public)"
                )
                await MainActor.run {
                    NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
                }
                await showLearnedNotification(for: summary)
            } else {
                logger.notice("Auto Learn apply completed without dictionary changes")
            }

            if try await pendingQueue.pendingCount() > 0 {
                // The schedule controls when a review run starts. Once started,
                // drain the backlog sequentially in bounded batches.
                await processPendingReviewBatch(generation: generation)
                return
            }

            // Unresolved decisions stayed claimed while later batches drained,
            // preventing one malformed response from blocking the rest of the queue.
            let hasUnresolvedReviews = !claimedCandidateIDs.isEmpty
            try await releaseAllClaimsToQueue()
            AutoLearnSettings.setNextReviewDate(nil)
            await notifyQueueChanged()
            await finishReviewTask(
                generation: generation,
                reschedule: hasUnresolvedReviews
                    && (AutoLearnSettings.reviewSchedule.delay ?? 0) > 0
            )
        } catch {
            try? await releaseAllClaimsToQueue()
            if !Task.isCancelled {
                AutoLearnSettings.recordFailure(error)
            }
            await finishReviewTask(
                generation: generation,
                reschedule: (AutoLearnSettings.reviewSchedule.delay ?? 0) > 0
            )
            log(error, message: "Failed to apply Auto Learn results; candidates remain queued")
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

    /// Re-arms a failed timed review. Successful runs drain their backlog
    /// directly without applying the schedule between batches.
    private func finishReviewTask(generation: UInt64, reschedule: Bool = false) async {
        guard reviewGeneration == generation else { return }
        reviewTask = nil
        reviewIsWaiting = false
        if reschedule {
            AutoLearnSettings.setNextReviewDate(nil)
            await schedulePendingReview()
        }
    }

    /// Cancels the active batch and returns its claims so rapid disable/re-enable
    /// cannot strand them. Releasing is idempotent.
    private func cancelReviewTask(clearScheduledDate: Bool) async {
        reviewGeneration &+= 1
        let cancelledTask = reviewTask
        cancelledTask?.cancel()
        if let cancelledTask {
            await cancelledTask.value
        }
        reviewTask = nil
        reviewIsWaiting = false
        if clearScheduledDate {
            AutoLearnSettings.setNextReviewDate(nil)
        }

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

    private func showLearnedNotification(for summary: AutoLearnMutationSummary) async {
        let corrections = summary.learnedCorrections
        guard !corrections.isEmpty else { return }

        if corrections.count == 1, let correction = corrections.first {
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: String(
                        localized: "Added “\(correction.correctedVocabularyTerm)” to Dictionary"
                    ),
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
                    title: String(localized: "Added \(corrections.count) words to Dictionary"),
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
            "\(message, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
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
