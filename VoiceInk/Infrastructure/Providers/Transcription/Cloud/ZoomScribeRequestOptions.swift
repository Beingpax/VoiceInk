import Foundation

enum ZoomScribeRequestOptions {
    /// Set by the caller for the duration of one transcription request. Carries the mode's Zoom Polishing choice.
    @TaskLocal static var textPolishingRequested: Bool = false
}
