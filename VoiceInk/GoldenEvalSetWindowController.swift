import AppKit
import SwiftData
import SwiftUI

class GoldenEvalSetWindowController: NSObject, NSWindowDelegate {
    static let shared = GoldenEvalSetWindowController()

    private var window: NSWindow?
    private let windowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.goldenEvalSetWindow")
    private let windowAutosaveName = NSWindow.FrameAutosaveName("VoiceInkGoldenEvalSetWindowFrame")

    private override init() {
        super.init()
    }

    func showWindow(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        AppPresentationPolicy.activateForUserFacingWindow(reason: "GoldenEvalSetWindow")

        if let existingWindow = window {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = createWindow(modelContainer: modelContainer, engine: engine)
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createWindow(modelContainer: ModelContainer, engine: VoiceInkEngine) -> NSWindow {
        let view = GoldenEvalSetView()
            .modelContainer(modelContainer)
            .environmentObject(engine)
            .frame(minWidth: 900, minHeight: 600)

        let hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.contentViewController = hostingController
        newWindow.title = String(localized: "Golden Eval Set")
        newWindow.identifier = windowIdentifier
        newWindow.delegate = self
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .visible
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.fullScreenPrimary]
        newWindow.minSize = NSSize(width: 900, height: 600)

        newWindow.setFrameAutosaveName(windowAutosaveName)
        if !newWindow.setFrameUsingName(windowAutosaveName) {
            newWindow.center()
        }

        return newWindow
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
            closedWindow.identifier == windowIdentifier
        else { return }

        window = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let keyWindow = notification.object as? NSWindow,
            keyWindow.identifier == windowIdentifier
        else { return }
        AppPresentationPolicy.activateForUserFacingWindow(reason: "GoldenEvalSetWindowDidBecomeKey")
    }
}
