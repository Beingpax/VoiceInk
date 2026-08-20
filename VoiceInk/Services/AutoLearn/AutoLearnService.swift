import Foundation
import OSLog
import SwiftData

actor AutoLearnService {
    static let shared = AutoLearnService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearn")
    private let accessibilityRuntime = AutoLearnAXRuntime()
    private let focusObserver = AutoLearnFocusObserver()

    private var replacementStore: WordReplacementStore?
    private var lifecycleGeneration: UInt64 = 0
    private var activeToken: AutoLearnPasteToken?
    private var activeGeneration: UInt64?
    private var activeProcessID: pid_t?
    private var deadlineTask: Task<Void, Never>?
    private var focusFinalizationTask: Task<Void, Never>?

    private init() {}

    func configure(modelContainer: ModelContainer) {
        guard replacementStore == nil else { return }
        replacementStore = WordReplacementStore(modelContainer: modelContainer)
    }

    func settingDidChange(isEnabled: Bool) async {
        guard !isEnabled else { return }
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func recordingDidStart() async {
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func prepareForPaste(text: String, processID: pid_t) async -> AutoLearnPasteToken? {
        // A new VoiceInk paste owns the next session. Never infer corrections from
        // the abandoned previous session.
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        await discardActiveSession()

        guard lifecycleGeneration == generation,
            AutoLearnSettings.isEnabled,
            replacementStore != nil
        else {
            return nil
        }

        let token = await accessibilityRuntime.prepare(text: text, processID: processID)
        guard lifecycleGeneration == generation, AutoLearnSettings.isEnabled else {
            if let token {
                await accessibilityRuntime.discard(token: token)
            }
            return nil
        }

        activeToken = token
        activeGeneration = token == nil ? nil : generation
        activeProcessID = token == nil ? nil : processID
        return token
    }

    func pasteDidFinish(token: AutoLearnPasteToken?, commandPosted: Bool) async {
        guard let token, activeToken == token else { return }

        guard commandPosted, AutoLearnSettings.isEnabled else {
            await discardSession(token: token)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.waitForFinalSnapshot(token: token)
        }
        deadlineTask = task
    }

    func cancelForAutoSend() async {
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func shutdown() async {
        lifecycleGeneration &+= 1
        await discardActiveSession()
    }

    func focusMayHaveChanged(token: AutoLearnPasteToken) {
        guard activeToken == token else { return }
        focusFinalizationTask?.cancel()
        focusFinalizationTask = Task { [weak self] in
            await self?.finalizeIfFocusLeft(token: token)
        }
    }

    private func waitForFinalSnapshot(token: AutoLearnPasteToken) async {
        guard await sleep(nanoseconds: AutoLearnLimits.verificationDelayNanoseconds),
            !Task.isCancelled,
            activeToken == token,
            AutoLearnSettings.isEnabled,
            await accessibilityRuntime.verifyPaste(token: token)
        else {
            await discardSession(token: token)
            return
        }

        guard let processID = activeProcessID else {
            await discardSession(token: token)
            return
        }
        focusObserver.start(processID: processID, token: token) { token in
            Task {
                await AutoLearnService.shared.focusMayHaveChanged(token: token)
            }
        }

        guard await sleep(nanoseconds: AutoLearnLimits.observationDurationNanoseconds),
            !Task.isCancelled,
            activeToken == token,
            AutoLearnSettings.isEnabled
        else {
            await discardSession(token: token)
            return
        }

        await completeSession(token: token, persist: true)
    }

    private func discardActiveSession() async {
        guard let token = activeToken else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        focusFinalizationTask?.cancel()
        focusFinalizationTask = nil
        focusObserver.stop()
        activeToken = nil
        activeGeneration = nil
        activeProcessID = nil
        await accessibilityRuntime.discard(token: token)
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
            let summary = try await replacementStore.apply(candidates)
            guard summary.hasChanges else { return }

            logger.notice(
                "Saved learned replacements created=\(summary.createdCount, privacy: .public) updated=\(summary.updatedCount, privacy: .public) moved=\(summary.movedCount, privacy: .public)"
            )
            await MainActor.run {
                NotificationCenter.default.post(name: .wordReplacementsDidChange, object: nil)
            }
        } catch {
            let nsError = error as NSError
            logger.error(
                "Failed to save learned replacements domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
        }
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
