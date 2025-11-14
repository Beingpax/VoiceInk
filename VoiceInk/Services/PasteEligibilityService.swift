import Cocoa

class PasteEligibilityService {
    static func isPastePossible() -> Bool {
        guard AXIsProcessTrustedWithOptions(nil) else {
            return true
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, 
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID(),
              let axElement = element as? AXUIElement else {
            return false
        }

        var isWritable: DarwinBoolean = false
        let isSettableResult = AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &isWritable)

        if isSettableResult == .success && isWritable.boolValue {
            return true
        }

        return false
    }
}