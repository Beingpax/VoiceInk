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

/// Deterministic speaker separation for recordings that carry one participant
/// per stereo channel (standard in telephony/call-center audio): each 100ms
/// frame is attributed to the channel with more energy, no ML involved.
enum ChannelDiarizer {
    static func segments(from channels: StereoChannelSamples, sampleRate: Double = 16000) -> [SpeakerSegment] {
        let frameSize = Int(sampleRate * 0.1)
        let frameDuration = Double(frameSize) / sampleRate
        let frameCount = min(channels.left.count, channels.right.count) / frameSize
        guard frameCount > 0 else { return [] }

        func rms(_ samples: [Float], frame: Int) -> Float {
            let start = frame * frameSize
            var sum: Float = 0
            for i in start..<(start + frameSize) {
                sum += samples[i] * samples[i]
            }
            return (sum / Float(frameSize)).squareRoot()
        }

        var leftRMS: [Float] = []
        var rightRMS: [Float] = []
        leftRMS.reserveCapacity(frameCount)
        rightRMS.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            leftRMS.append(rms(channels.left, frame: frame))
            rightRMS.append(rms(channels.right, frame: frame))
        }

        // Speech/silence threshold adapted to the recording's level, clamped so
        // neither silence-only nor loud recordings break it.
        let sortedRMS = (leftRMS + rightRMS).sorted()
        let p90 = sortedRMS[Int(Double(sortedRMS.count - 1) * 0.9)]
        let threshold = max(0.008, min(0.05, p90 * 0.15))

        // 0 = left, 1 = right, nil = silence; each active frame goes to the
        // louder channel.
        var frameSpeaker: [Int?] = []
        frameSpeaker.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let l = leftRMS[frame]
            let r = rightRMS[frame]
            if l < threshold && r < threshold {
                frameSpeaker.append(nil)
            } else {
                frameSpeaker.append(l >= r ? 0 : 1)
            }
        }

        // Merge active frames into segments, bridging short pauses (≤1s) by the
        // same speaker so segments don't fragment on every breath.
        var segments: [SpeakerSegment] = []
        var currentSpeaker: Int?
        var segmentStart: TimeInterval = 0
        var segmentEnd: TimeInterval = 0

        func flush() {
            if let speaker = currentSpeaker, segmentEnd - segmentStart >= 0.2 {
                segments.append(
                    SpeakerSegment(speakerId: "\(speaker + 1)", start: segmentStart, end: segmentEnd)
                )
            }
        }

        for (frame, speaker) in frameSpeaker.enumerated() {
            guard let speaker else { continue }
            let time = Double(frame) * frameDuration
            if speaker == currentSpeaker, time - segmentEnd <= 1.0 {
                segmentEnd = time + frameDuration
            } else {
                flush()
                currentSpeaker = speaker
                segmentStart = time
                segmentEnd = time + frameDuration
            }
        }
        flush()
        return segments
    }
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
        return utterances.sorted { $0.start < $1.start }
    }

    /// Groups consecutive words with the same speaker into utterances.
    /// Words without a speaker inherit the previous utterance's speaker.
    static func utterances(from words: [WordTiming]) -> [SpeakerUtterance] {
        var utterances: [SpeakerUtterance] = []
        for word in words {
            let speaker = word.speaker ?? utterances.last?.speaker ?? "Unknown"
            if var current = utterances.last, current.speaker == speaker {
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
