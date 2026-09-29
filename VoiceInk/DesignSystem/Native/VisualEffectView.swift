import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        if visualEffectView.material != material {
            visualEffectView.material = material
        }
        if visualEffectView.blendingMode != blendingMode {
            visualEffectView.blendingMode = blendingMode
        }
        if visualEffectView.state != .active {
            visualEffectView.state = .active
        }
    }
}
