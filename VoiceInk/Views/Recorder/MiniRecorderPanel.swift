import SwiftUI
import AppKit

class MiniRecorderPanel: NSPanel, NSWindowDelegate {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }
    
    private func configurePanel() {
        self.delegate = self
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }
    
    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 420, height: 180)
        }

        let widthVal = UserDefaults.standard.double(forKey: "miniRecorderWidth")
        let width: CGFloat = widthVal > 0 ? CGFloat(widthVal) : 420.0
        
        let heightVal = UserDefaults.standard.double(forKey: "miniRecorderHeight")
        let height: CGFloat = heightVal > 0 ? CGFloat(heightVal) : 180.0
        
        let placement = UserDefaults.standard.string(forKey: "miniRecorderPlacement") ?? "bottom"
        let offsetX = CGFloat(UserDefaults.standard.double(forKey: "miniRecorderXOffset"))
        let offsetY = CGFloat(UserDefaults.standard.double(forKey: "miniRecorderYOffset"))

        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 24

        let xPosition: CGFloat
        let yPosition: CGFloat

        switch placement {
        case "top":
            xPosition = visibleFrame.midX - (width / 2) + offsetX
            yPosition = visibleFrame.maxY - height - padding + offsetY
        case "center":
            xPosition = visibleFrame.midX - (width / 2) + offsetX
            yPosition = visibleFrame.midY - (height / 2) + offsetY
        case "bottom":
            fallthrough
        default:
            xPosition = visibleFrame.midX - (width / 2) + offsetX
            yPosition = visibleFrame.minY + padding + offsetY
        }

        return NSRect(
            x: xPosition,
            y: yPosition,
            width: width,
            height: height
        )
    }

    func show() {
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        setFrame(metrics, display: true)
        orderFrontRegardless()
    }
    
    func hide(completion: @escaping () -> Void) {
        completion()
    }

    // MARK: - NSWindowDelegate
    
    func windowDidMove(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 24
        
        let width = self.frame.width
        let height = self.frame.height
        
        let placement = UserDefaults.standard.string(forKey: "miniRecorderPlacement") ?? "bottom"
        
        let baseX: CGFloat
        let baseY: CGFloat
        
        switch placement {
        case "top":
            baseX = visibleFrame.midX - (width / 2)
            baseY = visibleFrame.maxY - height - padding
        case "center":
            baseX = visibleFrame.midX - (width / 2)
            baseY = visibleFrame.midY - (height / 2)
        case "bottom":
            fallthrough
        default:
            baseX = visibleFrame.midX - (width / 2)
            baseY = visibleFrame.minY + padding
        }
        
        let currentX = self.frame.origin.x
        let currentY = self.frame.origin.y
        
        let offsetX = currentX - baseX
        let offsetY = currentY - baseY
        
        UserDefaults.standard.set(Double(offsetX), forKey: "miniRecorderXOffset")
        UserDefaults.standard.set(Double(offsetY), forKey: "miniRecorderYOffset")
    }
} 