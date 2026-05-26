import SwiftUI
import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NotchRecorderPanel: KeyablePanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()

        super.init(
            contentRect: metrics.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .statusBar + 3
        self.backgroundColor = .clear
        self.isOpaque = false
        self.alphaValue = 1.0
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.appearance = NSAppearance(named: .darkAqua)
        self.styleMask.remove(.titled)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.isMovable = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        guard let screen = NSScreen.main else {
            return (NSRect(x: 0, y: 0, width: 280, height: 24), 280, 24)
        }

        let safeAreaInsets = screen.safeAreaInsets
        let notchHeight: CGFloat = safeAreaInsets.top > 0 ? safeAreaInsets.top : NSStatusBar.system.thickness

        let notchWidth: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea?.width,
               let right = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - left - right
            }
            return 180
        }()

        let maxSideExpansion: CGFloat = 110
        let sideMargin: CGFloat = 10
        let totalWidth = notchWidth + (maxSideExpansion + sideMargin) * 2

        let maxContentHeight: CGFloat = 200
        let xPosition = screen.frame.midX - (totalWidth / 2)
        let yPosition = screen.frame.maxY - maxContentHeight

        let frame = NSRect(x: xPosition, y: yPosition, width: totalWidth, height: maxContentHeight)
        return (frame, notchWidth, notchHeight)
    }

    func show() {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        setFrame(metrics.frame, display: true)
        orderFrontRegardless()
    }

    func hide(completion: @escaping () -> Void) {
        completion()
    }

    @objc private func handleScreenParametersChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let metrics = NotchRecorderPanel.calculateWindowMetrics()
            self.setFrame(metrics.frame, display: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

class NotchRecorderHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
