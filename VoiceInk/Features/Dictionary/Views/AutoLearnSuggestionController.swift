import AppKit
import SwiftUI

@MainActor
private final class AutoLearnSuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AutoLearnSuggestionController: ObservableObject {
    static let shared = AutoLearnSuggestionController()
    static let dismissalSeconds = 10

    @Published private(set) var proposals: [AutoLearnReviewProposal] = []
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var secondsRemaining = AutoLearnSuggestionController.dismissalSeconds
    @Published private(set) var dismissalDeadline: ContinuousClock.Instant?
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func update(_ proposals: [AutoLearnReviewProposal]) {
        let previousID = self.proposals.first?.id
        self.proposals = proposals
        guard let proposal = proposals.first else {
            dismissTask?.cancel()
            dismissalDeadline = nil
            panel?.close()
            panel = nil
            return
        }
        if proposal.id != previousID {
            errorMessage = nil
            secondsRemaining = Self.dismissalSeconds
            scheduleDismissal()
        }
        if panel == nil {
            present()
        }
        resizePanel()
    }

    func resolve(approve: Bool) {
        guard !isApplying, let proposal = proposals.first else { return }
        guard !approve || isValidSuggestion else { return }
        isApplying = true
        errorMessage = nil
        Task {
            do {
                if approve {
                    _ = try await AutoLearnService.shared.applyReviewProposal(proposal.id)
                } else {
                    try await AutoLearnService.shared.dismissReviewProposals([proposal.id])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
            resizePanel()
            if errorMessage == nil, secondsRemaining == 0 {
                resolve(approve: false)
            }
        }
    }

    var isValidSuggestion: Bool {
        guard let proposal = proposals.first, proposal.learningAction == .addReplacementOnly else { return false }
        return AutoLearnLocalReviewPolicy.accepts(
            source: proposal.addsReplacement ? proposal.incorrectTextToReplace ?? "" : nil,
            destination: proposal.correctedVocabularyTerm ?? "")
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard let proposalID = proposals.first?.id else { return }
        secondsRemaining = Self.dismissalSeconds
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(Self.dismissalSeconds))
        dismissalDeadline = deadline
        dismissTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: min(deadline, clock.now.advanced(by: .seconds(1))))
                } catch { return }
                guard let self, !Task.isCancelled, self.proposals.first?.id == proposalID else { return }
                let remaining = clock.now.duration(to: deadline).components
                self.secondsRemaining = max(0, Int(remaining.seconds) + (remaining.attoseconds > 0 ? 1 : 0))
                if self.secondsRemaining == 0 {
                    if self.errorMessage == nil { self.resolve(approve: false) }
                    return
                }
            }
        }
    }

    private func resizePanel() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let view = panel.contentView else { return }
            view.layoutSubtreeIfNeeded()
            panel.setContentSize(view.fittingSize)
            if let metrics = MiniRecorderPanel.calculateWindowMetrics(size: panel.frame.size, screen: panel.screen) {
                panel.setFrameOrigin(metrics.origin)
            }
        }
    }

    private func present() {
        let view = AutoLearnSuggestionView(controller: self)
        let hostingView = NSHostingView(rootView: view)
        guard let metrics = MiniRecorderPanel.calculateWindowMetrics(size: hostingView.fittingSize) else { return }
        let panel = AutoLearnSuggestionPanel(contentRect: metrics,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.appearance = nil
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        // Offer the correction without taking keyboard focus from the editor.
        panel.orderFrontRegardless()
    }
}

private struct AutoLearnSuggestionView: View {
    @ObservedObject var controller: AutoLearnSuggestionController

    var body: some View {
        if let proposal = controller.proposals.first {
            AutoLearnSuggestionContent(
                originalText: proposal.addsReplacement ? proposal.incorrectTextToReplace : nil,
                correctedText: proposal.correctedVocabularyTerm ?? "",
                secondsRemaining: controller.secondsRemaining,
                dismissalDeadline: controller.dismissalDeadline,
                dismissalSeconds: AutoLearnSuggestionController.dismissalSeconds,
                isApplying: controller.isApplying,
                isValid: controller.isValidSuggestion,
                errorMessage: controller.errorMessage,
                onApprove: { controller.resolve(approve: true) },
                onDismiss: { controller.resolve(approve: false) }
            )
        }
    }
}
