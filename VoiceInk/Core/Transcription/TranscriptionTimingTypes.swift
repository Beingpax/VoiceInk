import Foundation

/// Timing of a single character within a word, interpolated from the word's timing.
struct CharTiming: Codable, Sendable, Equatable {
    let char: String
    let start: TimeInterval
    let end: TimeInterval
}

/// A transcribed word with its position on the audio timeline.
struct WordTiming: Codable, Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String?

    /// Char-level timings are approximated by linear interpolation across the
    /// word's duration — engines only emit token/word-level timestamps.
    func interpolatedCharTimings() -> [CharTiming] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        let step = (end - start) / Double(characters.count)
        return characters.enumerated().map { index, character in
            CharTiming(
                char: String(character),
                start: start + Double(index) * step,
                end: start + Double(index + 1) * step
            )
        }
    }
}

/// A contiguous run of words attributed to a single speaker.
struct SpeakerUtterance: Codable, Sendable, Equatable {
    var speaker: String
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// A span of speech attributed to one speaker by the diarizer.
struct SpeakerSegment: Sendable, Equatable {
    let speakerId: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Transcription output that can carry word-level timing alongside the plain text.
/// Engines without timing support return `words == nil`.
struct DetailedTranscriptionResult: Sendable {
    var text: String
    var words: [WordTiming]?
}

/// The two channels of a stereo recording as separate 16kHz sample arrays.
struct StereoChannelSamples: Sendable {
    let left: [Float]
    let right: [Float]
}

enum SpeakerAlignment {
    /// Assigns a speaker to each word by maximum temporal overlap with the
    /// diarization segments, falling back to the nearest segment for words
    /// that fall inside silence gaps. Same strategy as WhisperX's
    /// `assign_word_speakers`.
    static func assignSpeakers(words: [WordTiming], segments: [SpeakerSegment]) -> [WordTiming] {
        guard !segments.isEmpty else { return words }
        return words.map { word in
            var word = word
            var bestSpeaker: String?
            var bestOverlap: TimeInterval = 0
            var nearestSpeaker: String?
            var nearestDistance: TimeInterval = .greatestFiniteMagnitude

            for segment in segments {
                let overlap = min(word.end, segment.end) - max(word.start, segment.start)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = segment.speakerId
                }
                let distance = overlap > 0 ? 0 : max(segment.start - word.end, word.start - segment.end)
                if distance < nearestDistance {
                    nearestDistance = distance
                    nearestSpeaker = segment.speakerId
                }
            }

            // Nearest-segment fallback only within a short gap; distant words keep
            // speaker == nil and inherit their neighbor's speaker during grouping,
            // so silence stretches can't drag a far-away speaker across the text.
            if bestSpeaker == nil, nearestDistance > 2.0 {
                nearestSpeaker = nil
            }
            word.speaker = bestSpeaker ?? nearestSpeaker
            return word
        }
    }

    /// Utterances for dual-channel transcription: each speaker's words are
    /// grouped into continuous runs (split on pauses longer than `maxGap`)
    /// independently, then the runs are ordered by start time. Unlike
    /// `utterances(from:)`, overlapping speech stays as coherent blocks per
    /// speaker instead of interleaving word by word.
    static func channelUtterances(from words: [WordTiming], maxGap: TimeInterval = 1.5) -> [SpeakerUtterance] {
        var utterances: [SpeakerUtterance] = []
        let bySpeaker = Dictionary(grouping: words) { $0.speaker ?? "Unknown" }
        for (speaker, speakerWords) in bySpeaker {
            let sorted = speakerWords.sorted { $0.start < $1.start }
            var current: SpeakerUtterance?
            for word in sorted {
                if var utterance = current, word.start - utterance.end <= maxGap {
                    utterance.text += " " + word.text
                    utterance.end = word.end
                    current = utterance
                } else {
                    if let utterance = current {
                        utterances.append(utterance)
                    }
                    current = SpeakerUtterance(speaker: speaker, text: word.text, start: word.start, end: word.end)
                }
            }
            if let utterance = current {
                utterances.append(utterance)
            }
        }
        return utterances.sorted { ($0.start, $0.speaker) < ($1.start, $1.speaker) }
    }

    /// Groups consecutive words with the same speaker into utterances, splitting
    /// on pauses longer than `maxGap` so silence stays visible between blocks.
    /// Words without a speaker inherit the previous utterance's speaker.
    static func utterances(from words: [WordTiming], maxGap: TimeInterval = 1.5) -> [SpeakerUtterance] {
        var utterances: [SpeakerUtterance] = []
        for word in words {
            let speaker = word.speaker ?? utterances.last?.speaker ?? "Unknown"
            if var current = utterances.last, current.speaker == speaker, word.start - current.end <= maxGap {
                current.text += " " + word.text
                current.end = word.end
                utterances[utterances.count - 1] = current
            } else {
                utterances.append(
                    SpeakerUtterance(speaker: speaker, text: word.text, start: word.start, end: word.end)
                )
            }
        }
        return utterances
    }
}
