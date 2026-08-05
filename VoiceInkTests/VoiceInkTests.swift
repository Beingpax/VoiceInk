import Foundation
import Testing
@testable import VoiceInk

struct AppIconVisibilityTests {
    @Test func warningDetectionCoversEveryVisibilityAndToggleCombination() {
        for isDockIconHidden in [false, true] {
            for isMenuBarIconHidden in [false, true] {
                let current = AppIconVisibility(
                    isDockIconHidden: isDockIconHidden,
                    isMenuBarIconHidden: isMenuBarIconHidden
                )
                let changes: [AppIconVisibilityChange] = [
                    .setDockIconHidden(false),
                    .setDockIconHidden(true),
                    .setMenuBarIconHidden(false),
                    .setMenuBarIconHidden(true),
                ]

                for change in changes {
                    let decision = current.decision(for: change)
                    let expected = !current.areBothIconsHidden && decision.requested.areBothIconsHidden
                    #expect(decision.requiresConfirmation == expected)
                }
            }
        }
    }

    @Test func cancelAndConfirmHidingMenuBarAsLastIcon() {
        let current = AppIconVisibility(isDockIconHidden: true, isMenuBarIconHidden: false)
        let decision = current.decision(for: .setMenuBarIconHidden(true))

        #expect(decision.requiresConfirmation)
    }

    @Test func cancelAndConfirmHidingDockAsLastIcon() {
        let current = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: true)
        let decision = current.decision(for: .setDockIconHidden(true))

        #expect(decision.requiresConfirmation)
    }
}

struct MenuBarIconPreferenceTests {
    @Test func menuBarIconDefaultsToVisible() {
        AppDefaults.registerDefaults()

        let registeredDefaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registeredDefaults[AppPreferenceKey.showMenuBarIcon] as? Bool == true)
    }
}

struct GeneralBackupIconVisibilityTests {
    @Test func oldBackupWithoutMenuBarFieldLeavesVisibilityUnchanged() throws {
        let backup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "isMenuBarOnly": true
              }
            }
            """)
        let current = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: true)

        #expect(backup.generalSettings?.showMenuBarIcon == nil)
        #expect(
            AppIconVisibility.afterImport(backup.generalSettings, current: current).isMenuBarIconHidden
                == current.isMenuBarIconHidden
        )
    }

    @Test(arguments: [true, false])
    func menuBarVisibilityRoundTrips(showMenuBarIcon: Bool) throws {
        let backup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "showMenuBarIcon": \(showMenuBarIcon)
              }
            }
            """)
        let encoded = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(BackupFile.self, from: encoded)

        #expect(decoded.generalSettings?.showMenuBarIcon == showMenuBarIcon)
    }

    @Test func importPreflightWarnsOnlyWhenSelectedGeneralWouldHideBothIcons() throws {
        let bothHiddenBackup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "isMenuBarOnly": true,
                "showMenuBarIcon": false
              }
            }
            """)
        let visible = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: false)

        #expect(
            BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: bothHiddenBackup, categories: [.general], current: visible
            )
        )
        #expect(
            !BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: bothHiddenBackup, categories: [.modes], current: visible
            )
        )
    }

    @Test func importPreflightUsesCurrentDockStateWhenBackupOmitsIt() throws {
        let menuHiddenBackup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "showMenuBarIcon": false
              }
            }
            """)

        let dockHidden = AppIconVisibility(isDockIconHidden: true, isMenuBarIconHidden: false)
        let dockVisible = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: false)

        #expect(
            BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: menuHiddenBackup, categories: [.general], current: dockHidden
            )
        )
        #expect(
            !BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: menuHiddenBackup, categories: [.general], current: dockVisible
            )
        )
    }

    @Test func oldBackupPreflightUsesCurrentMenuBarVisibility() throws {
        let oldBackup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "isMenuBarOnly": true
              }
            }
            """)
        let menuBarHidden = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: true)
        let iconsVisible = AppIconVisibility(isDockIconHidden: false, isMenuBarIconHidden: false)

        #expect(
            BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: oldBackup, categories: [.general], current: menuBarHidden
            )
        )
        #expect(
            !BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: oldBackup, categories: [.general], current: iconsVisible
            )
        )
    }

    @Test func importPreflightWarnsAgainWhenCurrentStateAlreadyHasBothIconsHidden() throws {
        let bothHiddenBackup = try decodeBackup("""
            {
              "version": "1.0.0",
              "generalSettings": {
                "isMenuBarOnly": true,
                "showMenuBarIcon": false
              }
            }
            """)
        let bothHidden = AppIconVisibility(isDockIconHidden: true, isMenuBarIconHidden: true)

        #expect(
            BackupIconVisibilityPreflight.resultsInBothIconsHidden(
                for: bothHiddenBackup, categories: [.general], current: bothHidden
            )
        )
    }

    private func decodeBackup(_ json: String) throws -> BackupFile {
        try JSONDecoder().decode(BackupFile.self, from: Data(json.utf8))
    }
}
