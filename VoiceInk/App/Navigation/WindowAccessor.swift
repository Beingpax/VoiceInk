import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        notifyWindowIfNeeded(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        notifyWindowIfNeeded(for: nsView, context: context)
    }

    private func notifyWindowIfNeeded(for view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window,
                context.coordinator.window !== window
            {
                context.coordinator.window = window
                callback(window)
            }
        }
    }

    final class Coordinator {
        weak var window: NSWindow?
    }
}
