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

  guard focusResult == .success, let element = focusedElement else {
   return false
  }

  var roleValue: AnyObject?
  let roleResult = AXUIElementCopyAttributeValue(
   element as! AXUIElement,
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
