import CoreGraphics

enum LayoutGuidance {
    static func horizontalPadding(for width: CGFloat, isMinimalist: Bool) -> CGFloat {
        if width < 900 {
            return isMinimalist ? 8 : 12
        } else if width < 1200 {
            return isMinimalist ? 12 : 16
        } else {
            return isMinimalist ? 16 : 20
        }
    }
}
