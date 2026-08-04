import Foundation

/// Opens a main-window tab from contexts with no view hierarchy, such as a notification action.
enum ModeSetupNavigator {
    static func openModesSettings() {
        open(destination: .modes)
    }

    static func openModelsSettings() {
        open(destination: .models)
    }

    private static func open(destination: ViewType) {
        MainWindowNavigation.shared.navigate(to: destination)

        if WindowManager.shared.currentMainWindow() == nil {
            WindowManager.shared.prepareForUserRequestedMainWindow()
            NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        } else {
            WindowManager.shared.showMainWindow()
        }
    }
}
