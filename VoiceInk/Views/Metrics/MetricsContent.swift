import SwiftUI
import SwiftData
import os

struct MetricsContent: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.VoiceInk", category: "MetricsContent")
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState

    @State private var totalCount: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoadingMetrics: Bool = true
    @State private var metricsTask: Task<Void, Never>?
    @State private var isModelStatsPanelPresented = false

    var body: some View {
        Group {
            if totalCount == 0 && !isLoadingMetrics {
                emptyStateView
            } else if isLoadingMetrics {
                ProgressView("Loading metrics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            heroSection
                            metricsSection
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
                        .padding(.horizontal, 32)
                    }
                    .background(Color(.windowBackgroundColor))
                }
            }
        }
        .task {
            await loadMetricsEfficiently()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onDisappear {
            metricsTask?.cancel()
        }
        .overlay {
            Color.black.opacity(isModelStatsPanelPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isModelStatsPanelPresented)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
        }
        .overlay(alignment: .trailing) {
            if isModelStatsPanelPresented {
                ModelPerformancePanel {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                .ignoresSafeArea()
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
    }
    
    private func loadMetricsEfficiently() async {
        await MainActor.run {
            self.isLoadingMetrics = true
        }

        let modelContainer = modelContext.container

        let backgroundContext = ModelContext(modelContainer)

        do {
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoadingMetrics = false
                }
                return
            }

            let count = try backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoadingMetrics = false
                }
                return
            }

            var descriptor = FetchDescriptor<SessionMetric>()
            descriptor.propertiesToFetch = [\.wordCount, \.audioDuration]

            var words = 0
            var duration: TimeInterval = 0

            try backgroundContext.enumerate(descriptor) { metric in
                words += metric.wordCount
                duration += metric.audioDuration
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isLoadingMetrics = false }
                return
            }

            await MainActor.run {
                self.totalCount = count
                self.totalWords = words
                self.totalDuration = duration
                // Stay in loading state if migration is still running and no data yet —
                // sessionMetricsDidChange will trigger a reload when it finishes.
                if count > 0 || !SessionMetricMigrationService.shared.isRunning {
                    self.isLoadingMetrics = false
                }
            }
        } catch {
            logger.error("Error loading metrics: \(error.localizedDescription, privacy: .public)")
            await MainActor.run { self.isLoadingMetrics = false }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.secondary)
            Text("No Recorder Sessions Yet")
                .font(.title3.weight(.semibold))
            Text("Start your first recording to unlock value insights.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                
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
    
    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: "\(totalCount)",
                detail: "VoiceInk sessions completed",
                color: .purple
            )

            MetricCard(
                icon: "text.alignleft",
                title: "Words Dictated",
                value: Formatters.formattedNumber(totalWords),
                detail: "words generated",
                color: Color(nsColor: .controlAccentColor)
            )
            
            MetricCard(
                icon: "speedometer",
                title: "Words Per Minute",
                value: averageWordsPerMinute > 0
                    ? String(format: "%.1f", averageWordsPerMinute)
                    : "–",
                detail: "VoiceInk vs. typing by hand",
                color: .yellow
            )
            
            MetricCard(
                icon: "keyboard.fill",
                title: "Keystrokes Saved",
                value: Formatters.formattedNumber(totalKeystrokesSaved),
                detail: "fewer keystrokes",
                color: .orange
            )
        }
    }

    private var footerActionsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = true }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge")
                    Text("Model Performance")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.thinMaterial))
            }
            .buttonStyle(.plain)
            .help("View transcription and enhancement model performance")
            CopySystemInfoButton()
        }
    }
    
    private var formattedTimeSaved: String {
        let formatted = Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings coming soon")
        return formatted
    }
    
    private var heroSubtitle: String {
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
                Color(nsColor: .controlAccentColor),
                Color(nsColor: .controlAccentColor).opacity(0.85),
                Color(nsColor: .controlAccentColor).opacity(0.7)
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

private struct CopySystemInfoButton: View {
    @State private var isCopied: Bool = false

    var body: some View {
        Button(action: {
            copySystemInfo()
        }) {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .rotationEffect(.degrees(isCopied ? 360 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)

                Text(isCopied ? "Copied!" : "Copy System Info")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .scaleEffect(isCopied ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCopied = false
            }
        }
    }
}
