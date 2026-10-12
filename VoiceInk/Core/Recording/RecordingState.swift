import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}
