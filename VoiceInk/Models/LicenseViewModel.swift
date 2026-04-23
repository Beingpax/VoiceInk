import Foundation
import AppKit
import os

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .trial(daysRemaining: 7)  // Default to trial
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
        // Only set trial start date if it hasn't been set before
        if licenseManager.trialStartDate == nil {
            licenseManager.trialStartDate = Date()
            licenseState = .trial(daysRemaining: trialPeriodDays)
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
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

        // Check if this is first launch
        let hasLaunchedBefore = userDefaults.bool(forKey: "VoiceInkHasLaunchedBefore")
        if !hasLaunchedBefore {
            // First launch - start trial automatically
            userDefaults.set(true, forKey: "VoiceInkHasLaunchedBefore")
            startTrial()
            return
        }

        // Only check trial if not licensed and not first launch
        if let trialStartDate = licenseManager.trialStartDate {
            let daysSinceTrialStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0

            if daysSinceTrialStart >= trialPeriodDays {
                licenseState = .trialExpired
            } else {
                licenseState = .trial(daysRemaining: trialPeriodDays - daysSinceTrialStart)
            }
        } else {
            // No trial has been started yet - start it now
            startTrial()
        }
    }
    
    var canUseApp: Bool {
        switch licenseState {
        case .licensed, .trial:
            return true
        case .trialExpired:
            return false
        }
    }
    
    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func validateLicense() async {
        guard !licenseKey.isEmpty else {
            validationSuccess = false
            validationMessage = "Please enter a license key"
            return
        }
        
        isValidating = true
        
        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(licenseKey)
            
            if !licenseCheck.isValid {
                validationSuccess = false
                validationMessage = "This license has been revoked or disabled. Please contact support."
                isValidating = false
                return
            }
            
            // Store the license key
            licenseManager.licenseKey = licenseKey

            // Handle based on whether activation is required
            if licenseCheck.requiresActivation {
                // If we already have an activation ID, try to validate with it first
                if let existingActivationId = licenseManager.activationId {
                    let isValid = (try? await polarService.validateLicenseKeyWithActivation(licenseKey, activationId: existingActivationId)) ?? false
                    if isValid {
                        licenseState = .licensed
                        validationSuccess = true
                        validationMessage = "License activated successfully!"
                        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
                        isValidating = false
                        return
                    }
                    // Activation is stale (deleted from portal) — clear it and create a new one
                    licenseManager.activationId = nil
                }

                // Need to create a new activation
                let (newActivationId, limit) = try await polarService.activateLicenseKey(licenseKey)

                // Store activation details
                licenseManager.activationId = newActivationId
                userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = limit
                userDefaults.activationsLimit = limit

            } else {
                // This license doesn't require activation (unlimited devices)
                licenseManager.activationId = nil
                userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = licenseCheck.activationsLimit ?? 0
                userDefaults.activationsLimit = licenseCheck.activationsLimit ?? 0

                // Update the license state for unlimited license
                licenseState = .licensed
                validationSuccess = true
                validationMessage = "License validated successfully!"
                NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
                isValidating = false
                return
            }
            
            // Update the license state for activated license
            licenseState = .licensed
            validationSuccess = true
            validationMessage = "License activated successfully!"
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)

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
            validationMessage = "An unexpected error occurred. Please try again or contact support at prakashjoshipax@gmail.com"
        }
        
        isValidating = false
    }
    
    func removeLicense() {
        // Remove all license data from Keychain
        licenseManager.removeAll()

        // Reset UserDefaults flags
        userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
        userDefaults.set(false, forKey: "VoiceInkHasLaunchedBefore")  // Allow trial to restart
        userDefaults.activationsLimit = 0

        licenseState = .trial(daysRemaining: trialPeriodDays)  // Reset to trial state
        licenseKey = ""
        validationMessage = nil
        activationsLimit = 0
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        loadLicenseState()
    }
}


// UserDefaults extension for non-sensitive license settings
extension UserDefaults {
    var activationsLimit: Int {
        get { integer(forKey: "VoiceInkActivationsLimit") }
        set { set(newValue, forKey: "VoiceInkActivationsLimit") }
    }
}
