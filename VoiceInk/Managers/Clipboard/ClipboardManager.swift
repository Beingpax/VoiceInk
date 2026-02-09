import SwiftUI
import AppKit

struct ClipboardManager {
    enum ClipboardError: Error {
        case copyFailed
        case accessDenied
    }

    static func setClipboard(_ text: String, transient: Bool = false) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            pasteboard.setString(bundleIdentifier, forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        }

        if transient {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }

        return true
    }

    static func copyToClipboard(_ text: String) -> Bool {
        return setClipboard(text, transient: false)
    }

    static func getClipboardContent() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}

struct ClipboardMessageModifier: ViewModifier {
    @Binding var message: String
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                            .transition(.opacity)
                            .animation(.easeInOut, value: message)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding()
            )
    }
}

extension View {
    func clipboardMessage(_ message: Binding<String>) -> some View {
        self.modifier(ClipboardMessageModifier(message: message))
    }
}
