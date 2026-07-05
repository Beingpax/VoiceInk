import SwiftUI
import SwiftData
import Foundation
import os

struct DashboardContent: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DashboardContent")
    private static let fallbackDisplayName = String(localized: "there")
    private static let displayNameFontSize: CGFloat = 28
    private static let displayNameFontWeight: NSFont.Weight = .bold
    private static let displayNameMinWidth: CGFloat = 72
    private static let displayNameMaxWidth: CGFloat = 280
    private static let displayNameHorizontalPadding: CGFloat = 8
    private static let insightsUnlockDuration: TimeInterval = 30 * 60
    private static let peakHoursUnlockDuration: TimeInterval = 30 * 60
    // Above this count, skip live auto-refresh (full reload is expensive); tab reopen still refreshes.
    private static let automaticStatsRefreshMetricLimit = 2_000
    private static let statsRefreshDebounceNanoseconds: UInt64 = 750_000_000
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState
    let onAddLicenseKey: () -> Void

    @State private var statsSummary: DashboardStatsSummary = .empty
    @State private var hasLoadedStatsSnapshot: Bool = false
    @State private var statsSnapshotGeneratedAt: Date?
    @State private var isDashboardStatsRefreshing = false
    @State private var dashboardStatsTask: Task<Void, Never>?
    @State private var dashboardStatsLoadGeneration = 0
    @State private var isModelPerformancePanelPresented = false
    @State private var isModelUsagePanelPresented = false
    @State private var isInsightsViewPresented = false
    @State private var selectedInsightPeriod: DashboardInsightPeriod = .lastSevenDays
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @State private var isSystemInfoCopied = false
    @State private var isEditingDisplayName = false
    @State private var displayNameDraft = ""
    @AppStorage("dashboardDisplayName") private var dashboardDisplayName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @Query(Self.recentTranscriptionsDescriptor()) private var recentTranscriptionCandidates: [Transcription]

    private static func recentTranscriptionsDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return descriptor
    }

    init(
        modelContext: ModelContext,
        licenseState: LicenseViewModel.LicenseState,
        onAddLicenseKey: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.licenseState = licenseState
        self.onAddLicenseKey = onAddLicenseKey

        let cachedSummary = DashboardStatsCache.shared.currentSummary()
        let cachedMetadata = DashboardStatsCache.shared.currentMetadata()
        _statsSummary = State(initialValue: cachedSummary ?? .empty)
        _hasLoadedStatsSnapshot = State(initialValue: cachedSummary != nil)
        _statsSnapshotGeneratedAt = State(initialValue: cachedMetadata?.generatedAt)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = DashboardLayout.contentWidth(for: geometry.size.width)

            ZStack(alignment: .top) {
                DashboardAmbientBackground()

                ScrollView {
                    Group {
                        if isInsightsViewPresented && canViewInsights {
                            dashboardInsightsView
                        } else {
                            dashboardMainContent(availableWidth: contentWidth)
                        }
                    }
                    .frame(width: contentWidth, alignment: .top)
                    .frame(
                        minHeight: max(0, geometry.size.height - DashboardLayout.contentBottomOffset),
                        alignment: .top
                    )
                    .padding(.vertical, DashboardLayout.pageVerticalPadding)
                    .padding(.horizontal, DashboardLayout.pageHorizontalPadding)
                }
            }
        }
        .task {
            await scheduleDashboardStatsRefresh(allowSkipWhenFresh: hasLoadedStatsSnapshot)
        }
        .onAppear(perform: refreshAccessibilityStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            DashboardStatsCache.shared.markStale()

            if shouldRefreshStatsAfterMetricChange {
                scheduleDashboardStatsRefresh(debounce: true, allowSkipWhenFresh: false)
            }
        }
        .onDisappear {
            dashboardStatsTask?.cancel()
            dashboardStatsTask = nil
            dashboardStatsLoadGeneration += 1
            isDashboardStatsRefreshing = false
        }
        .sidePanel(isPresented: $isModelPerformancePanelPresented) {
            ModelPerformancePanel(
                selectedPeriod: $selectedInsightPeriod,
                summaries: selectedModelPerformance
            ) {
                isModelPerformancePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isModelUsagePanelPresented) {
            ModelUsagePanel(
                selectedPeriod: $selectedInsightPeriod,
                summary: selectedModelUsage
            ) {
                isModelUsagePanelPresented = false
            }
        }
    }

    private func dashboardMainContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
            licenseStatusMessage

            greetingHeader

            nameEditorDismissArea {
                heroSection
            }

            if !isAccessibilityEnabled {
                nameEditorDismissArea {
                    accessibilityReminder
                }
            }

            if !recentDashboardTranscriptions.isEmpty {
                nameEditorDismissArea {
                    DashboardTranscriptCards(transcriptions: recentDashboardTranscriptions)
                }
            }

            Spacer(minLength: DashboardLayout.footerTopSpacing)

            nameEditorDismissArea {
                HStack {
                    Spacer()
                    footerActionsView
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: availableWidth, alignment: .topLeading)
    }

    private var recentDashboardTranscriptions: [Transcription] {
        Array(
            recentTranscriptionCandidates
                .filter { transcription in
                    isRecentDashboardTranscription(transcription)
                }
                .prefix(5)
        )
    }

    private func isRecentDashboardTranscription(_ transcription: Transcription) -> Bool {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
            transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue {
            return false
        }

        return text.range(of: "Transcription Failed:", options: [.caseInsensitive, .anchored]) == nil
    }

    private var selectedProductivityPoints: [DashboardProductivityPoint] {
        statsSummary.productivity(for: selectedInsightPeriod)
    }

    private var selectedModelPerformance: [ModelPerformanceSummary] {
        statsSummary.modelPerformance(for: selectedInsightPeriod)
    }

    private var selectedModelUsage: ModelUsageSummary {
        statsSummary.modelUsage(for: selectedInsightPeriod)
    }

    private var selectedPeakHours: DashboardPeakHoursSummary {
        statsSummary.peakHours(for: selectedInsightPeriod)
    }

    private var selectedTotals: DashboardMetricTotals {
        statsSummary.totals(for: selectedInsightPeriod)
    }

    private var selectedTimeSavedSummary: DashboardTimeSavedSummary {
        return DashboardTimeSavedSummary(
            timeSaved: DashboardTimeSaving.timeSaved(words: selectedTotals.words, duration: selectedTotals.duration),
            wordCount: selectedTotals.words,
            sessionCount: selectedTotals.count
        )
    }

    private var statsUpdatedAtText: String {
        guard let statsSnapshotGeneratedAt else {
            return String(localized: "Stats not updated yet")
        }

        let formattedDate = statsSnapshotGeneratedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(format: String(localized: "Updated at %@"), formattedDate)
    }

    private var canViewInsights: Bool {
        hasLoadedStatsSnapshot && statsSummary.totalDuration >= Self.insightsUnlockDuration
    }

    private var shouldShowLockedInsightsState: Bool {
        hasLoadedStatsSnapshot && !canViewInsights
    }

    private var canViewPeakHours: Bool {
        hasLoadedStatsSnapshot &&
            selectedTotals.duration >= Self.peakHoursUnlockDuration &&
            selectedPeakHours.hasData
    }

    private var shouldLockPeakHours: Bool {
        hasLoadedStatsSnapshot && !canViewPeakHours
    }

    private var shouldRefreshStatsAfterMetricChange: Bool {
        !hasLoadedStatsSnapshot || statsSummary.totalCount < Self.automaticStatsRefreshMetricLimit
    }

    private var insightsActionTitle: LocalizedStringKey {
        canViewInsights ? "View Insights" : "Insights Locked"
    }

    private var insightsActionIcon: String {
        canViewInsights ? "chart.line.uptrend.xyaxis" : "lock.fill"
    }

    private var insightsActionHelp: String {
        if canViewInsights {
            return String(localized: "View dashboard insights")
        }

        return String(localized: "Continue using VoiceInk to unlock these stats.")
    }

    private var insightsActionAccessibilityLabel: String {
        canViewInsights ? "View insights" : "Insights locked"
    }

    private var accessibilityReminder: some View {
        DashboardAccessibilityReminder(onOpenSettings: openAccessibilitySettings)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(greetingEmoji)
                    .font(.system(size: 25))
                    .accessibilityHidden(true)

                Text("\(greetingText),")
                    .font(displayNameFont)
                    .foregroundStyle(AppTheme.Text.primary)
                    .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)

                displayNameView

                dismissingSpacer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            HStack(alignment: .top, spacing: 0) {
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var displayNameView: some View {
        if isEditingDisplayName {
            TextField("your name", text: displayNameBinding)
                .textFieldStyle(.plain)
                .font(displayNameFont)
                .foregroundStyle(AppTheme.Text.primary)
                .focused($isNameFieldFocused)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .padding(.horizontal, Self.displayNameHorizontalPadding)
                .padding(.vertical, 3)
                .background(AppTheme.Accent.fill)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.Accent.border, lineWidth: 1)
                )
                .onSubmit(finishEditingDisplayName)
                .onChange(of: isNameFieldFocused) { isFocused in
                    if !isFocused {
                        finishEditingDisplayName()
                    }
                }
        } else {
            Text(defaultedDisplayName)
                .font(displayNameFont)
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .help("Click to edit dashboard name")
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditingDisplayName)
        }
    }

    private var displayNameFont: Font {
        .system(size: Self.displayNameFontSize, weight: .bold, design: .rounded)
    }

    private var dismissingSpacer: some View {
        Spacer(minLength: 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
    }

    private func nameEditorDismissArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInsightsIfAvailable() {
        guard canViewInsights else {
            return
        }

        isInsightsViewPresented = true
    }

    private func openModelPerformancePanel() {
        isModelPerformancePanelPresented = true
    }

    private func openModelUsagePanel() {
        isModelUsagePanelPresented = true
    }

    @MainActor
    private func refreshDashboardStats() {
        scheduleDashboardStatsRefresh(allowSkipWhenFresh: false)
    }

    @MainActor
    private func scheduleDashboardStatsRefresh(
        debounce: Bool = false,
        allowSkipWhenFresh: Bool = false
    ) {
        dashboardStatsTask?.cancel()
        dashboardStatsLoadGeneration += 1

        let generation = dashboardStatsLoadGeneration
        let modelContainer = modelContext.container

        dashboardStatsTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: Self.statsRefreshDebounceNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
            }

            await loadDashboardStatsEfficiently(
                from: modelContainer,
                generation: generation,
                allowSkipWhenFresh: allowSkipWhenFresh
            )
        }
    }

    private func loadDashboardStatsEfficiently(
        from modelContainer: ModelContainer,
        generation: Int,
        allowSkipWhenFresh: Bool
    ) async {
        do {
            if allowSkipWhenFresh {
                let shouldRefreshAutomatically = SessionMetricMigrationService.shared.isRunning ||
                    DashboardStatsCache.shared.shouldRefreshSnapshotAutomatically()

                guard shouldRefreshAutomatically else {
                    return
                }
            }

            let shouldStartRefresh = await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return false
                }

                self.isDashboardStatsRefreshing = true
                return true
            }

            guard shouldStartRefresh else {
                return
            }

            let summary = try await DashboardStatsLoader.load(from: modelContainer)

            guard !Task.isCancelled else {
                await finishDashboardStatsRefresh(generation: generation)
                return
            }

            let shouldAcceptSummary = summary.totalCount > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return
                }

                self.isDashboardStatsRefreshing = false

                guard shouldAcceptSummary else {
                    return
                }

                self.statsSummary = summary
                let metadata = DashboardStatsCache.shared.update(summary)
                self.statsSnapshotGeneratedAt = metadata.generatedAt
                self.hasLoadedStatsSnapshot = true
            }
        } catch is CancellationError {
            await finishDashboardStatsRefresh(generation: generation)
        } catch {
            await finishDashboardStatsRefresh(generation: generation)
            logger.error("Error loading dashboard stats: \(error, privacy: .public)")
        }
    }

    private func finishDashboardStatsRefresh(generation: Int) async {
        await MainActor.run {
            guard generation == dashboardStatsLoadGeneration else {
                return
            }

            self.isDashboardStatsRefreshing = false
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var licenseStatusMessage: some View {
        switch licenseState {
        case .unlicensed:
            TrialMessageView(
                message: Text("Activate a license to continue using VoiceInk."),
                type: .licenseRequired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trial(let daysRemaining):
            TrialMessageView(
                message: Text(String(localized: "You have \(daysRemaining) days left in your trial")),
                type: daysRemaining <= 2 ? .warning : .info,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trialExpired:
            TrialMessageView(
                message: nil,
                type: .expired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .licensed:
            EmptyView()
        }
    }

    private var dashboardInsightsView: some View {
        DashboardInsightsView(
            selectedPeriod: $selectedInsightPeriod,
            productivityPoints: selectedProductivityPoints,
            peakHoursSummary: selectedPeakHours,
            isPeakHoursLocked: shouldLockPeakHours,
            timeSavedSummary: selectedTimeSavedSummary,
            modelUsage: selectedModelUsage,
            modelPerformanceSummaries: selectedModelPerformance,
            updatedAtText: statsUpdatedAtText,
            isRefreshingStats: isDashboardStatsRefreshing,
            onBack: { isInsightsViewPresented = false },
            onRefreshStats: refreshDashboardStats,
            onViewModelUsage: openModelUsagePanel,
            onViewModelPerformance: openModelPerformancePanel
        )
    }

    private var heroSection: some View {
        DashboardHeroCard(
            isLocked: shouldShowLockedInsightsState,
            headline: momentumHeadline,
            subtext: momentumSubtext,
            actionTitle: insightsActionTitle,
            actionIcon: insightsActionIcon,
            canViewInsights: canViewInsights,
            actionHelp: insightsActionHelp,
            actionAccessibilityLabel: insightsActionAccessibilityLabel,
            onViewInsights: openInsightsIfAvailable
        )
    }

    private var footerActionsView: some View {
        HStack(alignment: .center, spacing: 12) {
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
    private func footerActionLabel(icon: String, title: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            DashboardIconGlyph(systemName: icon, color: color, size: 13, frameSize: 16)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
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

    private var displayNameBinding: Binding<String> {
        Binding(
            get: {
                isEditingDisplayName ? displayNameDraft : defaultedDisplayName
            },
            set: { newValue in
                displayNameDraft = String(newValue.prefix(32))
            }
        )
    }

    private var displayNameFieldWidth: CGFloat {
        let name = isEditingDisplayName ? displayNameDraft : defaultedDisplayName
        let measuredWidth = (name as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: Self.displayNameFontSize, weight: Self.displayNameFontWeight)]
        ).width
        return min(
            max(measuredWidth + (Self.displayNameHorizontalPadding * 2) + 6, Self.displayNameMinWidth),
            Self.displayNameMaxWidth
        )
    }

    private var defaultedDisplayName: String {
        let storedName = sanitizedDisplayName(dashboardDisplayName)
        return storedName.isEmpty ? systemDisplayName : storedName
    }

    private var systemDisplayName: String {
        Self.systemAccountFirstName() ?? Self.fallbackDisplayName
    }

    private func beginEditingDisplayName() {
        displayNameDraft = defaultedDisplayName
        isEditingDisplayName = true
        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func finishEditingDisplayName() {
        dashboardDisplayName = String(sanitizedDisplayName(displayNameDraft).prefix(32))
        isEditingDisplayName = false
        isNameFieldFocused = false

        if sanitizedDisplayName(dashboardDisplayName).isEmpty {
            dashboardDisplayName = ""
        }
    }

    private func dismissDisplayNameEditorIfNeeded() {
        if isEditingDisplayName {
            finishEditingDisplayName()
        }
    }

    private func sanitizedDisplayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func systemAccountFirstName() -> String? {
        let fullName = sanitizedSystemName(NSFullUserName())

        if let fullName,
           let givenName = PersonNameComponentsFormatter().personNameComponents(from: fullName)?.givenName,
           !givenName.isEmpty {
            return givenName
        }

        if let fullName,
           let firstName = fullName.split(whereSeparator: \.isWhitespace).first {
            return String(firstName)
        }

        if let shortName = sanitizedSystemName(NSUserName()) {
            return shortName
                .split(separator: ".")
                .first
                .map(String.init) ?? shortName
        }

        return nil
    }

    private static func sanitizedSystemName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return String(localized: "Good morning")
        case 12..<17:
            return String(localized: "Good afternoon")
        case 17..<24:
            return String(localized: "Good evening")
        default:
            return String(localized: "Hi")
        }
    }

    private var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "☀️"
        case 12..<17:
            return "👋"
        case 17..<24:
            return "🌙"
        default:
            return "👋"
        }
    }

    private var headerSubtitle: String {
        guard hasLoadedStatsSnapshot else {
            return String(localized: "Pulling together your VoiceInk activity.")
        }

        guard statsSummary.totalCount > 0 else {
            return String(localized: "Record your first session to start building momentum.")
        }

        if statsSummary.recentSevenDayCount >= 5 {
            return String(localized: "You’re on a roll this week. Keep the momentum going.")
        }

        if statsSummary.recentSevenDayCount > 0 {
            return String(localized: "You’re building momentum this week. Keep it going.")
        }

        return String(localized: "Your data is not ready yet. Keep the momentum going.")
    }

    private var momentumHeadline: DashboardHeroHeadline {
        guard hasLoadedStatsSnapshot else {
            return .calculatingProgress
        }

        guard statsSummary.totalCount > 0 else {
            return .startRecordingProgress
        }

        return .savedTime(formattedAllTimeSaved)
    }

    private var momentumSubtext: String {
        guard hasLoadedStatsSnapshot else {
            return String(localized: "Your word count and benchmark will appear here.")
        }

        guard statsSummary.totalCount > 0 else {
            return String(localized: "Your first milestone appears after one session.")
        }

        return formattedProgressBenchmarkText
    }

    // MARK: - Computed Metrics

    private var allTimeSaved: TimeInterval {
        DashboardTimeSaving.timeSaved(words: statsSummary.totalWords, duration: statsSummary.totalDuration)
    }

    private var formattedAllTimeSaved: String {
        Formatters.formattedSavedTime(allTimeSaved)
    }

    private var formattedAllTimeWords: String {
        let words = Formatters.formattedCompactNumber(statsSummary.totalWords)
        let wordUnit = statsSummary.totalWords == 1 ? String(localized: "word") : String(localized: "words")
        return String(localized: "\(words) \(wordUnit)")
    }

    private var formattedProgressBenchmarkText: String {
        switch DashboardProgressBenchmark.equivalence(for: statsSummary.totalWords) {
        case .matched(let title):
            return String(localized: "Dictated \(formattedAllTimeWords), equivalent to \(title).")
        case .repeated(let title, let count):
            return String(localized: "Dictated \(formattedAllTimeWords), equivalent to \(title) \(formattedBenchmarkMultiple(count)).")
        case .remaining(let words, let title):
            guard words > 0, !title.isEmpty else {
                return String(localized: "Dictated \(formattedAllTimeWords).")
            }

            let remainingWords = Formatters.formattedNumber(words)
            return String(localized: "Dictated \(formattedAllTimeWords), \(remainingWords) words from \(title).")
        }
    }

    private func formattedBenchmarkMultiple(_ count: Int) -> String {
        if count == 2 {
            return String(localized: "twice")
        }

        return String(localized: "\(Formatters.formattedNumber(count)) times")
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

private struct DashboardAmbientBackground: View {
    var body: some View {
        Color.clear
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
