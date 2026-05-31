//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
@testable import VoiceInk
import Foundation

struct VoiceInkTests {

    @Test func generalBackupDecodesWithoutMenuBarIconPreference() throws {
        let data = Data("""
        {
          "launchAtLoginEnabled": true,
          "isMenuBarOnly": true
        }
        """.utf8)

        let backup = try JSONDecoder().decode(GeneralBackup.self, from: data)

        #expect(backup.launchAtLoginEnabled == true)
        #expect(backup.isMenuBarOnly == true)
        #expect(backup.showMenuBarIcon == nil)
    }

    @Test func generalBackupDecodesMenuBarIconPreference() throws {
        let data = Data("""
        {
          "showMenuBarIcon": false
        }
        """.utf8)

        let backup = try JSONDecoder().decode(GeneralBackup.self, from: data)

        #expect(backup.showMenuBarIcon == false)
    }

}
