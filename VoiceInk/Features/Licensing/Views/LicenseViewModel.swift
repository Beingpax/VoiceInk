import AppKit
import Foundation
import os

private enum LicenseStorageError: Error {
    case failed
}

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case unlicensed
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .unlicensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published private(set) var isDeactivating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0

    private let trialPeriodDays = 7
    private let polarService = PolarService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseViewModel")
    private let userDefaults = UserDefaults.standard
    private let licenseManager = LicenseManager.shared

    init() {
        #if LOCAL_BUILD
            licenseState = .licensed
        #else
            loadLicenseState()
        #endif
    }

    func startTrial() {
        let didStartTrial = licenseManager.startTrialIfNeeded()
        refreshTrialState()
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)

        if didStartTrial {
            requestLicenseCelebration()
        }
    }

    private func loadLicenseState() {
        // Check for existing license key
        if let storedLicenseKey = licenseManager.licenseKey {
            self.licenseKey = storedLicenseKey

            // If we have a license key, trust that it's licensed
            // Skip server validation on startup
            if licenseManager.activationId != nil || !userDefaults.bool(forKey: "VoiceInkLicenseRequiresActivation") {
                licenseState = .licensed
                activationsLimit = userDefaults.activationsLimit
                return
            }
        }

        if let trialStartDate = licenseManager.trialStartDate {
            refreshTrialState(from: trialStartDate)
        } else {
            setUnlicensedState()
        }
    }

    func refreshLicenseState() {
        loadLicenseState()
    }

    var isLicensed: Bool {
        if case .licensed = licenseState {
            return true
        }

        return false
    }

    private func setUnlicensedState() {
        licenseState = .unlicensed
    }

    private func refreshTrialState() {
        guard let trialStartDate = licenseManager.trialStartDate else {
            setUnlicensedState()
            return
        }

        refreshTrialState(from: trialStartDate)
    }

    private func refreshTrialState(from trialStartDate: Date) {
        let daysSinceTrialStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0

        if daysSinceTrialStart >= trialPeriodDays {
            licenseState = .trialExpired
        } else {
            licenseState = .trial(daysRemaining: trialPeriodDays - daysSinceTrialStart)
        }
    }

    var canUseApp: Bool {
        switch licenseState {
        case .licensed, .trial:
            return true
        case .unlicensed, .trialExpired:
            return false
        }
    }

    var usageRestrictionMessage: String? {
        switch licenseState {
        case .unlicensed, .trialExpired:
            return String(
                format: String(localized: "Your trial has ended. Upgrade to VoiceInk Pro at %@"),
                "tryvoiceink.com/buy"
            )
        case .trial, .licensed:
            return nil
        }
    }

    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }

    func validateLicense() async {
        let normalizedLicenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedLicenseKey.isEmpty else {
            validationSuccess = false
            validationMessage = String(localized: "Please enter a license key")
            return
        }

        licenseKey = normalizedLicenseKey
        isValidating = true
        defer { isValidating = false }
        validationSuccess = false
        validationMessage = nil

        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(normalizedLicenseKey)

            if !licenseCheck.isValid {
                validationSuccess = false
                validationMessage = String(
                    localized: "This license has been revoked or disabled. Please contact support.")
                return
            }

            // Handle based on whether activation is required
            if licenseCheck.requiresActivation {
                // If we already have an activation ID, try to validate with it first
                if let existingActivationId = licenseManager.activationId,
                    licenseManager.licenseKey == normalizedLicenseKey
                {
                    let isValid = try await validateExistingActivation(
                        key: normalizedLicenseKey,
                        activationId: existingActivationId
                    )

                    if isValid {
                        let limit = licenseCheck.activationsLimit ?? userDefaults.activationsLimit
                        userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                        activationsLimit = limit
                        userDefaults.activationsLimit = limit
                        completeSuccessfulValidation(message: String(localized: "License activated successfully!"))
                        return
                    }
                    // Activation is stale (deleted from portal) — clear it and create a new one
                    try persistLicense(key: normalizedLicenseKey, activationId: nil)
                }

                // Need to create a new activation
                let limit = try await activateAndPersistLicense(normalizedLicenseKey)
                userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = limit
                userDefaults.activationsLimit = limit

            } else {
                // This license doesn't require activation (unlimited devices)
                let limit = licenseCheck.activationsLimit ?? 0
                try persistLicense(key: normalizedLicenseKey, activationId: nil)
                userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = limit
                userDefaults.activationsLimit = limit

                // Update the license state for unlimited license
                completeSuccessfulValidation(message: String(localized: "License validated successfully!"))
                return
            }

            // Update the license state for activated license
            completeSuccessfulValidation(message: String(localized: "License activated successfully!"))

        } catch LicenseError.keyNotFound {
            validationSuccess = false
            validationMessage = String(localized: "License key not found. Please double-check your key and try again.")
        } catch LicenseError.activationLimitReached {
            validationSuccess = false
            validationMessage = String(
                localized:
                    "This license has reached its device limit. Visit the License Management Portal to deactivate other devices."
            )
        } catch LicenseError.serverError(let code) {
            validationSuccess = false
            validationMessage = String(
                format: String(localized: "Server error (%d). Please try again later or contact support."),
                code
            )
        } catch LicenseStorageError.failed {
            validationSuccess = false
            validationMessage = String(localized: "VoiceInk couldn't save the license. Please try again.")
        } catch let urlError as URLError {
            validationSuccess = false
            logger.error("🔑 License network error: \(urlError, privacy: .public)")
            validationMessage = String(
                localized: "Could not reach the server. Please check your internet connection and try again.")
        } catch {
            validationSuccess = false
            logger.error("🔑 Unexpected license error: \(error, privacy: .public)")
            validationMessage = String(
                format: String(localized: "An unexpected error occurred. Please try again or contact support at %@"),
                "support@tryvoiceink.com"
            )
        }
    }

    private func validateExistingActivation(key: String, activationId: String) async throws -> Bool {
        do {
            return try await polarService.validateLicenseKeyWithActivation(key, activationId: activationId)
        } catch LicenseError.keyNotFound {
            return false
        }
    }

    private func activateAndPersistLicense(_ key: String) async throws -> Int {
        let (activationId, limit) = try await polarService.activateLicenseKey(key)

        do {
            try persistLicense(key: key, activationId: activationId)
            return limit
        } catch {
            do {
                try await polarService.deactivateLicenseKey(key, activationId: activationId)
            } catch {
                logger.error("🔑 Failed to roll back unsaved license activation: \(error, privacy: .public)")
            }
            throw LicenseStorageError.failed
        }
    }

    private func persistLicense(key: String, activationId: String?) throws {
        guard licenseManager.storeLicense(key: key, activationId: activationId) else {
            throw LicenseStorageError.failed
        }
    }

    private func completeSuccessfulValidation(message: String) {
        licenseState = .licensed
        validationSuccess = true
        validationMessage = message
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        requestLicenseCelebration()
    }

    private func requestLicenseCelebration() {
        NotificationCenter.default.post(name: .licenseCelebrationRequested, object: nil)
    }

    func deactivateLicense() async {
        guard !isDeactivating else { return }

        isDeactivating = true
        validationMessage = nil
        defer { isDeactivating = false }

        do {
            if let key = licenseManager.licenseKey,
                let activationId = licenseManager.activationId
            {
                try await polarService.deactivateLicenseKey(key, activationId: activationId)
            }
            try clearStoredLicense()
        } catch LicenseStorageError.failed {
            validationSuccess = false
            validationMessage = String(localized: "VoiceInk couldn't remove the saved license. Please try again.")
        } catch {
            logger.error("🔑 License deactivation failed: \(error, privacy: .public)")
            validationSuccess = false
            validationMessage = String(localized: "Couldn't deactivate the license. Please try again.")
        }
    }

    private func clearStoredLicense() throws {
        // Remove only the license credentials. Trial history stays intact.
        guard licenseManager.removeStoredLicense() else {
            throw LicenseStorageError.failed
        }

        // Reset UserDefaults flags
        userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
        userDefaults.activationsLimit = 0

        licenseKey = ""
        validationMessage = nil
        validationSuccess = false
        activationsLimit = 0
        loadLicenseState()
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
}

// UserDefaults extension for non-sensitive license settings
extension UserDefaults {
    var activationsLimit: Int {
        get { integer(forKey: "VoiceInkActivationsLimit") }
        set { set(newValue, forKey: "VoiceInkActivationsLimit") }
    }
}
