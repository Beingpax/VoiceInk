import AppKit
import Combine
import Foundation
import SwiftData

// Drives the Dashboard's "help people discover VoiceInk" GitHub star card; gated on session count, not just window launch.
@MainActor
final class GitHubStarPromptCoordinator: ObservableObject {
    static let shared = GitHubStarPromptCoordinator()

    enum Mode: Equatable {
        /// `gh` is installed, authenticated, and the repo isn't starred yet — star directly via the API.
        case cli
        /// `gh` isn't available/authenticated (or a direct star attempt failed) — hand off to the browser.
        case web
    }

    enum CompletionState: Equatable {
        case none
        case starred
        case opened
    }

    @Published private(set) var isVisible = false
    @Published private(set) var isStarring = false
    @Published private(set) var mode: Mode = .web
    @Published private(set) var isResolved: Bool
    @Published private(set) var hasDeferredAtLeastOnce: Bool
    @Published private(set) var completionState: CompletionState = .none
    // Brief, non-blocking feedback when NSWorkspace fails to open the repo URL - card stays up so the user can retry.
    @Published private(set) var openFailed = false

    // Shown in the Dashboard footer only once Later has been clicked - never appears from a toast-only flow.
    var showsFooterStarButton: Bool { hasDeferredAtLeastOnce && (!isResolved || completionState != .none) }

    private static let repoURL = URL(string: "https://github.com/Beingpax/VoiceInk")!
    private static let showDelaySeconds: TimeInterval = 3
    private static let completionDisplaySeconds: TimeInterval = 1.5
    private static let minimumCompletedSessionsToPrompt = 30

    private enum Keys {
        static let hasStarred = "GitHubStarPromptHasStarred"
        static let hasDeferredOnce = "GitHubStarPromptHasDeferredOnce"
    }

    private var hasScheduled = false
    private var scheduleTask: Task<Void, Never>?
    private var modelContainer: ModelContainer?

    private init() {
        let defaults = UserDefaults.standard
        isResolved = defaults.bool(forKey: Keys.hasStarred)
        hasDeferredAtLeastOnce = defaults.bool(forKey: Keys.hasDeferredOnce)
    }

    // Call once when the main window appears; only the first call per app run schedules the timer.
    func scheduleIfNeeded(modelContainer: ModelContainer) {
        guard !hasScheduled else { return }
        hasScheduled = true
        self.modelContainer = modelContainer
        guard Self.shouldShow else { return }

        scheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.showDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.evaluateAndPresent()
        }
    }

    private func evaluateAndPresent() async {
        guard Self.shouldShow else { return }
        guard await hasReachedSessionThreshold() else { return }

        // Skip showing the card entirely if gh says the repo is already starred.
        let remoteState = await GitHubCLIStarService.checkRemoteStarState()
        guard Self.shouldShow else { return }

        switch remoteState {
        case .starred:
            UserDefaults.standard.set(true, forKey: Keys.hasStarred)
            isResolved = true
        case .notStarred:
            mode = .cli
            isVisible = true
        case .unavailable:
            mode = .web
            isVisible = true
        }
    }

    func star() {
        guard !isStarring, completionState == .none else { return }

        if mode == .web {
            // Only mark resolved if the browser actually opened - keeps the retry path alive otherwise.
            guard NSWorkspace.shared.open(Self.repoURL) else {
                presentOpenFailure()
                return
            }
            UserDefaults.standard.set(true, forKey: Keys.hasStarred)
            isResolved = true
            presentCompletion(.opened)
            return
        }

        isStarring = true
        Task { [weak self] in
            let succeeded = await GitHubCLIStarService.star()
            guard let self else { return }
            self.isStarring = false
            if succeeded {
                UserDefaults.standard.set(true, forKey: Keys.hasStarred)
                self.isResolved = true
                self.presentCompletion(.starred)
            } else {
                // Direct star failed (auth/network) - fall back to the manual web flow.
                self.mode = .web
            }
        }
    }

    // Holds the card/footer button on a "Starred! Thank you" state briefly before dismissing.
    private func presentCompletion(_ state: CompletionState) {
        completionState = state
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.completionDisplaySeconds * 1_000_000_000))
            guard let self else { return }
            self.isVisible = false
            self.completionState = .none
        }
    }

    // Flags the open failure briefly so the button doesn't look like a dead click, then clears for retry.
    private func presentOpenFailure() {
        openFailed = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.completionDisplaySeconds * 1_000_000_000))
            guard let self else { return }
            self.openFailed = false
        }
    }

    func later() {
        UserDefaults.standard.set(true, forKey: Keys.hasDeferredOnce)
        hasDeferredAtLeastOnce = true
        isVisible = false
    }

    // Once Later has been clicked, the toast retires for good; the persistent footer button takes over.
    private static var shouldShow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.hasStarred) { return false }
        if defaults.bool(forKey: Keys.hasDeferredOnce) { return false }
        return true
    }

    private func hasReachedSessionThreshold() async -> Bool {
        guard let modelContainer else { return false }
        let threshold = Self.minimumCompletedSessionsToPrompt

        return await Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(modelContainer)
            let count = (try? backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())) ?? 0
            return count >= threshold
        }.value
    }
}
