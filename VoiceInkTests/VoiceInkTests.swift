//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import AppKit
@testable import VoiceInk

@MainActor
struct VoiceInkTests {

    @Test func miniRecorderDigitShortcutsUseDefaultModifiersWithoutHeldRecordingModifiers() {
        #expect(MiniRecorderShortcutManager.promptDigitModifierFlags(ambientModifierFlags: []) == [.command])
        #expect(MiniRecorderShortcutManager.powerModeDigitModifierFlags(ambientModifierFlags: []) == [.option])
        #expect(MiniRecorderShortcutManager.shouldRegisterPowerModeDigitShortcuts(ambientModifierFlags: []))
    }

    @Test func miniRecorderPromptShortcutsIncludeHeldRecordingModifiers() {
        let modifierFlags = MiniRecorderShortcutManager.promptDigitModifierFlags(
            ambientModifierFlags: [.option]
        )

        #expect(modifierFlags == [.command, .option])
    }

    @Test func miniRecorderPowerModeShortcutsDoNotCollideWithPromptShortcutsWhenOptionIsHeld() {
        let promptModifierFlags = MiniRecorderShortcutManager.promptDigitModifierFlags(
            ambientModifierFlags: [.option]
        )
        let powerModeModifierFlags = MiniRecorderShortcutManager.powerModeDigitModifierFlags(
            ambientModifierFlags: [.option]
        )

        #expect(promptModifierFlags == [.command, .option])
        #expect(powerModeModifierFlags == [.option])
        #expect(promptModifierFlags != powerModeModifierFlags)
        #expect(MiniRecorderShortcutManager.shouldRegisterPowerModeDigitShortcuts(ambientModifierFlags: [.option]))
    }

    @Test func miniRecorderPowerModeShortcutsAreSkippedWhenFoldedModifiersWouldCollide() {
        let promptModifierFlags = MiniRecorderShortcutManager.promptDigitModifierFlags(
            ambientModifierFlags: [.command, .option]
        )
        let powerModeModifierFlags = MiniRecorderShortcutManager.powerModeDigitModifierFlags(
            ambientModifierFlags: [.command, .option]
        )

        #expect(promptModifierFlags == powerModeModifierFlags)
        #expect(!MiniRecorderShortcutManager.shouldRegisterPowerModeDigitShortcuts(ambientModifierFlags: [.command, .option]))
    }

}
