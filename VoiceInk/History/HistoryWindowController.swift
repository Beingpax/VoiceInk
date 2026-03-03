import SwiftUI
import SwiftData
import AppKit

class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()

    private var historyWindow: NSWindow?
    private let windowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.historyWindow")
    private let windowAutosaveName = NSWindow.FrameAutosaveName("VoiceInkHistoryWindowFrame")

    private override init() {
        super.init()
    }

    func showHistoryWindow(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        if let existingWindow = historyWindow {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = createHistoryWindow(modelContainer: modelContainer, engine: engine)
        historyWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createHistoryWindow(modelContainer: ModelContainer, engine: VoiceInkEngine) -> NSWindow {
        let historyView = TranscriptionHistoryView()
            .modelContainer(modelContainer)
            .environmentObject(engine)
            .environmentObject(engine.enhancementService!)
            .frame(minWidth: 1000, minHeight: 700)

        let hostingController = NSHostingController(rootView: historyView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "VoiceInk — Transcription History"
        window.identifier = windowIdentifier
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 1000, height: 700)

        window.setFrameAutosaveName(windowAutosaveName)
        if !window.setFrameUsingName(windowAutosaveName) {
            window.center()
        }

        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == windowIdentifier else { return }

        historyWindow = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == windowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
