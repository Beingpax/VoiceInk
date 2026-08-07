import Foundation

enum AppPreferenceKey {
    static let isMenuBarOnly = "IsMenuBarOnly"
    static let showMenuBarIcon = "ShowMenuBarIcon"
}

struct AppIconVisibility: Equatable {
    var isDockIconHidden: Bool
    var isMenuBarIconHidden: Bool

    var areBothIconsHidden: Bool {
        isDockIconHidden && isMenuBarIconHidden
    }

    func applying(_ change: AppIconVisibilityChange) -> AppIconVisibility {
        var updated = self

        switch change {
        case .setDockIconHidden(let isHidden):
            updated.isDockIconHidden = isHidden
        case .setMenuBarIconHidden(let isHidden):
            updated.isMenuBarIconHidden = isHidden
        }

        return updated
    }

    func decision(for change: AppIconVisibilityChange) -> AppIconVisibilityDecision {
        AppIconVisibilityDecision(current: self, requested: applying(change))
    }

    static func afterImport(_ general: GeneralBackup?, current: AppIconVisibility) -> AppIconVisibility {
        guard let general else { return current }

        return AppIconVisibility(
            isDockIconHidden: general.isMenuBarOnly ?? current.isDockIconHidden,
            isMenuBarIconHidden: general.showMenuBarIcon.map { !$0 } ?? current.isMenuBarIconHidden
        )
    }
}

enum AppIconVisibilityChange: Equatable {
    case setDockIconHidden(Bool)
    case setMenuBarIconHidden(Bool)
}

struct AppIconVisibilityDecision: Equatable {
    let current: AppIconVisibility
    let requested: AppIconVisibility

    var requiresConfirmation: Bool {
        !current.areBothIconsHidden && requested.areBothIconsHidden
    }
}

enum BackupIconVisibilityPreflight {
    static func decision(
        for backup: BackupFile, categories: Set<BackupCategory>, current: AppIconVisibility
    ) -> AppIconVisibilityDecision? {
        guard categories.contains(.general), let general = backup.generalSettings else {
            return nil
        }

        return AppIconVisibilityDecision(
            current: current,
            requested: .afterImport(general, current: current)
        )
    }

    static func resultsInBothIconsHidden(
        for backup: BackupFile, categories: Set<BackupCategory>, current: AppIconVisibility
    ) -> Bool {
        decision(for: backup, categories: categories, current: current)?.requested.areBothIconsHidden == true
    }
}
