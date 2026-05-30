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
        static let materialCard = Color(NSColor.controlBackgroundColor).opacity(0.50)
        static let subtle = Color.primary.opacity(0.06)
        static let controlActive = Color.secondary.opacity(0.14)
        static let control = Color(NSColor.controlBackgroundColor)
        static let window = Color(NSColor.windowBackgroundColor)
        static let sidePanelOverlay = Color(NSColor.windowBackgroundColor).opacity(0.50)
    }

    enum Border {
        static let subtle = Color(NSColor.separatorColor).opacity(0.28)
        static let card = Color(NSColor.separatorColor).opacity(0.35)
        static let control = Color(NSColor.separatorColor)
        static let tint = Color.primary.opacity(0.12)
        static let sidePanelOuter = Color.white.opacity(0.12)
    }

    enum Selection {
        static let fill = Color.primary.opacity(0.10)
        static let border = Color.primary.opacity(0.14)
        static let foreground = Color.primary.opacity(0.78)
    }

    enum Status {
        static let success = Color.white.opacity(0.85)
        static let positive = Color.green
        static let info = Color.white.opacity(0.75)
        static let infoStrong = Color.blue
        static let warning = Color.white.opacity(0.85)
        static let warningStrong = Color.orange
        static let error = Color.red
    }

    enum Data {
        static let transcript = Color.indigo
        static let audio = Color.teal
        static let enhancement = Color.mint
        static let purple = Color(nsColor: .systemPurple)
        static let yellow = Color(nsColor: .systemYellow)
        static let orange = Color(nsColor: .systemOrange)
    }

    enum Sidebar {
        static let dashboard = Color(nsColor: .systemOrange)
        static let modes = Color(nsColor: .systemIndigo)
        static let models = Color(nsColor: .systemBrown)
        static let audio = Color(nsColor: .systemPink)
        static let dictionary = Color(nsColor: .systemBlue)
        static let transcribeAudio = Color(nsColor: .systemTeal)
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
        static let muted = Color.secondary.opacity(0.70)
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }
}
