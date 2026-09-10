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
    private var activeToken: AutoLearnPasteToken?
    private var activeGeneration: UInt64?
    private var activeProcessID: pid_t?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration: UInt64 = 0

    private init() {}

    func configure(modelContainer: ModelContainer, reviewer: AutoLearnAIReviewer) async {
        guard replacementStore == nil else { return }
        let store = WordReplacementStore(modelContainer: modelContainer)
        replacementStore = store
        self.reviewer = reviewer
        do {
            try await pendingQueue.recoverInterruptedReviews()
            schedulePendingReview()
        } catch {
            log(error, message: "Failed to recover queued Auto Learn reviews")
        }
    }

    func settingDidChange(isEnabled: Bool) async {
        reviewGeneration &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        if isEnabled {
            schedulePendingReview()
            return
        }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func retryPendingReviews() {
        guard AutoLearnSettings.isEnabled else { return }
        schedulePendingReview()
    }

    func recordingDidStart() async {
        guard let token = activeToken else { return }
        await completeSession(token: token, persist: true)
    }

    func pasteWillStart() async {
        guard let token = activeToken else { return }
        await completeSession(token: token, persist: true)
    }

    func pasteDidFinish(text: String, processID: pid_t?, commandPosted: Bool) async {
        // A new VoiceInk paste owns the next session. Capture happens only after
        // Command-V is posted, so Accessibility work never delays the paste.
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        await discardActiveSession()

        guard lifecycleGeneration == generation,
            commandPosted,
            AutoLearnSettings.isEnabled,
            replacementStore != nil,
            let processID
        else {
            return
        }

        deadlineTask = Task { [weak self] in
            await self?.beginObservation(
                text: text,
                processID: processID,
                generation: generation
            )
        }
    }

    func cancelForAutoSend() async {
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func shutdown() async {
        lifecycleGeneration &+= 1
        reviewGeneration &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        await discardActiveSession()
    }

    func focusMayHaveChanged(token: AutoLearnPasteToken) {
        guard activeToken == token else { return }
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
        guard activeToken == token, let generation = activeGeneration else { return }
        deadlineTask?.cancel()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()

        if persist {
            let snapshot = await accessibilityRuntime.finishSnapshot(token: token)
            guard lifecycleGeneration == generation else { return }
            await persistSnapshot(snapshot)
        } else {
            await accessibilityRuntime.discard(token: token)
        }
    }

    private func discardSession(token: AutoLearnPasteToken) async {
        await completeSession(token: token, persist: false)
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
        logger.notice(
            "Auto Learn captured revision original=\(revision.original, privacy: .public) corrected=\(revision.corrected, privacy: .public)"
        )
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
                schedulePendingReview()
            }
        } catch {
            log(error, message: "Failed to queue Auto Learn candidates")
        }
    }

    private func schedulePendingReview() {
        guard reviewTask == nil,
            AutoLearnSettings.isEnabled,
            replacementStore != nil,
            reviewer != nil
        else {
            return
        }

        reviewGeneration &+= 1
        let generation = reviewGeneration
        reviewTask = Task { [weak self] in
            await self?.processPendingReviewBatch(generation: generation)
        }
    }

    private func processPendingReviewBatch(generation: UInt64) async {
        guard let replacementStore, let reviewer else {
            finishReviewTask(generation: generation)
            return
        }

        let candidates: [AutoLearnReviewCandidate]
        do {
            candidates = try await pendingQueue.claimPending()
        } catch {
            finishReviewTask(generation: generation)
            log(error, message: "Failed to load queued Auto Learn candidates")
            return
        }

        guard !candidates.isEmpty else {
            finishReviewTask(generation: generation)
            return
        }

        let candidateIDs = Set(candidates.map(\.id))
        let decisions: [AutoLearnReviewDecision]
        do {
            decisions = try await reviewer.review(candidates)
            AutoLearnSettings.clearFailure()
            let acceptedCount = decisions.reduce(0) { count, decision in
                count + (decision.accepted ? 1 : 0)
            }
            logger.notice(
                "Completed Auto Learn AI review accepted=\(acceptedCount, privacy: .public) rejected=\(decisions.count - acceptedCount, privacy: .public)"
            )
        } catch {
            try? await pendingQueue.release(candidateIDs)
            if !Task.isCancelled {
                AutoLearnSettings.recordFailure(error)
            }
            finishReviewTask(generation: generation)
            log(error, message: "Auto Learn AI review failed; candidates remain queued")
            return
        }

        guard !Task.isCancelled, AutoLearnSettings.isEnabled else {
            try? await pendingQueue.release(candidateIDs)
            finishReviewTask(generation: generation)
            return
        }

        do {
            let summary = try await replacementStore.apply(decisions, candidates: candidates)
            try await pendingQueue.remove(candidateIDs)
            if summary.hasChanges {
                logger.notice(
                    "Applied AI-reviewed Auto Learn results created=\(summary.createdCount, privacy: .public) updated=\(summary.updatedCount, privacy: .public) vocabulary=\(summary.vocabularyCount, privacy: .public)"
                )
                await MainActor.run {
                    NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
                }
                await showLearnedNotification(for: summary)
            } else {
                logger.notice("Auto Learn review completed without adding dictionary entries")
            }

            finishReviewTask(generation: generation, continueProcessing: true)
        } catch {
            try? await pendingQueue.release(candidateIDs)
            finishReviewTask(generation: generation)
            log(error, message: "Failed to apply Auto Learn results; candidates remain queued")
        }
    }

    private func finishReviewTask(generation: UInt64, continueProcessing: Bool = false) {
        guard reviewGeneration == generation else { return }
        reviewTask = nil
        if continueProcessing {
            schedulePendingReview()
        }
    }

    private func showLearnedNotification(for summary: AutoLearnMutationSummary) async {
        let corrections = summary.learnedCorrections
        guard !corrections.isEmpty else { return }

        if corrections.count == 1, let correction = corrections.first {
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: "Added “\(correction.destination)” to Dictionary",
                    type: .success,
                    duration: 4,
                    actionButton: (
                        label: "Undo",
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
                    title: "Added \(corrections.count) words to Dictionary",
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
