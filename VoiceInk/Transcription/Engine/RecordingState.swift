import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case transcribing
    case enhancing
    case busy
}
