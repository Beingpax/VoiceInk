import AppKit
import Combine
import SwiftUI

/// Apps where the ambient light is suppressed.
///
/// The light covers the whole display, which is wrong in a few specific places: a video call where
/// it frames your face, a photo or video editor where a coloured wash over the edges misrepresents
/// what you are grading, a presentation. Recording still works normally — only the light goes away.
@MainActor
enum AmbientAppExclusions {
    static let userDefaultsKey = "AmbientExcludedBundleIdentifiers"

    static var bundleIdentifiers: [String] {
        get { UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? [] }
        set {
            UserDefaults.standard.set(
                Array(Set(newValue)).sorted(), forKey: userDefaultsKey)
            NotificationCenter.default.post(name: .ambientExclusionsChanged, object: nil)
        }
    }

    static func isExcluded(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifiers.contains(bundleIdentifier)
    }

    static var isFrontmostAppExcluded: Bool {
        isExcluded(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}

extension Notification.Name {
    static let ambientExclusionsChanged = Notification.Name("ambientExclusionsChanged")
}

/// Full-screen, click-through window that hosts the ambient border.
///
/// Never takes focus and never intercepts a click — it has to sit over whatever you are working in
/// without being in the way, which is the entire point of the ambient style.
@MainActor
final class AmbientRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Ignored by default, and only switched on for the moments something here is actually
        // clickable — a result peek, the cancel button, the mode strip. The hosting view below also
        // passes through everything it does not draw, but that is a second line of defence now
        // rather than the only one: a display-sized window that accepts events is one SwiftUI
        // hit-testing surprise away from swallowing every click on the machine, and the cost of
        // being wrong is the user losing their mouse.
        ignoresMouseEvents = true
        canHide = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Excluded from screen capture. A light around the whole display would otherwise be baked
        // into every screen recording and shared screen, where it means nothing to the viewer and
        // cannot be turned off after the fact.
        sharingType = .none
    }
}

/// A full-screen hosting view that only claims the clicks it actually draws something for.
///
/// `NSHostingView` returns itself for a hit anywhere in its bounds, which for a display-sized
/// window means swallowing every click on the machine. Returning nil when SwiftUI's own hit-test
/// resolves to the host itself lets AppKit pass the event to the window below.
@MainActor
final class AmbientPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

@MainActor
final class AmbientWindowManager {
    private var panel: AmbientRecorderPanel?
    private let makeView: () -> AnyView

    private var isShowing = false
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Task<Void, Never>?

    init(engine: VoiceInkEngine, recorder: Recorder) {
        var setInteractive: (Bool) -> Void = { _ in }
        self.makeView = {
            AnyView(
                AmbientRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    onInteractiveChange: { setInteractive($0) }
                )
            )
        }
        setInteractive = { [weak self] value in self?.setInteractive(value) }
    }

    deinit {
        watchdog?.cancel()
    }

    func show() {
        isShowing = true
        if panel == nil { build() }
        startObserving()
        syncToActiveScreen()
    }

    func hide() {
        isShowing = false
        stopObserving()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    /// Called by the view when clickable content appears or leaves.
    func setInteractive(_ isInteractive: Bool) {
        panel?.ignoresMouseEvents = !isInteractive
    }

    /// Tears the window down without yanking SwiftUI's floor out from under it.
    ///
    /// Releasing the panel synchronously crashes: `GraphHost` can already have an async transaction
    /// queued, and when it lands it calls `NSHostingView.setNeedsUpdate` →
    /// `setNeedsUpdateConstraints` → `_postWindowNeedsUpdateConstraints`, which throws on a window
    /// that is going away. It is a pre-existing race — it is in crash reports from before any of
    /// this — but destroying the panel on a style change made it easy to hit rather than rare.
    ///
    /// So the window is ordered out now and released on the next turn of the run loop, with its
    /// SwiftUI content detached first. Anything already queued drains against a window that is
    /// still valid.
    func destroyWindow() {
        isShowing = false
        stopObserving()

        guard let doomed = panel else { return }
        panel = nil

        doomed.ignoresMouseEvents = true
        doomed.orderOut(nil)

        DispatchQueue.main.async {
            doomed.contentView = NSView(frame: .zero)
        }
    }

    // MARK: - Staying on the right screen
    //
    // This window is the only one in the app sized to an entire display, and it was positioned
    // exactly once — at show(). Anything that moved the active screen out from under it left the
    // light stranded: it was still drawing, on a display the user was no longer looking at, or at a
    // size the display no longer had. From the front that looks like the UI vanishing mid-take
    // while recording carries on, because that is precisely what happened.
    //
    // Four things cause it, and they need different signals, so the safety net is deliberately
    // wide: display connected or disconnected, resolution or scaling changed, focus moved to
    // another display, and the space changing to or from a full-screen app.

    /// Puts the panel on whatever screen is active now, and re-asserts its stacking.
    ///
    /// Cheap enough to call on a timer: when nothing has moved it compares two rects and returns.
    private func syncToActiveScreen() {
        guard isShowing, let panel else { return }

        guard !AmbientAppExclusions.isFrontmostAppExcluded else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        guard let screen = NSScreen.main else { return }

        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }

        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        func observe(_ name: Notification.Name, on notificationCenter: NotificationCenter) {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.syncToActiveScreen() }
                }
            )
        }

        // Display added, removed, rearranged, or its mode changed.
        observe(NSApplication.didChangeScreenParametersNotification, on: center)
        // Moving to a full-screen app, or any other space change.
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspaceCenter)
        // Switching apps is the usual way NSScreen.main changes on a multi-display setup, and it is
        // also when an excluded app can come to the front.
        observe(NSWorkspace.didActivateApplicationNotification, on: workspaceCenter)
        observe(.ambientExclusionsChanged, on: center)

        // The notifications above cover every cause found so far, but this window failing silently
        // is worse than the cost of checking: a second is far below noticing, and the check is two
        // rect comparisons when nothing has changed.
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isShowing else { return }
                self.syncToActiveScreen()
            }
        }
    }

    private func stopObserving() {
        watchdog?.cancel()
        watchdog = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func build() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let newPanel = AmbientRecorderPanel(contentRect: screenFrame)

        let host = AmbientPassthroughHostingView(rootView: makeView())
        host.frame = NSRect(origin: .zero, size: screenFrame.size)
        host.autoresizingMask = [.width, .height]
        newPanel.contentView = host

        panel = newPanel
    }
}
