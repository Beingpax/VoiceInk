import SwiftUI

// MARK: - Recorder Chrome

/// The recorder's panel surface. Replaces a flat opaque `Color.black` with a dark material, a
/// rim light and a drop shadow, so the panel reads as floating above the desktop rather than
/// punched out of it.
struct RecorderChrome: View {
    var cornerRadius: CGFloat

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(AppTheme.Recorder.chrome))
            .overlay(shape.strokeBorder(AppTheme.Recorder.rim, lineWidth: 0.5))
            .compositingGroup()
            .shadow(color: AppTheme.Recorder.shadow, radius: 12, y: 4)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// Same treatment for the notch, which needs its own clip shape rather than a rounded rectangle.
struct NotchRecorderChrome: View {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var body: some View {
        let shape = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )

        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(AppTheme.Recorder.chrome))
            .compositingGroup()
            .shadow(color: AppTheme.Recorder.shadow, radius: 10, y: 3)
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

struct RecorderModeButton: View {
    private let modeManager = ModeManager.shared
    let buttonSize: CGFloat
    let padding: EdgeInsets

    private static let dismissDelay = Duration.milliseconds(250)

    @State private var isPopoverPresented = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false

    init(buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self.buttonSize = buttonSize
        self.padding = padding
    }

    private var hasModes: Bool {
        !modeManager.enabledConfigurations.isEmpty
    }

    private var isHovering: Bool {
        isHoveringButton || isHoveringPopover
    }

    private var currentModeName: String {
        modeManager.currentEffectiveConfiguration?.name ?? String(localized: "None")
    }

    var body: some View {
        RecorderToggleButton(
            isEnabled: hasModes,
            icon: hasModes
                ? (modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2") : "square.grid.2x2",
            disabled: !hasModes,
            accessibilityLabel: hasModes
                ? String(format: String(localized: "Switch mode, currently %@"), currentModeName)
                : String(localized: "No modes configured")
        ) {
            isPopoverPresented.toggle()
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover { isHoveringButton = $0 }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            ModePopover()
                .onHover { isHoveringPopover = $0 }
        }
        // Debounce dismissal so travelling from the button to the popover does not close it.
        // Cancellation is tied to view lifetime, so there is no work item to leak.
        .task(id: isHovering) {
            if isHovering {
                isPopoverPresented = true
                return
            }

            guard isPopoverPresented else { return }
            try? await Task.sleep(for: Self.dismissDelay)
            guard !Task.isCancelled else { return }
            isPopoverPresented = false
        }
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
