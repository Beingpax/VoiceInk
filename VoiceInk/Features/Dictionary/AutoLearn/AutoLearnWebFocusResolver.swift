import Foundation

/// Some WebKit editors expose the web area as focused while hiding the editable
/// descendant from AXChildren. Resolve the selection's editable ancestor instead.
struct AutoLearnWebFocusResolver<Element> {
    let isWebArea: (Element) -> Bool
    let children: (Element) -> [Element]
    let selectedEditableElement: (Element) -> Element?

    func resolve(fromFocus focusedElement: Element, parent: (Element) -> Element?) -> Element? {
        // Some editors report a proxy element as focused. Walk its ancestors to
        // the nearest web area, even when it is too deep in the window tree.
        var current: Element? = focusedElement
        for _ in 0..<8 {
            guard let element = current else { return nil }
            if isWebArea(element) { return selectedEditableElement(element) }
            current = parent(element)
        }
        return nil
    }

    func resolve(in root: Element) -> Element? {
        var queue: [(Element, Int)] = [(root, 0)]
        var index = 0
        // Inspect structure only, never collect page text or search other windows.
        while index < queue.count && index < 64 {
            let (element, depth) = queue[index]
            index += 1
            if isWebArea(element) {
                if let editable = selectedEditableElement(element) { return editable }
                // A web area's document may contain an unrelated selection. Do not
                // search its contents for another editor when no focused one exists.
                continue
            }
            guard depth < 6 else { continue }
            let remaining = 64 - queue.count
            guard remaining > 0 else { continue }
            queue.append(contentsOf: children(element).prefix(remaining).map { ($0, depth + 1) })
        }
        return nil
    }
}
