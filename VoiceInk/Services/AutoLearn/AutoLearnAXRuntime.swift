import ApplicationServices
import Foundation

final class AutoLearnAXRuntime: @unchecked Sendable {
    private struct Session {
        let token: AutoLearnPasteToken
        let appElement: AXUIElement
        let targetElement: AXUIElement
        let textBeforePaste: String
        let selectionBeforePaste: NSRange
        let pastedText: String

        var baselineFieldText: String?
        var pastedRange: NSRange?
    }

    private let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.auto-learn.accessibility")
    private var session: Session?

    func prepare(text: String, processID: pid_t) async -> AutoLearnPasteToken? {
        await perform { [self] in
            session = nil

            guard AXIsProcessTrusted(),
                processID != ProcessInfo.processInfo.processIdentifier,
                !text.isEmpty,
                text.count <= AutoLearnLimits.maximumPastedCharacters
            else {
                return nil
            }

            let appElement = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(appElement, AutoLearnLimits.accessibilityTimeoutSeconds)

            guard let targetElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: appElement),
                !isSecureTextElement(targetElement),
                copyBoolAttribute("AXEditable", from: targetElement) != false,
                let fieldText = copyTextValue(from: targetElement),
                fieldText.utf16.count <= AutoLearnLimits.maximumFieldUTF16Length,
                let selectedRange = copyRangeAttribute(kAXSelectedTextRangeAttribute, from: targetElement),
                isValid(selectedRange, inUTF16Length: fieldText.utf16.count)
            else {
                return nil
            }

            let token = AutoLearnPasteToken(id: UUID())
            session = Session(
                token: token,
                appElement: appElement,
                targetElement: targetElement,
                textBeforePaste: fieldText,
                selectionBeforePaste: selectedRange,
                pastedText: text
            )
            return token
        }
    }

    func verifyPaste(token: AutoLearnPasteToken) async -> Bool {
        await perform { [self] in
            guard var active = session, active.token == token,
                focusedElementMatches(active.targetElement, in: active.appElement),
                let fieldText = copyTextValue(from: active.targetElement),
                fieldText.utf16.count <= AutoLearnLimits.maximumFieldUTF16Length,
                let expectedText = replacing(
                    active.selectionBeforePaste,
                    in: active.textBeforePaste,
                    with: active.pastedText
                )
            else {
                if session?.token == token {
                    session = nil
                }
                return false
            }

            guard textIsExactlyEqual(fieldText, expectedText) else {
                session = nil
                return false
            }

            active.baselineFieldText = fieldText
            active.pastedRange = NSRange(
                location: active.selectionBeforePaste.location,
                length: active.pastedText.utf16.count
            )
            session = active
            return true
        }
    }

    func finishSnapshot(token: AutoLearnPasteToken) async -> AutoLearnFieldSnapshot? {
        await perform { [self] in
            guard let active = session, active.token == token else { return nil }
            session = nil

            guard let baselineFieldText = active.baselineFieldText,
                let pastedRange = active.pastedRange,
                let finalFieldText = copyTextValue(from: active.targetElement),
                finalFieldText.utf16.count <= AutoLearnLimits.maximumFieldUTF16Length,
                !textIsExactlyEqual(finalFieldText, active.textBeforePaste)
            else {
                return nil
            }

            return AutoLearnFieldSnapshot(
                baselineFieldText: baselineFieldText,
                finalFieldText: finalFieldText,
                pastedRange: pastedRange,
                originalPastedText: active.pastedText
            )
        }
    }

    func targetIsFocused(token: AutoLearnPasteToken) async -> Bool {
        await perform { [self] in
            guard let active = session, active.token == token else { return false }
            return focusedElementMatches(active.targetElement, in: active.appElement)
        }
    }

    func discard(token: AutoLearnPasteToken? = nil) async {
        await perform { [self] in
            guard token == nil || session?.token == token else { return }
            session = nil
        }
    }

    private func textIsExactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    private func focusedElementMatches(_ targetElement: AXUIElement, in appElement: AXUIElement) -> Bool {
        if copyBoolAttribute(kAXFrontmostAttribute, from: appElement) == false
            || copyBoolAttribute(kAXFocusedAttribute, from: targetElement) == false
        {
            return false
        }

        guard let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: appElement) else {
            return false
        }
        return CFEqual(focusedElement, targetElement)
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        guard let subrole = copyStringAttribute(kAXSubroleAttribute, from: element) else { return false }
        return subrole == kAXSecureTextFieldSubrole as String
    }

    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private func copyTextValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let value
        else {
            return nil
        }

        if let text = value as? String {
            return text
        }
        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }
        return nil
    }

    private func copyRangeAttribute(_ attribute: String, from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID(),
            AXValueGetType(value as! AXValue) == .cfRange
        else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range),
            range.location != kCFNotFound,
            range.location >= 0,
            range.length >= 0
        else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    private func replacing(_ range: NSRange, in text: String, with replacement: String) -> String? {
        guard isValid(range, inUTF16Length: text.utf16.count) else { return nil }
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: range, with: replacement)
        return result as String
    }

    private func isValid(_ range: NSRange, inUTF16Length length: Int) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && range.location <= length
            && range.length <= length - range.location
    }

    private func perform<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }
}
