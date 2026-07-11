//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
@testable import VoiceInk

struct VoiceInkTests {
    @Test func preferredInputChannelsExcludeLoopbackChannels() {
        let selection = AudioInputChannelSelection.resolve(
            deviceChannelCount: 4,
            preferredStereoChannels: [1, 2]
        )

        #expect(selection.deviceChannelIndices == [0, 1])
    }

    @Test func monoInputUsesOneChannel() {
        let selection = AudioInputChannelSelection.resolve(
            deviceChannelCount: 1,
            preferredStereoChannels: [1, 1]
        )

        #expect(selection.deviceChannelIndices == [0])
    }

    @Test func missingPreferredChannelsFallBackToFirstTwoInputs() {
        let selection = AudioInputChannelSelection.resolve(
            deviceChannelCount: 4,
            preferredStereoChannels: nil
        )

        #expect(selection.deviceChannelIndices == [0, 1])
    }

    @Test func invalidPreferredChannelsFallBackToFirstTwoInputs() {
        let selection = AudioInputChannelSelection.resolve(
            deviceChannelCount: 4,
            preferredStereoChannels: [0, 5]
        )

        #expect(selection.deviceChannelIndices == [0, 1])
    }
}
