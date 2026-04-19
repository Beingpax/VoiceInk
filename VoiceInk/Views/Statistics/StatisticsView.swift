import SwiftUI
import SwiftData
import os

struct StatisticsView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.VoiceInk", category: "StatisticsView")
    @Environment(\.modelContext) private var modelContext

    @State private var totalCount: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoading: Bool = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading statistics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if totalCount == 0 {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        heroSection
                        metricsSection
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 32)
                }
                .background(Color(.windowBackgroundColor))
            }
        }
        .task {
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionCreated)) { _ in
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionCompleted)) { _ in
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDeleted)) { _ in
            scheduleReload()
        }
        .onDisappear {
            loadTask?.cancel()
        }
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
                value: StatisticsFormatters.formattedNumber(totalWords),
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
                value: StatisticsFormatters.formattedNumber(totalKeystrokesSaved),
                detail: "fewer keystrokes",
                color: .orange
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.secondary)
            Text("No Transcriptions Yet")
                .font(.title3.weight(.semibold))
            Text("Statistics will appear here after your first recording.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Derived metrics

    private static let assumedTypingWordsPerMinute: Double = 35
    private static let averageKeystrokesPerWord: Double = 5

    private var estimatedTypingTime: TimeInterval {
        let estimatedMinutes = Double(totalWords) / Self.assumedTypingWordsPerMinute
        return estimatedMinutes * 60
    }

    private var timeSaved: TimeInterval {
        max(estimatedTypingTime - totalDuration, 0)
    }

    private var averageWordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    private var totalKeystrokesSaved: Int {
        Int(Double(totalWords) * Self.averageKeystrokesPerWord)
    }

    private var formattedTimeSaved: String {
        StatisticsFormatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings coming soon")
    }

    private var heroSubtitle: String {
        guard totalCount > 0 else {
            return "Your VoiceInk journey starts with your first recording."
        }
        let wordsText = StatisticsFormatters.formattedNumber(totalWords)
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

    // MARK: - Data loading

    private func scheduleReload() {
        loadTask?.cancel()
        loadTask = Task { await reload() }
    }

    private func reload() async {
        await MainActor.run { self.isLoading = true }

        let backgroundContext = ModelContext(modelContext.container)

        do {
            let completedFilter = #Predicate<Transcription> { $0.transcriptionStatus == "completed" }
            let count = try backgroundContext.fetchCount(FetchDescriptor<Transcription>(predicate: completedFilter))

            guard !Task.isCancelled else {
                await MainActor.run { self.isLoading = false }
                return
            }

            var descriptor = FetchDescriptor<Transcription>(predicate: completedFilter)
            descriptor.propertiesToFetch = [\.text, \.duration]

            var words = 0
            var duration: TimeInterval = 0
            try backgroundContext.enumerate(descriptor) { transcription in
                words += transcription.text.split(whereSeparator: \.isWhitespace).count
                duration += transcription.duration
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isLoading = false }
                return
            }

            await MainActor.run {
                self.totalCount = count
                self.totalWords = words
                self.totalDuration = duration
                self.isLoading = false
            }
        } catch {
            logger.error("Error loading statistics: \(error.localizedDescription, privacy: .public)")
            await MainActor.run { self.isLoading = false }
        }
    }
}

private enum StatisticsFormatters {
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
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formattedDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "–") -> String {
        guard interval > 0 else { return fallback }
        durationFormatter.unitsStyle = style
        durationFormatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return durationFormatter.string(from: interval) ?? fallback
    }
}
