import SwiftUI

// MARK: - Recorder Chrome

/// The recorder's panel surface. Replaces a flat opaque `Color.black` with a dark material, a
/// rim light and a drop shadow, so the panel reads as floating above the desktop rather than
/// punched out of it.
struct RecorderChrome: View {
    var cornerRadius: CGFloat
    var rimState: RecorderRimState = .neutral

    private var rimWidth: CGFloat { rimState == .neutral ? 0.5 : 1 }

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(AppTheme.Recorder.chrome))
            .overlay(shape.strokeBorder(rimState.color, lineWidth: rimWidth))
            .compositingGroup()
            .shadow(color: AppTheme.Recorder.shadow, radius: 12, y: 4)
            // A soft outer bloom in the rim colour, so state is readable from the corner of the
            // eye without occupying any layout.
            .shadow(color: rimState.glow ?? .clear, radius: 7)
            .animation(AppTheme.Motion.standard, value: rimState)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// Same treatment for the notch, which needs its own clip shape rather than a rounded rectangle.
struct NotchRecorderChrome: View {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var rimState: RecorderRimState = .neutral

    var body: some View {
        let shape = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )

        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(AppTheme.Recorder.chrome))
            // The notch is flush with the bezel on three sides, so only the visible lower edge
            // carries the rim — a full stroke would draw a line across the display cutout.
            .overlay(
                shape.stroke(rimState.color, lineWidth: rimState == .neutral ? 0 : 1.5)
                    .mask(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.35),
                            .init(color: .black, location: 0.75),
                        ],
                        startPoint: .top, endPoint: .bottom))
            )
            .compositingGroup()
            .shadow(color: AppTheme.Recorder.shadow, radius: 10, y: 3)
            .shadow(color: rimState.glow ?? .clear, radius: 6)
            .animation(AppTheme.Motion.standard, value: rimState)
    }
}

// MARK: - Icon Toggle Button

struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let disabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    init(
        isEnabled: Bool,
        icon: String,
        disabled: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.disabled = disabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    private var isEmoji: Bool {
        !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }

    private var tint: Color {
        if disabled { return AppTheme.Recorder.labelDisabled }
        return isEnabled ? AppTheme.Recorder.label : AppTheme.Recorder.labelInactive
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon).font(.system(size: 14))
                } else {
                    Image(systemName: icon).font(.system(size: 13))
                }
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Record Button

struct RecorderRecordButton: View {
    let recordingState: RecordingState
    let action: () -> Void

    private var visualState: VisualState {
        switch recordingState {
        case .idle, .starting, .busy:
            return .ready
        case .recording:
            return .recording
        case .transcribing, .enhancing:
            return .processing
        }
    }

    private var isDisabled: Bool {
        switch recordingState {
        case .idle, .recording:
            return false
        case .starting, .transcribing, .enhancing, .busy:
            return true
        }
    }

    var body: some View {
        Button(action: action) {
            buttonFace
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonFace: some View {
        ZStack {
            Circle()
                .fill(colors.surface)
                .overlay(
                    Circle()
                        .strokeBorder(colors.border, lineWidth: 0.6)
                )

            stateMark
        }
        .frame(width: 21, height: 21)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.16), value: visualState)
    }

    private var colors: StateColors {
        switch visualState {
        case .ready:
            return StateColors(
                surface: AppTheme.Recorder.idleFill,
                border: AppTheme.Recorder.idleBorder,
                mark: AppTheme.Recorder.idleMark
            )
        case .recording:
            let red = AppTheme.Status.error
            return StateColors(
                surface: red.opacity(0.92),
                border: red.opacity(0.98),
                mark: AppTheme.Recorder.label
            )
        case .processing:
            return StateColors(
                surface: AppTheme.Recorder.controlFill,
                border: AppTheme.Recorder.controlBorder,
                mark: AppTheme.Recorder.labelSecondary
            )
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch visualState {
        case .ready, .recording:
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .fill(colors.mark)
                .frame(width: 8, height: 8)
        case .processing:
            ProcessingIndicator(color: colors.mark)
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return String(localized: "Start recording")
        case .starting:
            return String(localized: "Starting recording")
        case .recording:
            return String(localized: "Stop recording")
        case .transcribing:
            return String(localized: "Transcribing recording")
        case .enhancing:
            return String(localized: "Enhancing recording")
        case .busy:
            return String(localized: "Recorder unavailable")
        }
    }

    private enum VisualState: Equatable {
        case ready
        case recording
        case processing
    }

    private struct StateColors {
        let surface: Color
        let border: Color
        let mark: Color
    }
}

// MARK: - Close Button

struct RecorderCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.Recorder.controlFill)
                    .overlay(
                        Circle()
                            .strokeBorder(AppTheme.Recorder.controlBorder, lineWidth: 0.6)
                    )

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.Recorder.labelSecondary)
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    let color: Color

    /// Seconds per full turn.
    private let period: TimeInterval = 1

    var body: some View {
        // TimelineView drives rotation off the frame clock, so it suspends when the view is
        // offscreen or the window is occluded — unlike a retained `repeatForever` animation.
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSinceReferenceDate / period

            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(color, lineWidth: 1.5)
                .rotationEffect(.degrees(360 * turns.truncatingRemainder(dividingBy: 1)))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Progress Dot Animation

struct ProgressAnimation: View {
    let color: Color
    let animationSpeed: Double

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2

    init(color: Color = AppTheme.Recorder.label, animationSpeed: Double = 0.3) {
        self.color = color
        self.animationSpeed = animationSpeed
    }

    /// One extra step at each end produces the brief all-off pause the original sentinel value
    /// was reaching for.
    private var phaseCount: Int { dotCount + 2 }

    var body: some View {
        PhaseAnimator(0..<phaseCount) { phase in
            HStack(spacing: dotSpacing) {
                ForEach(0..<dotCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: dotSize / 2, style: .continuous)
                        .fill(color.opacity(index < phase ? 0.85 : 0.25))
                        .frame(width: dotSize, height: dotSize)
                }
            }
        } animation: { _ in
            .easeInOut(duration: animationSpeed)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Mode Button

/// Mode switcher. Expands inline on hover into a row of the first few enabled modes with their
/// ⌥-number badges, instead of opening a popover that steals focus.
///
/// `RecorderPanelShortcutManager` already binds ⌥1–9 to modes while the panel is visible
/// (`ShortcutAction.recorderPanelMode`), and nothing on screen has ever said so.
struct RecorderModeButton: View {
    private let modeManager = ModeManager.shared
    let buttonSize: CGFloat
    let padding: EdgeInsets

    /// ⌥1–9 plus ⌥0 are bound, but a row of ten is unreadable at panel scale.
    private static let inlineModeLimit = 4
    private static let collapseDelay = Duration.milliseconds(260)

    /// Bound to the panel so it can widen to fit the row — at the compact 184pt the chips were
    /// simply clipped off the right edge.
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    init(
        buttonSize: CGFloat = 28,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7),
        isExpanded: Binding<Bool>
    ) {
        self.buttonSize = buttonSize
        self.padding = padding
        self._isExpanded = isExpanded
    }

    private var enabledModes: [ModeConfig] {
        modeManager.enabledConfigurations
    }

    private var hasModes: Bool { !enabledModes.isEmpty }

    private var inlineModes: [ModeConfig] {
        Array(enabledModes.prefix(Self.inlineModeLimit))
    }

    private var activeModeID: UUID? {
        modeManager.currentEffectiveConfiguration?.id
    }

    private var currentModeName: String {
        modeManager.currentEffectiveConfiguration?.name ?? String(localized: "None")
    }

    var body: some View {
        Group {
            if isExpanded && hasModes {
                modeRow
            } else {
                collapsedButton
            }
        }
        .padding(padding)
        .onHover { isHovering = $0 }
        .animation(AppTheme.Motion.quick, value: isExpanded)
        // Expand on hover, collapse on a short delay so crossing a gap between chips does not
        // snap it shut. Cancellation is tied to view lifetime.
        .task(id: isHovering) {
            if isHovering {
                isExpanded = true
                return
            }
            guard isExpanded else { return }
            try? await Task.sleep(for: Self.collapseDelay)
            guard !Task.isCancelled else { return }
            isExpanded = false
        }
    }

    private var collapsedButton: some View {
        RecorderToggleButton(
            isEnabled: hasModes,
            icon: hasModes
                ? (modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2") : "square.grid.2x2",
            disabled: !hasModes,
            accessibilityLabel: hasModes
                ? String(format: String(localized: "Switch mode, currently %@"), currentModeName)
                : String(localized: "No modes configured")
        ) {
            isExpanded.toggle()
        }
        .frame(width: buttonSize)
    }

    private var modeRow: some View {
        HStack(spacing: 4) {
            RecorderModeChips(modes: Array(inlineModes.enumerated()), activeModeID: activeModeID)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
    }
}

/// The chips, separated from the button so the notch recorder can split them across the camera
/// cutout instead of running the whole row underneath it.
struct RecorderModeChips: View {
    let modes: [(offset: Int, element: ModeConfig)]
    let activeModeID: UUID?

    private let modeManager = ModeManager.shared

    var body: some View {
        ForEach(modes, id: \.element.id) { index, mode in
            RecorderModeChip(
                mode: mode,
                shortcutNumber: index + 1,
                isActive: mode.id == activeModeID
            ) {
                modeManager.setActiveConfiguration(mode)
            }
        }
    }
}

/// Splits the enabled modes into the two columns either side of the notch.
@MainActor
enum RecorderNotchModeSplit {
    static func columns(
        limit: Int = 4
    ) -> (leading: [(offset: Int, element: ModeConfig)], trailing: [(offset: Int, element: ModeConfig)]) {
        let modes = Array(ModeManager.shared.enabledConfigurations.prefix(limit).enumerated())
            .map { (offset: $0.offset, element: $0.element) }
        let split = (modes.count + 1) / 2
        return (Array(modes.prefix(split)), Array(modes.dropFirst(split)))
    }
}

private struct RecorderModeChip: View {
    let mode: ModeConfig
    let shortcutNumber: Int
    let isActive: Bool
    let action: () -> Void

    private var label: String {
        String(format: String(localized: "Switch to %@, option %lld"), mode.name, Int64(shortcutNumber))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("⌥\(shortcutNumber)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isActive ? AppTheme.Recorder.label : AppTheme.Recorder.labelTertiary
                    )

                Text(mode.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 78, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(
                        isActive ? AppTheme.Recorder.label : AppTheme.Recorder.labelSecondary
                    )
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                Capsule().fill(
                    isActive ? AppTheme.Recorder.bubbleUser : AppTheme.Recorder.controlFill
                )
            )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Live Transcript View

struct LiveTranscriptView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Recorder.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .id("bottom")
            }
            .frame(height: 56)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Recorder Status Display

struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeterProvider: () -> AudioMeter
    let menuBarHeight: CGFloat?

    init(
        currentState: RecordingState,
        audioMeterProvider: @escaping () -> AudioMeter,
        menuBarHeight: CGFloat? = nil
    ) {
        self.currentState = currentState
        self.audioMeterProvider = audioMeterProvider
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                ProcessingStatusDisplay(mode: .enhancing, color: .white).transition(.opacity)
            } else if currentState == .transcribing {
                ProcessingStatusDisplay(mode: .transcribing, color: .white).transition(.opacity)
            } else if currentState == .recording {
                AudioVisualizer(
                    audioMeterProvider: audioMeterProvider,
                    color: .white,
                    isActive: true
                )
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentState)
    }
}

// MARK: - Assistant Response Panel

struct AssistantPanelView: View {
    var session: AssistantSession
    let liveFollowUpText: String
    let onSend: (String) -> Void

    @State private var draftMessage = ""
    @FocusState private var isFollowUpFieldFocused: Bool

    private let horizontalPadding: CGFloat = 20
    private let followUpTextColor = AppTheme.Recorder.labelSecondary

    private var statusText: String? {
        switch session.phase {
        case .responding, .sendingFollowUp:
            return String(localized: "Thinking")
        case .failed(let message):
            return message
        case .inactive, .ready:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            messageList
            followUpRow
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(height: 320)
        .onAppear(perform: focusFollowUpFieldIfAvailable)
        .onChange(of: session.phase) {
            focusFollowUpFieldIfAvailable()
        }
    }

    private var fullConversationText: String {
        session.messages.map { msg in
            let prefix = msg.role == .user ? "You" : "Assistant"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(session.messages) { message in
                        AssistantMessageBubble(message: message)
                            .id(message.id)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Recorder.labelTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("status")
                    }
                }
                .padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if !session.messages.isEmpty {
                        CopyIconButton(textToCopy: fullConversationText)
                            .scaleEffect(0.72)
                    }
                }
            }
            .onChange(of: session.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: session.phase) {
                scrollToBottom(proxy)
            }
        }
    }

    private var followUpRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if shouldShowLiveFollowUpText {
                    Text(liveFollowUpText)
                        .font(.system(size: 12))
                        .foregroundStyle(followUpTextColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .allowsHitTesting(false)
                }

                TextField("", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(followUpTextColor)
                    .tint(followUpTextColor)
                    .disabled(!session.canSendFollowUp)
                    .focused($isFollowUpFieldFocused)
                    .onSubmit(sendDraftMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.Recorder.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: sendDraftMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canSendDraft ? .black : AppTheme.Recorder.labelDisabled)
                    .frame(width: 24, height: 24)
                    .background(canSendDraft ? AppTheme.Recorder.sendEnabled : AppTheme.Recorder.fieldFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft)
            .help("Send follow up")
        }
    }

    private var shouldShowLiveFollowUpText: Bool {
        draftMessage.isEmpty && !liveFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendDraft: Bool {
        session.canSendFollowUp && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraftMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard session.canSendFollowUp, !trimmed.isEmpty else { return }
        draftMessage = ""
        onSend(trimmed)
        focusFollowUpFieldIfAvailable()
    }

    private func focusFollowUpFieldIfAvailable() {
        guard session.canSendFollowUp else { return }
        DispatchQueue.main.async {
            isFollowUpFieldFocused = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    proxy.scrollTo("status", anchor: .bottom)
                }
            }
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantDisplayMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            MarkdownContentView(
                message.content,
                fontSize: 12,
                foregroundColor: isUser ? AppTheme.Recorder.label : AppTheme.Recorder.labelSecondary,
                alignment: .leading
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isUser ? AppTheme.Recorder.bubbleUser : AppTheme.Recorder.bubbleAssistant)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUser {
                    CopyIconButton(textToCopy: message.content)
                        .scaleEffect(0.72)
                        .padding(0)
                }
            }
            .help(isUser ? message.content : "")

            if !isUser {
                Spacer(minLength: 36)
            }
        }
    }
}
