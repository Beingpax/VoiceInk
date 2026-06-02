import SwiftUI
import SwiftData
import Foundation
import os

private struct DashboardStatsSummary: Equatable, Sendable {
    var totalCount: Int = 0
    var totalWords: Int = 0
    var totalDuration: TimeInterval = 0
}

private final class DashboardStatsCache: @unchecked Sendable {
    static let shared = DashboardStatsCache()

    private let lock = NSLock()
    private var summary: DashboardStatsSummary?

    private init() {}

    func currentSummary() -> DashboardStatsSummary? {
        lock.lock()
        defer { lock.unlock() }
        return summary
    }

    func update(_ summary: DashboardStatsSummary) {
        lock.lock()
        self.summary = summary
        lock.unlock()
    }
}

private enum DashboardStatsLoader {
    static func load(from modelContainer: ModelContainer) async throws -> DashboardStatsSummary {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let backgroundContext = ModelContext(modelContainer)
            let count = try backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())

            try Task.checkCancellation()

            var words = 0
            var duration: TimeInterval = 0
            let batchSize = 500
            var offset = 0

            while offset < count {
                try Task.checkCancellation()

                var descriptor = FetchDescriptor<SessionMetric>()
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let records = try backgroundContext.fetch(descriptor)
                if records.isEmpty {
                    break
                }

                for metric in records {
                    words += metric.wordCount
                    duration += metric.audioDuration
                }

                offset += records.count
            }

            try Task.checkCancellation()

            return DashboardStatsSummary(
                totalCount: count,
                totalWords: words,
                totalDuration: duration
            )
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct DashboardContent: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DashboardContent")
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState
    let onAddLicenseKey: () -> Void

    @State private var totalCount: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var hasLoadedStatsSnapshot: Bool = false
    @State private var dashboardStatsTask: Task<Void, Never>?
    @State private var isModelStatsPanelPresented = false
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @State private var isSystemInfoCopied = false

    init(
        modelContext: ModelContext,
        licenseState: LicenseViewModel.LicenseState,
        onAddLicenseKey: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.licenseState = licenseState
        self.onAddLicenseKey = onAddLicenseKey

        let cachedSummary = DashboardStatsCache.shared.currentSummary()
        _totalCount = State(initialValue: cachedSummary?.totalCount ?? 0)
        _totalWords = State(initialValue: cachedSummary?.totalWords ?? 0)
        _totalDuration = State(initialValue: cachedSummary?.totalDuration ?? 0)
        _hasLoadedStatsSnapshot = State(initialValue: cachedSummary != nil)
    }

    private func openModelStatsPanel() {
        isModelStatsPanelPresented = true
    }

    private func closeModelStatsPanel() {
        isModelStatsPanelPresented = false
    }

    var body: some View {
        Group {
            if totalCount == 0 && hasLoadedStatsSnapshot {
                emptyStateView
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            licenseStatusMessage

                            heroSection

                            if !isAccessibilityEnabled {
                                accessibilityReminder
                            }

                            voiceInkStatsSection

                            HStack(alignment: .top, spacing: 18) {
                                HelpAndResourcesSection()
                                DashboardPromotionsSection(licenseState: licenseState)
                            }

                            Spacer(minLength: 20)

                            HStack {
                                Spacer()
                                footerActionsView
                            }
                        }
                        .frame(minHeight: geometry.size.height - 56)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
        .task {
            await loadDashboardStatsEfficiently()
        }
        .onAppear(perform: refreshAccessibilityStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            dashboardStatsTask?.cancel()
            dashboardStatsTask = Task {
                await loadDashboardStatsEfficiently()
            }
        }
        .onDisappear {
            dashboardStatsTask?.cancel()
        }
        .sidePanel(isPresented: .init(
            get: { isModelStatsPanelPresented },
            set: { newValue in
                if !newValue { closeModelStatsPanel() }
            }
        )) {
            ModelPerformancePanel(onClose: closeModelStatsPanel)
        }
    }

    private var accessibilityReminder: some View {
        DashboardAccessibilityReminder(onOpenSettings: openAccessibilitySettings)
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func loadDashboardStatsEfficiently() async {
        do {
            let summary = try await DashboardStatsLoader.load(from: modelContext.container)

            guard !Task.isCancelled else {
                return
            }

            let shouldAcceptSummary = summary.totalCount > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard shouldAcceptSummary else {
                    return
                }

                self.totalCount = summary.totalCount
                self.totalWords = summary.totalWords
                self.totalDuration = summary.totalDuration
                DashboardStatsCache.shared.update(summary)
                self.hasLoadedStatsSnapshot = true
            }
        } catch is CancellationError {
        } catch {
            logger.error("Error loading dashboard stats: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var emptyStateView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    licenseStatusMessage

                    VStack(spacing: 20) {
                        Image(systemName: "waveform")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("No Recorder Sessions Yet")
                            .font(.title3.weight(.semibold))
                        Text("Start your first recording to unlock value insights.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height - 56)

                    if !isAccessibilityEnabled {
                        accessibilityReminder
                    }
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 24)
            }
        }
    }
    
    // MARK: - Sections

    @ViewBuilder
    private var licenseStatusMessage: some View {
        switch licenseState {
        case .unlicensed:
            TrialMessageView(
                message: "Activate a license to continue using VoiceInk.",
                type: .licenseRequired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trial(let daysRemaining):
            TrialMessageView(
                message: "You have \(daysRemaining) days left in your trial",
                type: daysRemaining <= 2 ? .warning : .info,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trialExpired:
            TrialMessageView(
                message: "Your trial has expired. Upgrade to continue using VoiceInk",
                type: .expired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .licensed:
            EmptyView()
        }
    }
    
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)

                if hasLoadedStatsSnapshot {
                    (Text("You have saved ")
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                     +
                     Text(formattedTimeSaved)
                        .fontWeight(.black)
                        .font(.system(size: 36, design: .rounded))
                        .foregroundStyle(.white)
                     +
                     Text(" with VoiceInk")
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                    )
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                } else {
                    Text("VoiceInk Insights")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 16)
    }
    
    private var voiceInkStatsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            DashboardStatCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: hasLoadedStatsSnapshot ? "\(totalCount)" : "–",
                detail: "VoiceInk sessions completed",
                color: AppTheme.Sidebar.audio
            )

            DashboardStatCard(
                icon: "text.alignleft",
                title: "Words Dictated",
                value: hasLoadedStatsSnapshot ? Formatters.formattedNumber(totalWords) : "–",
                detail: "words generated",
                color: AppTheme.Sidebar.dictionary
            )
            
            DashboardStatCard(
                icon: "speedometer",
                title: "Words Per Minute",
                value: hasLoadedStatsSnapshot && averageWordsPerMinute > 0
                    ? String(format: "%.1f", averageWordsPerMinute)
                    : "–",
                detail: "VoiceInk vs. typing by hand",
                color: AppTheme.Sidebar.dashboard
            )
            
            DashboardStatCard(
                icon: "keyboard.fill",
                title: "Keystrokes Saved",
                value: hasLoadedStatsSnapshot ? Formatters.formattedNumber(totalKeystrokesSaved) : "–",
                detail: "fewer keystrokes",
                color: AppTheme.Sidebar.modes
            )
        }
    }

    private var footerActionsView: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: openModelStatsPanel) {
                footerActionLabel(icon: "gauge", title: "Model Performance", color: AppTheme.Sidebar.models)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help("View transcription and enhancement model performance")

            Button(action: copySystemInfo) {
                footerActionLabel(
                    icon: isSystemInfoCopied ? "checkmark" : "doc.on.doc",
                    title: isSystemInfoCopied ? "Copied!" : "Copy System Info",
                    color: isSystemInfoCopied ? AppTheme.Sidebar.license : AppTheme.Sidebar.fallback
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSystemInfoCopied)
        }
    }

    @ViewBuilder
    private func footerActionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            DashboardIconGlyph(systemName: icon, color: color, size: 13, frameSize: 16)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .frame(width: nil, height: 36, alignment: .center)
        .background(AppCardBackground(cornerRadius: 18))
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isSystemInfoCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isSystemInfoCopied = false
            }
        }
    }
    
    private var formattedTimeSaved: String {
        let formatted = Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings coming soon")
        return formatted
    }
    
    private var heroSubtitle: String {
        guard hasLoadedStatsSnapshot else {
            return "Your usage summary will appear here."
        }

        guard totalCount > 0 else {
            return "Your VoiceInk journey starts with your first recording."
        }

        let wordsText = Formatters.formattedNumber(totalWords)
        let sessionText = totalCount == 1 ? "session" : "sessions"

        return "Dictated \(wordsText) words across \(totalCount) \(sessionText)."
    }
    
    private var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                AppTheme.Accent.primary,
                AppTheme.Accent.strong,
                AppTheme.Accent.foreground
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Computed Metrics

    private var estimatedTypingTime: TimeInterval {
        let averageTypingSpeed: Double = 35 // words per minute
        let estimatedTypingTimeInMinutes = Double(totalWords) / averageTypingSpeed
        return estimatedTypingTimeInMinutes * 60
    }

    private var timeSaved: TimeInterval {
        max(estimatedTypingTime - totalDuration, 0)
    }

    private var averageWordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    private var totalKeystrokesSaved: Int {
        Int(Double(totalWords) * 5.0)
    }
    
}

private struct DashboardAccessibilityReminder: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Accent.fill)

                Image(systemName: "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Enable Accessibility Access")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Required for VoiceInk shortcuts and app-wide controls to work properly.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Open Settings", action: onOpenSettings)
                .controlSize(.small)
                .help("Open Accessibility settings")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: 16))
    }
}

private enum Formatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    static func formattedNumber(_ value: Int) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formattedDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "–") -> String {
        guard interval > 0 else { return fallback }
        durationFormatter.unitsStyle = style
        durationFormatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return durationFormatter.string(from: interval) ?? fallback
    }
}
