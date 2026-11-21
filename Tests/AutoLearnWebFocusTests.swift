import Foundation

@main
struct AutoLearnWebFocusTests {
    static func main() {
        // Recorded Muse shape: window -> group -> scroll area -> web area.
        // The editable text area is absent from AXChildren, but the selection's
        // text marker points to a static-text node with AXEditableAncestor.
        let tree = ["window": ["group"], "group": ["scroll"], "scroll": ["web"], "web": ["button"]]
        var inspected: [String] = []
        let resolver = AutoLearnWebFocusResolver<String>(
            isWebArea: { $0 == "web" },
            children: { tree[$0] ?? [] },
            selectedEditableElement: { inspected.append($0); return "hidden-editor" }
        )
        precondition(resolver.resolve(in: "window") == "hidden-editor")
        precondition(resolver.resolve(in: "web") == "hidden-editor")
        precondition(inspected == ["web", "web"])
        print("PASS Muse selection resolves editor missing from exposed children")

        // Muse 13.1 reports a button inside a group as the focused element.
        // Its containing web area is seven levels below the focused window.
        let deepTree = [
            "window": ["group1"], "group1": ["group2"], "group2": ["group3"],
            "group3": ["group4"], "group4": ["group5"], "group5": ["scroll"],
            "scroll": ["web"], "web": ["composer"], "composer": ["focus-proxy"]
        ]
        let parents = deepTree.reduce(into: [String: String]()) { result, entry in
            for child in entry.value { result[child] = entry.key }
        }
        let deepResolver = AutoLearnWebFocusResolver<String>(
            isWebArea: { $0 == "web" },
            children: { deepTree[$0] ?? [] },
            selectedEditableElement: { _ in "hidden-editor" }
        )
        precondition(deepResolver.resolve(in: "window") == nil)
        precondition(deepResolver.resolve(in: "focus-proxy") == nil)
        precondition(deepResolver.resolve(fromFocus: "focus-proxy") { parents[$0] } == "hidden-editor")
        print("PASS Muse focus proxy resolves the selected editor in a deeply nested web area")

        var readChildren: [String] = []
        let noSelection = AutoLearnWebFocusResolver<String>(
            isWebArea: { $0 == "web" },
            children: { readChildren.append($0); return tree[$0] ?? [] },
            selectedEditableElement: { _ in nil }
        )
        precondition(noSelection.resolve(in: "window") == nil)
        precondition(noSelection.resolve(fromFocus: "focus-proxy") { parents[$0] } == nil)
        precondition(!readChildren.contains("web"))
        print("PASS absent or noneditable selection never searches conversation contents")

        var visited = 0
        let cycle = AutoLearnWebFocusResolver<Int>(
            isWebArea: { _ in visited += 1; return false },
            children: { [$0, $0 + 1] },
            selectedEditableElement: { _ in preconditionFailure("not a web area") }
        )
        precondition(cycle.resolve(in: 0) == nil)
        precondition(visited <= 64)
        visited = 0
        precondition(cycle.resolve(fromFocus: 0) { $0 } == nil)
        precondition(visited <= 8)
        print("PASS cyclic or broad trees have bounded work")
    }
}
