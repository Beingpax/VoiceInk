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
        self.ignoresMouseEvents = false
        self.isMovable = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        let screen = ActiveScreenResolver.currentActiveScreen()

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

        // Add visual effect view as background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .dark
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.95).cgColor

        // Create a mask layer for the notched shape
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        let bounds = view.bounds
        let cornerRadius: CGFloat = 10

        // Create the notched path
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: bounds.maxX - cornerRadius, y: bounds.maxY),
                         control: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX + cornerRadius, y: bounds.maxY))
        path.addQuadCurve(to: CGPoint(x: bounds.minX, y: bounds.maxY - cornerRadius),
                         control: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.closeSubpath()

        maskLayer.path = path
        visualEffect.layer?.mask = maskLayer

        view.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
