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

    enum Sidebar {
        static let dashboard = Color(nsColor: .systemOrange)
        static let modes = Color(nsColor: .systemIndigo)
        static let models = Color(nsColor: .systemBrown)
        static let history = Color(nsColor: .systemPink)
        static let audio = Color(nsColor: .systemTeal)
        static let dictionary = Color(nsColor: .systemBlue)
        static let transcribeAudio = Color(red: 0.86, green: 0.32, blue: 0.27)
        /// Reserved for utility destinations (Settings) — not a catch-all for unassigned rows.
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
        static let secondaryForeground = Text.primary
        static let disabledFill = Surface.controlActive
        static let disabledForeground = Text.disabled
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
        static let tile: CGFloat = 6
        static let row: CGFloat = 10
        static let panel: CGFloat = 16
    }

    /// Recorder chrome. The recorder floats over arbitrary desktop content, so it keeps its own
    /// dark palette rather than following the app appearance — but it goes through tokens like
    /// everything else instead of literal `Color.white.opacity(_:)` at each call site.
    enum Recorder {
        static let chrome = Color.black.opacity(0.72)
        static let rim = Color.white.opacity(0.16)
        static let shadow = Color.black.opacity(0.34)
        static let separator = Color.white.opacity(0.15)

        /// The rim carries recorder state peripherally — one colour, one meaning.
        static let rimRecording = Color(nsColor: .systemRed).opacity(0.85)
        static let rimProcessing = Color(nsColor: .systemOrange).opacity(0.80)

        /// Signal Strip: health reads green/red, context reads blue. No other
        /// element in the recorder uses these families, so the split is legible
        /// without labels.
        static let healthOK = Color(nsColor: .systemGreen)
        static let healthBad = Color(nsColor: .systemRed)
        static let context = Color(nsColor: .systemBlue)

        static let label = Color.white
        static let labelSecondary = Color.white.opacity(0.86)
        static let labelTertiary = Color.white.opacity(0.62)
        static let labelDisabled = Color.white.opacity(0.30)
        static let labelInactive = Color.white.opacity(0.60)

        static let controlFill = Color.white.opacity(0.13)
        static let controlBorder = Color.white.opacity(0.18)
        static let fieldFill = Color.white.opacity(0.10)
        static let bubbleUser = Color.white.opacity(0.16)
        static let bubbleAssistant = Color.white.opacity(0.08)
        static let sendEnabled = Color.white.opacity(0.88)

        static let idleFill = Color(red: 0.30, green: 0.30, blue: 0.32)
        static let idleBorder = Color(red: 0.42, green: 0.42, blue: 0.44)
        static let idleMark = Color(red: 0.78, green: 0.78, blue: 0.80)
    }

    /// Spacing scale. Values match the intervals already in use across the app so migration is a
    /// rename, not a re-layout.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// Semantic type roles built on the system text styles, so the app scales with the user's
    /// text-size setting instead of pinning absolute point values.
    enum Typography {
        static let displayName = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let screenTitle = Font.system(.title2).weight(.semibold)
        static let sectionHeader = Font.system(.headline)
        static let cardTitle = Font.system(.subheadline).weight(.semibold)
        static let body = Font.system(.body)
        static let bodyEmphasized = Font.system(.body).weight(.medium)
        static let callout = Font.system(.callout)
        static let calloutEmphasized = Font.system(.callout).weight(.medium)
        static let label = Font.system(.subheadline)
        static let labelEmphasized = Font.system(.subheadline).weight(.medium)
        static let caption = Font.system(.caption)
        static let captionEmphasized = Font.system(.caption).weight(.medium)
        static let footnote = Font.system(.footnote)
        static let monospacedDigits = Font.system(.callout).monospacedDigit()
    }

    /// Motion scale. Durations and springs were previously re-declared per call site with values
    /// between 0.12s and 0.45s; these are the four that actually appear.
    enum Motion {
        static let micro = Animation.easeOut(duration: 0.12)
        static let quick = Animation.easeInOut(duration: 0.18)
        static let standard = Animation.easeInOut(duration: 0.25)
        static let emphasis = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let panelExpand = Animation.spring(response: 0.42, dampingFraction: 0.80)
        static let panelCollapse = Animation.spring(response: 0.45, dampingFraction: 1.0)
    }
}
