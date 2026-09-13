import ApplicationServices
import Foundation

struct AutoLearnAXTextReading {
    let appElement: AXUIElement
    let targetElement: AXUIElement
    let fieldText: String
    let selection: NSRange?
    let source: String
    let focusSource: String
}

struct AutoLearnAXTextValue {
    let text: String
    let source: String
}

/// Reads editable text through macOS Accessibility only. Web accessibility is
/// activated on demand; no keyboard event tap or Input Monitoring is involved.
final class AutoLearnAXTextReader {
    private struct MarkerSnapshot {
        let text: String
        let selection: NSRange
    }

    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
    private static let selectedMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
    private static let documentStartMarkerAttribute = "AXStartTextMarker" as CFString
    private static let documentEndMarkerAttribute = "AXEndTextMarker" as CFString
    private static let startMarkerForRangeAttribute = "AXStartTextMarkerForTextMarkerRange" as CFString
    private static let endMarkerForRangeAttribute = "AXEndTextMarkerForTextMarkerRange" as CFString
    private static let rangeForMarkersAttribute = "AXTextMarkerRangeForUnorderedTextMarkers" as CFString
    private static let stringForMarkerRangeAttribute = "AXStringForTextMarkerRange" as CFString

    private var manualAccessibilityLastEnabledAt: [pid_t: UInt64] = [:]
    private var manualAccessibilityUnsupportedPIDs = Set<pid_t>()

    func focusedReadings(processID: pid_t) -> [AutoLearnAXTextReading] {
        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(
            appElement,
            AutoLearnLimits.captureAccessibilityTimeoutSeconds
        )
        enableWebAccessibilityIfNeeded(processID: processID, appElement: appElement)

        var candidates: [(element: AXUIElement, source: String)] = []
        if let appFocused = copyElement(kAXFocusedUIElementAttribute as CFString, from: appElement) {
            appendUnique(appFocused, source: "application-focus", to: &candidates)
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let systemFocused = copyElement(kAXFocusedUIElementAttribute as CFString, from: systemWide),
            owningProcessID(of: systemFocused) == processID
        {
            appendUnique(systemFocused, source: "system-focus", to: &candidates)
        }

        var readings: [AutoLearnAXTextReading] = []
        for candidate in candidates {
            guard copyBool("AXEditable" as CFString, from: candidate.element) != false else { continue }

            let candidateReadings = makeReadings(
                from: candidate.element,
                appElement: appElement,
                focusSource: candidate.source
            )
            readings.append(contentsOf: candidateReadings)
        }
        return readings
    }

    func textValue(from element: AXUIElement) -> AutoLearnAXTextValue? {
        let attributes = attributeNames(of: element)
        let parameterizedAttributes = parameterizedAttributeNames(of: element)

        if parameterizedAttributes.contains(kAXStringForRangeParameterizedAttribute as String),
            attributes.contains(kAXNumberOfCharactersAttribute as String),
            let documentLength = copyInteger(kAXNumberOfCharactersAttribute as CFString, from: element),
            documentLength >= 0,
            documentLength <= AutoLearnLimits.maximumFieldUTF16Length,
            let text = copyStringForRange(
                NSRange(location: 0, length: documentLength),
                from: element
            ),
            documentLength == 0 || !text.isEmpty
        {
            return AutoLearnAXTextValue(text: text, source: "string-for-range")
        }

        guard let value = copyString(kAXValueAttribute as CFString, from: element),
            value.utf16.count <= AutoLearnLimits.maximumFieldUTF16Length
        else {
            guard let markerSnapshot = markerSnapshot(from: element) else { return nil }
            return AutoLearnAXTextValue(text: markerSnapshot.text, source: "text-markers")
        }
        return AutoLearnAXTextValue(text: value, source: "value")
    }

    private func makeReadings(
        from element: AXUIElement,
        appElement: AXUIElement,
        focusSource: String
    ) -> [AutoLearnAXTextReading] {
        var result: [AutoLearnAXTextReading] = []

        if let textValue = textValue(from: element) {
            let reportedSelection = copyRange(
                kAXSelectedTextRangeAttribute as CFString,
                from: element
            )
            let selection = reportedSelection.flatMap {
                isValid($0, inUTF16Length: textValue.text.utf16.count) ? $0 : nil
            }
            result.append(
                AutoLearnAXTextReading(
                    appElement: appElement,
                    targetElement: element,
                    fieldText: textValue.text,
                    selection: selection,
                    source: "native-\(textValue.source)",
                    focusSource: focusSource
                )
            )
        }

        if let markerReading = markerReading(
            from: element,
            appElement: appElement,
            focusSource: focusSource
        ) {
            let isDuplicate = result.contains {
                $0.selection == markerReading.selection
                    && $0.fieldText.utf16.elementsEqual(markerReading.fieldText.utf16)
            }
            if !isDuplicate {
                result.append(markerReading)
            }
        }

        return result
    }

    private func markerReading(
        from element: AXUIElement,
        appElement: AXUIElement,
        focusSource: String
    ) -> AutoLearnAXTextReading? {
        guard let snapshot = markerSnapshot(from: element) else { return nil }
        return AutoLearnAXTextReading(
            appElement: appElement,
            targetElement: element,
            fieldText: snapshot.text,
            selection: snapshot.selection,
            source: "text-markers",
            focusSource: focusSource
        )
    }

    private func markerSnapshot(from element: AXUIElement) -> MarkerSnapshot? {
        let parameterizedAttributes = parameterizedAttributeNames(of: element)
        guard parameterizedAttributes.contains(Self.startMarkerForRangeAttribute as String),
            parameterizedAttributes.contains(Self.endMarkerForRangeAttribute as String),
            parameterizedAttributes.contains(Self.rangeForMarkersAttribute as String),
            parameterizedAttributes.contains(Self.stringForMarkerRangeAttribute as String),
            let selectedRange = copyOpaque(Self.selectedMarkerRangeAttribute, from: element),
            let documentStart = copyOpaque(Self.documentStartMarkerAttribute, from: element),
            let documentEnd = copyOpaque(Self.documentEndMarkerAttribute, from: element),
            let selectionStart = copyOpaqueParameterized(
                Self.startMarkerForRangeAttribute,
                parameter: selectedRange,
                from: element
            ),
            let selectionEnd = copyOpaqueParameterized(
                Self.endMarkerForRangeAttribute,
                parameter: selectedRange,
                from: element
            ),
            let beforeRange = markerRange(from: documentStart, to: selectionStart, on: element),
            let beforeText = stringForMarkerRange(beforeRange, on: element)
        else {
            return nil
        }

        let selectedText = stringForMarkerRange(selectedRange, on: element) ?? ""
        let afterText: String
        if let afterRange = markerRange(from: selectionEnd, to: documentEnd, on: element),
            let text = stringForMarkerRange(afterRange, on: element)
        {
            afterText = text
        } else {
            afterText = ""
        }

        let fieldText = beforeText + selectedText + afterText
        guard fieldText.utf16.count <= AutoLearnLimits.maximumFieldUTF16Length else {
            return nil
        }

        return MarkerSnapshot(
            text: fieldText,
            selection: NSRange(
                location: beforeText.utf16.count,
                length: selectedText.utf16.count
            )
        )
    }

    private func enableWebAccessibilityIfNeeded(
        processID: pid_t,
        appElement: AXUIElement
    ) {
        guard !manualAccessibilityUnsupportedPIDs.contains(processID) else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if let lastEnabledAt = manualAccessibilityLastEnabledAt[processID],
            now - lastEnabledAt < 1_000_000_000
        {
            return
        }

        let result = AXUIElementSetAttributeValue(
            appElement,
            Self.manualAccessibilityAttribute,
            kCFBooleanTrue
        )
        switch result {
        case .success:
            manualAccessibilityLastEnabledAt[processID] = now
        case .attributeUnsupported, .notImplemented:
            manualAccessibilityUnsupportedPIDs.insert(processID)
        default:
            break
        }
    }

    private func appendUnique(
        _ element: AXUIElement,
        source: String,
        to candidates: inout [(element: AXUIElement, source: String)]
    ) {
        guard !candidates.contains(where: { CFEqual($0.element, element) }) else { return }
        candidates.append((element, source))
    }

    private func owningProcessID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return processID
    }

    private func attributeNames(of element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
            let values = names as? [String]
        else {
            return []
        }
        return Set(values)
    }

    private func parameterizedAttributeNames(of element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
            let values = names as? [String]
        else {
            return []
        }
        return Set(values)
    }

    private func copyElement(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyOpaque(attribute, from: element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyBool(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        (copyOpaque(attribute, from: element) as? NSNumber)?.boolValue
    }

    private func copyInteger(_ attribute: CFString, from element: AXUIElement) -> Int? {
        (copyOpaque(attribute, from: element) as? NSNumber)?.intValue
    }

    private func copyString(_ attribute: CFString, from element: AXUIElement) -> String? {
        let value = copyOpaque(attribute, from: element)
        if let text = value as? String {
            return text
        }
        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }
        return nil
    }

    private func copyRange(_ attribute: CFString, from element: AXUIElement) -> NSRange? {
        guard let value = copyOpaque(attribute, from: element),
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

    private func copyStringForRange(_ range: NSRange, from element: AXUIElement) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        guard let value = copyOpaqueParameterized(
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter: rangeValue,
            from: element
        ) else {
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

    private func markerRange(
        from start: CFTypeRef,
        to end: CFTypeRef,
        on element: AXUIElement
    ) -> CFTypeRef? {
        copyOpaqueParameterized(
            Self.rangeForMarkersAttribute,
            parameter: [start, end] as CFArray,
            from: element
        )
    }

    private func stringForMarkerRange(_ range: CFTypeRef, on element: AXUIElement) -> String? {
        let value = copyOpaqueParameterized(
            Self.stringForMarkerRangeAttribute,
            parameter: range,
            from: element
        )
        if let text = value as? String {
            return text
        }
        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }
        return nil
    }

    private func copyOpaque(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyOpaqueParameterized(
        _ attribute: CFString,
        parameter: CFTypeRef,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute,
            parameter,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func isValid(_ range: NSRange, inUTF16Length length: Int) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && range.location <= length
            && range.length <= length - range.location
    }
}
