import Foundation
import SwiftUI

enum ModeValidationError: Error, Identifiable {
    case emptyName
    case duplicateName(String)
    case duplicateAppTrigger(String, String) // (app name, existing mode name)
    case duplicateWebsiteTrigger(String, String) // (website, existing mode name)

    var id: String {
        switch self {
        case .emptyName: return "emptyName"
        case .duplicateName: return "duplicateName"
        case .duplicateAppTrigger: return "duplicateAppTrigger"
        case .duplicateWebsiteTrigger: return "duplicateWebsiteTrigger"
        }
    }

    var localizedDescription: String {
        switch self {
        case .emptyName:
            return "Mode name cannot be empty."
        case .duplicateName(let name):
            return "A mode with the name '\(name)' already exists."
        case .duplicateAppTrigger(let appName, let modeName):
            return "The app '\(appName)' is already configured in the '\(modeName)' mode."
        case .duplicateWebsiteTrigger(let website, let modeName):
            return "The website '\(website)' is already configured in the '\(modeName)' mode."
        }
    }
}

struct ModeValidator {
    private let modeManager: ModeManager

    init(modeManager: ModeManager) {
        self.modeManager = modeManager
    }

    func validateForSave(config: ModeConfig, mode: ConfigurationMode) -> [ModeValidationError] {
        var errors: [ModeValidationError] = []

        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        let isDuplicateName = modeManager.configurations.contains { existingConfig in
            if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                return false
            }
            return existingConfig.name == config.name
        }

        if isDuplicateName {
            errors.append(.duplicateName(config.name))
        }

        for appConfig in config.allAppConfigs {
            for existingConfig in modeManager.configurations {
                if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                    continue
                }

                if existingConfig.allAppConfigs.contains(where: { $0.bundleIdentifier == appConfig.bundleIdentifier }) {
                    errors.append(.duplicateAppTrigger(appConfig.appName, existingConfig.name))
                }
            }
        }

        for urlConfig in config.allURLConfigs {
            let cleanedURL = modeManager.cleanURL(urlConfig.url)

            for existingConfig in modeManager.configurations {
                if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                    continue
                }

                if existingConfig.allURLConfigs.contains(where: { modeManager.cleanURL($0.url) == cleanedURL }) {
                    errors.append(.duplicateWebsiteTrigger(cleanedURL, existingConfig.name))
                }
            }
        }

        return errors
    }
}

extension View {
    func modeValidationAlert(
        errors: [ModeValidationError],
        isPresented: Binding<Bool>
    ) -> some View {
        self.alert(
            "Cannot Save Mode",
            isPresented: isPresented,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                if let firstError = errors.first {
                    Text(firstError.localizedDescription)
                } else {
                    Text("Please fix the validation errors before saving.")
                }
            }
        )
    }
}
