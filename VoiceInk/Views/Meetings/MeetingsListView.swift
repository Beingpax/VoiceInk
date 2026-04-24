import SwiftUI
import SwiftData
import AppKit
import OSLog
import UniformTypeIdentifiers

struct MeetingsListView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingsListView")
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pipeline: MeetingPipeline
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @State private var isDropTargeted = false
    @State private var searchQuery: String = ""

    private var filteredMeetings: [Meeting] {
        guard !searchQuery.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if meetings.isEmpty {
                    emptyStateView
                } else if filteredMeetings.isEmpty {
                    noResultsView
                } else {
                    meetingListContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    NativeSearchField(text: $searchQuery, placeholder: "Search meetings")
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: seedDemoMeetings) {
                            Label("Seed Demo Meetings", systemImage: "wand.and.stars")
                        }
                        Button(role: .destructive, action: clearAllMeetings) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("More options")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openImportPanel) {
                        Label("Import Meeting", systemImage: "plus")
                    }
                    .help("Import a meeting audio or video file")
                }
            }
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
        }
    }

    // MARK: - Empty / No-results State

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No meetings match \"\(searchQuery)\"")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.wave.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No meetings yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Import a recording or seed demo data")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - List

    private var meetingListContent: some View {
        List(filteredMeetings) { meeting in
            NavigationLink(value: meeting) {
                MeetingRowView(meeting: meeting)
            }
        }
        .listStyle(.inset)
        .onDrop(of: [.fileURL, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Actions

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.message = "Select audio or video files to import"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { _ = await pipeline.importMeeting(from: url) }
            }
        }
    }

    private func clearAllMeetings() {
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { _ = await pipeline.importMeeting(from: url) }
                }
            }
        }
        return true
    }

    // MARK: - Seed Demo Data

    private func seedDemoMeetings() {
        let now = Date()

        // Meeting 1: Q2 Product Review — all done
        let m1 = Meeting(
            title: "Q2 Product Review",
            subtitle: "Roadmap alignment for design + engineering",
            audioFilePath: "",
            durationSec: 2730,
            createdAt: now.addingTimeInterval(-2 * 3600),
            summaryTldr: "Design proposes wallet v2 ship in Q3; engineering pushes back on auth redesign; compromise: soft-launch wallet with existing auth.",
            summaryKeyPoints: ["Wallet v2 target: Q3 soft-launch", "Auth redesign deferred to Q4", "Hiring: +2 iOS eng by June"],
            summaryActionItems: ["Sarah drafts wallet v2 scope doc by Fri", "Eng team to ship prototype by May 15", "HR posts 2 iOS roles this week"],
            transcriptionStatus: .done,
            diarizationStatus: .done,
            summaryStatus: .done
        )
        modelContext.insert(m1)

        let s1a = Speaker(diarizerLabel: "speaker_0", displayName: "Sarah", meeting: m1)
        let s1b = Speaker(diarizerLabel: "speaker_1", displayName: "Mike", meeting: m1)
        modelContext.insert(s1a)
        modelContext.insert(s1b)

        let m1Segments: [(Double, Double, String, Speaker)] = [
            (0, 14, "So the main thing we're tracking this quarter is the wallet feature rollout.", s1a),
            (15, 30, "Right, and my concern is the timeline. Auth redesign alone is a six-week effort.", s1b),
            (31, 50, "I hear you. What if we soft-launch wallet with the existing auth and defer the redesign to Q4?", s1a),
            (51, 68, "That could work. We'd still need a prototype ready by mid-May to feel confident.", s1b),
            (69, 85, "Agreed. I'll write up the scope doc this week so everyone's aligned before we kick off.", s1a),
            (86, 105, "Cool. On hiring — we talked about two iOS engineers. Has HR posted the roles?", s1b),
            (106, 122, "Not yet. I'll ping them today. We really need those seats filled before Q3 ramp.", s1a),
            (123, 140, "Sounds good. Let's make sure the job specs reflect the wallet work specifically.", s1b)
        ]
        for (start, end, text, spk) in m1Segments {
            let seg = Segment(startSec: start, endSec: end, text: text, speaker: spk, meeting: m1)
            modelContext.insert(seg)
        }

        // Meeting 2: 1:1 with Priya — summary failed
        let m2 = Meeting(
            title: "Weekly 1:1 with Priya",
            subtitle: "Career growth + current blockers",
            audioFilePath: "",
            durationSec: 1820,
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86400),
            transcriptionStatus: .done,
            diarizationStatus: .done,
            summaryStatus: .failed
        )
        modelContext.insert(m2)

        let s2a = Speaker(diarizerLabel: "speaker_0", displayName: "Ramdan", meeting: m2)
        let s2b = Speaker(diarizerLabel: "speaker_1", displayName: "Priya", meeting: m2)
        modelContext.insert(s2a)
        modelContext.insert(s2b)

        let m2Segments: [(Double, Double, String, Speaker)] = [
            (0, 18, "Hey Priya, how's the sprint going? You mentioned some blockers last week.", s2a),
            (19, 42, "Yeah, it's been rough. The API integration keeps timing out and I'm not sure if it's our infra or theirs.", s2b),
            (43, 65, "Let's loop in platform on that. On the career side — I know you wanted to talk about the senior track.", s2a),
            (66, 90, "Exactly. I feel like I've been doing senior-level work for a while but the title hasn't caught up.", s2b),
            (91, 112, "I agree with that read. I want to put together a case for your promo in the next review cycle.", s2a)
        ]
        for (start, end, text, spk) in m2Segments {
            let seg = Segment(startSec: start, endSec: end, text: text, speaker: spk, meeting: m2)
            modelContext.insert(seg)
        }

        // Meeting 3: Design critique — all running (in-progress)
        let m3 = Meeting(
            title: "Design critique — onboarding flow",
            subtitle: "",
            audioFilePath: "",
            durationSec: 3400,
            createdAt: now.addingTimeInterval(-30 * 60),
            transcriptionStatus: .running,
            diarizationStatus: .running,
            summaryStatus: .running
        )
        modelContext.insert(m3)

        try? modelContext.save()
    }
}

// MARK: - Meeting Row

private struct MeetingRowView: View {
    let meeting: Meeting

    private var isInProgress: Bool {
        meeting.transcriptionStage == .running
            || meeting.diarizationStage == .running
            || meeting.summaryStage == .running
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if !meeting.subtitle.isEmpty {
                    Text(meeting.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(Self.relativeTime(meeting.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    Text(formattedDuration(meeting.durationSec))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isInProgress {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relativeTime(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Native Search Field

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }
}
