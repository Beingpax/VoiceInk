import SwiftUI

enum AppTheme {
    enum Accent {
        static let primary = Color.accentColor
        static let fillSubtle = primary.opacity(0.10)
        static let fill = primary.opacity(0.14)
        static let fillStrong = primary.opacity(0.28)
        static let border = primary.opacity(0.40)
        static let disabled = primary.opacity(0.50)
        static let foreground = primary.opacity(0.65)
        static let strong = primary.opacity(0.80)
        static let shadow = primary.opacity(0.20)
    }

    enum Surface {
        static let card = Color.secondary.opacity(0.10)
        static let materialCard = Color(nsColor: .controlBackgroundColor).opacity(0.50)
        static let subtle = Color.primary.opacity(0.06)
        static let controlActive = Color.secondary.opacity(0.14)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let window = Color(nsColor: .windowBackgroundColor)
        static let sidePanelOverlay = Color(nsColor: .windowBackgroundColor).opacity(0.50)
        static let clear = Color.clear
    }

    enum Border {
        static let subtle = Color(nsColor: .separatorColor).opacity(0.28)
        static let card = Color(nsColor: .separatorColor).opacity(0.35)
        static let control = Color(nsColor: .separatorColor)
        static let tint = Color.primary.opacity(0.12)
        static let sidePanelOuter = Color.white.opacity(0.12)
    }

    enum Selection {
        static let fill = Color.primary.opacity(0.10)
        static let border = Color.primary.opacity(0.14)
        static let foreground = Color.primary.opacity(0.78)
    }

    enum Status {
        static let success = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let positive = Color(nsColor: .systemGreen)
        static let info = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.75)
        static let infoStrong = Color(nsColor: .systemBlue)
        static let warning = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let warningStrong = Color(nsColor: .systemOrange)
        static let error = Color(nsColor: .systemRed)
    }

    enum Data {
        static let transcript = Color.indigo
        static let audio = Color.teal
        static let enhancement = Color.mint
        static let purple = Color(nsColor: .systemPurple)
        static let yellow = Color(nsColor: .systemYellow)
        static let orange = Color(nsColor: .systemOrange)
    }

    enum Insights {
        static let page = neutral(light: 0.995, dark: 0.065)
        static let card = neutral(light: 0.955, dark: 0.105)
        static let elevated = neutral(light: 1.0, dark: 0.145)
        static let hover = Color.primary.opacity(0.045)
        static let border = AppTheme.Border.tint
        static let productivity = Color(nsColor: .systemBlue)
        static let activity = Color(nsColor: .systemTeal)
        static let selection = productivity.opacity(0.12)
        static let selectionText = dynamic(
            light: NSColor(srgbRed: 0.10, green: 0.32, blue: 0.66, alpha: 1),
            dark: NSColor(srgbRed: 0.42, green: 0.68, blue: 1.0, alpha: 1)
        )
        static let grid = Color.primary.opacity(0.075)

        private static func neutral(light: CGFloat, dark: CGFloat) -> Color {
            dynamic(light: NSColor(white: light, alpha: 1), dark: NSColor(white: dark, alpha: 1))
        }

        private static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? dark : light
            })
        }
    }

    enum Sidebar {
        static let dashboard = Color(nsColor: .systemOrange)
        static let modes = Color(nsColor: .systemIndigo)
        static let models = Color(nsColor: .systemBrown)
        static let audio = Color(nsColor: .systemPink)
        static let dictionary = Color(nsColor: .systemBlue)
        static let transcribeAudio = Color(red: 0.86, green: 0.32, blue: 0.27)
        static let fallback = Color(nsColor: .systemGray)
        static let license = Color(nsColor: .systemGreen)
    }

    enum Waveform {
        static let hoverBubble = Color.primary.opacity(0.74)
        static let hoverMarker = Color.primary.opacity(0.68)
        static let playedLower = Color.primary
        static let playedUpper = Color.primary.opacity(0.80)
        static let unplayedLower = Color.primary.opacity(0.30)
        static let unplayedUpper = Color.primary.opacity(0.20)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let muted = secondary.opacity(0.70)
        static let disabled = Color(nsColor: .disabledControlTextColor)
        static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    }

    enum NativeText {
        static let primary = NSColor.labelColor
    }

    enum Action {
        static let primaryFill = Accent.primary
        static let primaryForeground = Text.onAccent
        static let destructiveFill = Color(nsColor: .systemRed)
        static let destructiveForeground = Text.onAccent
        static let secondaryForeground = Text.primary
        static let disabledFill = Surface.controlActive
        static let disabledForeground = Text.disabled
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }
}
