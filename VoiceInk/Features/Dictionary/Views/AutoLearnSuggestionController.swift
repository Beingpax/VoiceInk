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

    @Published private(set) var suggestions: [AutoLearnSuggestion] = []
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var secondsRemaining = AutoLearnSuggestionController.dismissalSeconds
    @Published private(set) var dismissalDeadline: ContinuousClock.Instant?
    private let presentsPanel: Bool
    private let service: AutoLearnService
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    init(presentsPanel: Bool = true, service: AutoLearnService = .shared) {
        self.presentsPanel = presentsPanel
        self.service = service
    }

    func update(_ suggestions: [AutoLearnSuggestion]) {
        let previous = self.suggestions.first
        self.suggestions = suggestions
        guard let suggestion = suggestions.first else {
            dismissTask?.cancel()
            dismissTask = nil
            dismissalDeadline = nil
            errorMessage = nil
            panel?.close()
            panel = nil
            return
        }
        if suggestion != previous {
            errorMessage = nil
            secondsRemaining = Self.dismissalSeconds
            scheduleDismissal()
        }
        if presentsPanel, panel == nil {
            present()
        }
        resizePanel()
    }

    func resolve(approve: Bool) {
        guard !isApplying, let suggestion = suggestions.first else { return }
        guard !approve || isValidSuggestion else { return }
        isApplying = true
        errorMessage = nil
        Task {
            do {
                if approve {
                    try await service.applySuggestion(suggestion)
                } else {
                    try await service.dismissSuggestion(suggestion)
                }
            } catch {
                if suggestions.first == suggestion {
                    errorMessage = error.localizedDescription
                }
            }
            isApplying = false
            resizePanel()
            if let current = suggestions.first, current != suggestion,
                errorMessage == nil, secondsRemaining == 0 {
                resolve(approve: false)
            }
        }
    }

    var isValidSuggestion: Bool {
        suggestions.first?.isValid == true
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard let suggestion = suggestions.first else { return }
        secondsRemaining = Self.dismissalSeconds
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(Self.dismissalSeconds))
        dismissalDeadline = deadline
        dismissTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: min(deadline, clock.now.advanced(by: .seconds(1))))
                } catch { return }
                guard let self, !Task.isCancelled, self.suggestions.first == suggestion else { return }
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
        guard presentsPanel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let view = panel.contentView else { return }
            view.layoutSubtreeIfNeeded()
            panel.setContentSize(view.fittingSize)
            if let metrics = MiniRecorderPanel.calculateWindowMetrics(size: panel.frame.size, screen: panel.screen)?.offsetBy(dx: 0, dy: 48) {
                panel.setFrameOrigin(metrics.origin)
            }
        }
    }

    private func present() {
        let view = AutoLearnSuggestionView(controller: self)
        let hostingView = NSHostingView(rootView: view)
        guard let metrics = MiniRecorderPanel.calculateWindowMetrics(size: hostingView.fittingSize)?.offsetBy(dx: 0, dy: 48) else { return }
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
        if let suggestion = controller.suggestions.first {
            AutoLearnSuggestionContent(
                originalText: suggestion.originals.map(\.text).joined(separator: ", "),
                correctedText: suggestion.replacementText,
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
