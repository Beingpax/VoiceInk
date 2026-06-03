import Foundation
import AppKit
import os

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
        case .unlicensed:
            return "Start a 7-day trial or buy VoiceInk Pro to continue using VoiceInk."
        case .trialExpired:
            return "Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy"
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
            validationMessage = "Please enter a license key"
            return
        }
        
        licenseKey = normalizedLicenseKey
        isValidating = true
        validationSuccess = false
        validationMessage = nil
        
        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(normalizedLicenseKey)
            
            if !licenseCheck.isValid {
                validationSuccess = false
                validationMessage = "This license has been revoked or disabled. Please contact support."
                isValidating = false
                return
            }
            
            // Handle based on whether activation is required
            if licenseCheck.requiresActivation {
                // If we already have an activation ID, try to validate with it first
                if let existingActivationId = licenseManager.activationId {
                    let isValid = (try? await polarService.validateLicenseKeyWithActivation(normalizedLicenseKey, activationId: existingActivationId)) ?? false
                    if isValid {
                        let limit = licenseCheck.activationsLimit ?? userDefaults.activationsLimit
                        licenseManager.licenseKey = normalizedLicenseKey
                        userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                        activationsLimit = limit
                        userDefaults.activationsLimit = limit
                        completeSuccessfulValidation(message: "License activated successfully!")
                        isValidating = false
                        return
                    }
                    // Activation is stale (deleted from portal) — clear it and create a new one
                    licenseManager.activationId = nil
                }

                // Need to create a new activation
                let (newActivationId, limit) = try await polarService.activateLicenseKey(normalizedLicenseKey)

                // Store activation details
                licenseManager.licenseKey = normalizedLicenseKey
                licenseManager.activationId = newActivationId
                userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = limit
                userDefaults.activationsLimit = limit

            } else {
                // This license doesn't require activation (unlimited devices)
                licenseManager.licenseKey = normalizedLicenseKey
                licenseManager.activationId = nil
                userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = licenseCheck.activationsLimit ?? 0
                userDefaults.activationsLimit = licenseCheck.activationsLimit ?? 0

                // Update the license state for unlimited license
                completeSuccessfulValidation(message: "License validated successfully!")
                isValidating = false
                return
            }
            
            // Update the license state for activated license
            completeSuccessfulValidation(message: "License activated successfully!")

        } catch LicenseError.keyNotFound {
            validationSuccess = false
            validationMessage = "License key not found. Please double-check your key and try again."
        } catch LicenseError.activationLimitReached {
            validationSuccess = false
            validationMessage = "This license has reached its device limit. Visit the License Management Portal to deactivate other devices."
        } catch LicenseError.serverError(let code) {
            validationSuccess = false
            validationMessage = "Server error (\(code)). Please try again later or contact support."
        } catch let urlError as URLError {
            validationSuccess = false
            logger.error("🔑 License network error: \(urlError.localizedDescription, privacy: .public)")
            validationMessage = "Could not reach the server. Please check your internet connection and try again."
        } catch {
            validationSuccess = false
            logger.error("🔑 Unexpected license error: \(error, privacy: .public)")
            validationMessage = "An unexpected error occurred. Please try again or contact support at support@tryvoiceink.com"
        }
        
        isValidating = false
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
    
    func removeLicense() {
        // Remove only the license credentials. Trial history stays intact.
        licenseManager.removeStoredLicense()

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
