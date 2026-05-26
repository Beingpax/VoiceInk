import Testing
@testable import VoiceInk

struct AlienWaveformProfileTests {
    @Test func activeSamplesAreDenseAsymmetricAndBounded() {
        let profile = AlienWaveformProfile(minHeight: 5, maxHeight: 45)
        let samples = profile.samples(
            audioPower: 0.72,
            time: 18.25,
            count: 49,
            isActive: true
        )

        #expect(samples.count == 49)
        let allSamplesAreBounded = samples.allSatisfy { sample in
            let upperIsBounded = sample.upperHeight >= 5 && sample.upperHeight <= 45
            let lowerIsBounded = sample.lowerHeight >= 5 && sample.lowerHeight <= 45
            return upperIsBounded && lowerIsBounded
        }
        #expect(allSamplesAreBounded)

        let roundedHeights = Set(samples.map { Int($0.totalHeight.rounded()) })
        #expect(roundedHeights.count >= 14)

        let asymmetries = samples.map { abs($0.upperHeight - $0.lowerHeight) }
        let strongestAsymmetry = asymmetries.max()!
        #expect(strongestAsymmetry > 4)

        let strongestDrift = samples.map { abs($0.xDrift) }.max()!
        #expect(strongestDrift > 12)

        let tallInteriorSamples = samples.enumerated().filter { index, sample in
            index > 4 && index < samples.count - 5 && sample.totalHeight > 34
        }
        #expect(tallInteriorSamples.count >= 3)
    }

    @Test func defaultSamplesFavorReadableOrganicSpacing() {
        let profile = AlienWaveformProfile(minHeight: 5, maxHeight: 45)
        let samples = profile.samples(audioPower: 0.72, time: 2.4, isActive: true)

        #expect(samples.count == 37)
    }

    @Test func restingSamplesStaySubtleButOrganic() {
        let profile = AlienWaveformProfile(minHeight: 5, maxHeight: 45)
        let samples = profile.samples(
            audioPower: 0,
            time: 7.5,
            count: 49,
            isActive: false
        )

        #expect(samples.count == 49)
        let restingSamplesAreSubtle = samples.allSatisfy { sample in
            sample.totalHeight >= 6 && sample.totalHeight <= 22
        }
        #expect(restingSamplesAreSubtle)

        let asymmetries = samples.map { abs($0.upperHeight - $0.lowerHeight) }
        let strongestAsymmetry = asymmetries.max()!
        #expect(strongestAsymmetry > 1.5)
    }
}
