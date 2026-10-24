import ApplicationServices
import Foundation

/// Shared focus metadata queries. Does not enable web accessibility or read text.
enum AccessibilityFocusReader {
    struct ElementRead {
        let element: AXUIElement?
        let error: AXError
    }

    static func focusedElement(in root: AXUIElement) -> ElementRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return ElementRead(element: nil, error: error)
        }
        return ElementRead(element: unsafeBitCast(value, to: AXUIElement.self), error: error)
    }

    /// Nil means editability is unknown, including generic web containers.
    static func editableState(of element: AXUIElement, role: String? = nil) -> Bool? {
        if let editable = boolAttribute("AXEditable" as CFString, from: element) { return editable }
        let role = role ?? stringAttribute(kAXRoleAttribute as CFString, from: element)
        if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole { return true }
        return nil
    }

    static func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return processID
    }

    static func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
