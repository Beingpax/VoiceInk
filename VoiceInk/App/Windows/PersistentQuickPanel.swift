import AppKit

@MainActor
final class PersistentQuickPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onDismissRequest: (() -> Void)?

    private let positionDefaultsKey: String

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(
        size: NSSize,
        positionDefaultsKey: String,
        defaultVerticalOffset: CGFloat = 48
    ) {
        self.positionDefaultsKey = positionDefaultsKey

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        restorePosition(orCenterWithVerticalOffset: defaultVerticalOffset)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        if event.keyCode == 53 {
            performEscapeAction()
            return
        }

        if onKeyDown?(event) == true {
            return
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }

        performEscapeAction()
    }

    private func performEscapeAction() {
        if let onEscape {
            onEscape()
        } else {
            onDismissRequest?()
        }
    }

    override func resignKey() {
        super.resignKey()

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isKeyWindow else { return }
            guard !self.isHostingFocusedAuxiliaryWindow else { return }
            self.onDismissRequest?()
        }
    }

    func persistPosition() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: positionDefaultsKey)
    }

    func resizeKeepingTopEdge(to size: NSSize) {
        let currentFrame = frame
        let origin = NSPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.maxY - size.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    @objc private func panelDidMove() {
        persistPosition()
    }

    private var isHostingFocusedAuxiliaryWindow: Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }

        return keyWindow.parent == self
            || childWindows?.contains(keyWindow) == true
            || keyWindow.sheetParent == self
            || attachedSheet == keyWindow
    }

    private func restorePosition(orCenterWithVerticalOffset verticalOffset: CGFloat) {
        if let storedOrigin = UserDefaults.standard.string(forKey: positionDefaultsKey) {
            let origin = NSPointFromString(storedOrigin)
            let proposedFrame = NSRect(origin: origin, size: frame.size)

            if NSScreen.screens.contains(where: { screen in
                let visibleIntersection = screen.visibleFrame.intersection(proposedFrame)
                return visibleIntersection.width >= 120 && visibleIntersection.height >= 80
            }) {
                setFrameOrigin(origin)
                return
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            center()
            return
        }

        setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2 + verticalOffset
            )
        )
    }
}
