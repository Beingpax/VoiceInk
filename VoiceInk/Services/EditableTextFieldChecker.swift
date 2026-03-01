import AppKit
import ApplicationServices

enum EditableTextFieldChecker {
 static func isEditableTextFieldFocused() -> Bool {
  let systemWide = AXUIElementCreateSystemWide()

  var focusedElement: AnyObject?
  let focusResult = AXUIElementCopyAttributeValue(
   systemWide,
   kAXFocusedUIElementAttribute as CFString,
   &focusedElement
  )

  guard focusResult == .success, let focusedElement else {
   return false
  }
  // AXUIElement is a CFTypeRef; the accessibility API always returns one on success
  let element = focusedElement as! AXUIElement

  var roleValue: AnyObject?
  let roleResult = AXUIElementCopyAttributeValue(
   element,
   kAXRoleAttribute as CFString,
   &roleValue
  )

  guard roleResult == .success, let role = roleValue as? String else {
   return false
  }

  let editableRoles: Set<String> = [
   kAXTextFieldRole,
   kAXTextAreaRole,
   kAXComboBoxRole,
   "AXSearchField",
   "AXWebArea",
  ]

  return editableRoles.contains(role)
 }
}
