import Foundation
import ApplicationServices
import os

@MainActor
final class SelectedTextService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SelectedTextService")

    static func fetchSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility is not trusted; selected text capture skipped")
            return nil
        }

        return getSelectedTextByAccessibility()
    }

    private static func getSelectedTextByAccessibility() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: systemWideElement),
              let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: focusedElement) else {
            return nil
        }

        return normalized(selectedText)
    }

    private static func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
