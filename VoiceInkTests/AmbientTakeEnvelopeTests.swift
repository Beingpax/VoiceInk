import Testing

@testable import VoiceInk

struct AmbientTakeEnvelopeTests {

    @Test func foldsToTheRequestedSize() {
        let samples = (0..<1_000).map { Double($0) / 1_000 }
        #expect(AmbientTakeEnvelope.downsample(samples, to: 110).count == 110)
    }

    @Test func aShortTakeIsLeftAlone() {
        // Fewer samples than buckets means there is nothing to fold — stretching them would invent
        // detail the take does not have.
        let samples = [0.2, 0.5, 0.9]
        #expect(AmbientTakeEnvelope.downsample(samples, to: 110) == samples)
    }

    @Test func emptyStaysEmpty() {
        #expect(AmbientTakeEnvelope.downsample([], to: 110).isEmpty)
    }

    @Test func zeroBucketsIsEmptyRatherThanACrash() {
        #expect(AmbientTakeEnvelope.downsample([0.1, 0.2], to: 0).isEmpty)
    }

    @Test func peaksSurviveTheFold() {
        // The whole reason buckets take the max: one shouted word in a quiet minute has to still be
        // visible in the replay. Averaging this bucket would give 0.19 and the spike would vanish.
        var samples = [Double](repeating: 0.1, count: 1_000)
        samples[500] = 1.0

        let folded = AmbientTakeEnvelope.downsample(samples, to: 10)
        #expect(folded.max() == 1.0)
        #expect(folded.filter { $0 == 1.0 }.count == 1)
    }

    @Test func orderIsPreserved() {
        // The crest lays the take out from the notch outward, so the fold must not reorder it —
        // otherwise the replay sweep would show the take shuffled.
        let ramp = (0..<1_000).map { Double($0) / 1_000 }
        let folded = AmbientTakeEnvelope.downsample(ramp, to: 20)

        #expect(zip(folded, folded.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(folded.first! < folded.last!)
    }

    @Test func everyBucketIsCovered() {
        // No sample may be skipped and no bucket left unwritten, or the replay would have gaps
        // where the take was silent-looking but was not.
        let samples = (0..<997).map { _ in 0.4 }
        let folded = AmbientTakeEnvelope.downsample(samples, to: 64)
        #expect(folded.count == 64)
        #expect(folded.allSatisfy { $0 == 0.4 })
    }
}
