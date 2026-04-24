import Foundation
import SwiftData

enum MeetingStageStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case done
    case failed
}

@Model
final class Meeting {
    var id: UUID
    var title: String
    var subtitle: String
    var audioFilePath: String
    var durationSec: Double
    var createdAt: Date

    var transcriptionModelName: String?
    var summaryTldr: String?
    var summaryKeyPoints: [String]
    var summaryActionItems: [String]

    // Raw String storage keeps SwiftData schema compatible with data written under the original
    // `String` field type. Access via the typed `*Stage` accessors below, not directly.
    var transcriptionStatus: String
    var diarizationStatus: String
    var summaryStatus: String

    var transcriptionStage: MeetingStageStatus {
        get { MeetingStageStatus(rawValue: transcriptionStatus) ?? .pending }
        set { transcriptionStatus = newValue.rawValue }
    }
    var diarizationStage: MeetingStageStatus {
        get { MeetingStageStatus(rawValue: diarizationStatus) ?? .pending }
        set { diarizationStatus = newValue.rawValue }
    }
    var summaryStage: MeetingStageStatus {
        get { MeetingStageStatus(rawValue: summaryStatus) ?? .pending }
        set { summaryStatus = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Speaker.meeting)
    var speakers: [Speaker]

    @Relationship(deleteRule: .cascade, inverse: \Segment.meeting)
    var segments: [Segment]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        audioFilePath: String,
        durationSec: Double,
        createdAt: Date = Date(),
        transcriptionModelName: String? = nil,
        summaryTldr: String? = nil,
        summaryKeyPoints: [String] = [],
        summaryActionItems: [String] = [],
        transcriptionStatus: MeetingStageStatus = .pending,
        diarizationStatus: MeetingStageStatus = .pending,
        summaryStatus: MeetingStageStatus = .pending,
        speakers: [Speaker] = [],
        segments: [Segment] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.audioFilePath = audioFilePath
        self.durationSec = durationSec
        self.createdAt = createdAt
        self.transcriptionModelName = transcriptionModelName
        self.summaryTldr = summaryTldr
        self.summaryKeyPoints = summaryKeyPoints
        self.summaryActionItems = summaryActionItems
        self.transcriptionStatus = transcriptionStatus.rawValue
        self.diarizationStatus = diarizationStatus.rawValue
        self.summaryStatus = summaryStatus.rawValue
        self.speakers = speakers
        self.segments = segments
    }
}

@Model
final class Speaker {
    var id: UUID
    var diarizerLabel: String
    var displayName: String
    var meeting: Meeting?

    init(
        id: UUID = UUID(),
        diarizerLabel: String,
        displayName: String,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.diarizerLabel = diarizerLabel
        self.displayName = displayName
        self.meeting = meeting
    }
}

@Model
final class Segment {
    var id: UUID
    var startSec: Double
    var endSec: Double
    var text: String
    var speaker: Speaker?
    var meeting: Meeting?

    init(
        id: UUID = UUID(),
        startSec: Double,
        endSec: Double,
        text: String,
        speaker: Speaker? = nil,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
        self.speaker = speaker
        self.meeting = meeting
    }
}
