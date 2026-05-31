import Foundation
import os

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy

    /// Returns true if `next` is a valid state to transition to from `self`.
    func canTransition(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.idle, .starting),
             (.idle, .busy),
             (.starting, .recording),
             (.starting, .idle),
             (.recording, .transcribing),
             (.recording, .idle),
             (.transcribing, .enhancing),
             (.transcribing, .idle),
             (.enhancing, .idle),
             (.busy, .idle):
            return true
        case (let from, let to) where from == to:
            return true // no-op same-state is harmless
        default:
            return false
        }
    }
}
