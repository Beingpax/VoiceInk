import Foundation
import AppKit

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
    @Published private(set) var activationsLimit: Int = 0
    
    private let trialPeriodDays = 7
    private let polarService = PolarService()
    private let userDefaults = UserDefaults.standard
    
    init() {
        checkLicenseState()
    }
    
    func startTrial() {
        // Only set trial start date if it hasn't been set before
        if userDefaults.trialStartDate == nil {
            userDefaults.trialStartDate = Date()
            licenseState = .trial(daysRemaining: trialPeriodDays)
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }
    
    private func checkLicenseState() {
        // Check for existing license key
        if let licenseKey = userDefaults.licenseKey {
            self.licenseKey = licenseKey
            
            // Check if this license requires activation
            if userDefaults.bool(forKey: "VoiceInkLicenseRequiresActivation") {
                // If we have an activation ID, we need to validate it
                if let activationId = userDefaults.activationId {
                    Task {
                        do {
                            let isValid = try await polarService.validateLicenseKeyWithActivation(licenseKey, activationId: activationId)
                            if isValid {
                                licenseState = .licensed
                            } else {
                                // If validation fails, we'll need to reactivate
                                userDefaults.activationId = nil
                                licenseState = .trialExpired
                            }
                        } catch {
                            // If there's an error, we'll need to reactivate
                            userDefaults.activationId = nil
                            licenseState = .trialExpired
                        }
                    }
                } else {
                    // We have a license key but no activation ID, so we need to activate
                    licenseState = .licensed
                }
            } else {
                // This license doesn't require activation (unlimited devices)
                licenseState = .licensed
            }
            return
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
        if let trialStartDate = userDefaults.trialStartDate {
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
            validationMessage = "Please enter a license key"
            return
        }
        
        isValidating = true
        
        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(licenseKey)
            
            if !licenseCheck.isValid {
                validationMessage = "Invalid license key"
                isValidating = false
                return
            }
            
            // Store the license key
            userDefaults.licenseKey = licenseKey
            
            // Handle based on whether activation is required
            if licenseCheck.requiresActivation {
                // If we already have an activation ID, validate with it
                if let activationId = userDefaults.activationId {
                    let isValid = try await polarService.validateLicenseKeyWithActivation(licenseKey, activationId: activationId)
                    if isValid {
                        // Existing activation is valid
                        licenseState = .licensed
                        validationMessage = "License activated successfully!"
                        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
                        isValidating = false
                        return
                    }
                }
                
                // Need to create a new activation
                let (activationId, limit) = try await polarService.activateLicenseKey(licenseKey)
                
                // Store activation details
                userDefaults.activationId = activationId
                userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = limit
                
            } else {
                // This license doesn't require activation (unlimited devices)
                userDefaults.activationId = nil
                userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
                self.activationsLimit = licenseCheck.activationsLimit ?? 0
            }
            
            // Update the license state
            licenseState = .licensed
            validationMessage = "License activated successfully!"
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
            
        } catch LicenseError.activationLimitReached {
            validationMessage = "This license has reached its maximum number of activations."
        } catch LicenseError.activationNotRequired {
            // This is actually a success case for unlimited licenses
            userDefaults.licenseKey = licenseKey
            userDefaults.activationId = nil
            userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
            self.activationsLimit = 0
            
            licenseState = .licensed
            validationMessage = "License activated successfully!"
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        } catch {
            validationMessage = "Error validating license: \(error.localizedDescription)"
        }
        
        isValidating = false
    }
    
    func removeLicense() {
        // Remove both license key and trial data
        userDefaults.licenseKey = nil
        userDefaults.activationId = nil
        userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
        userDefaults.trialStartDate = nil
        userDefaults.set(false, forKey: "VoiceInkHasLaunchedBefore")  // Allow trial to restart
        
        licenseState = .trial(daysRemaining: trialPeriodDays)  // Reset to trial state
        licenseKey = ""
        validationMessage = nil
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        checkLicenseState()
    }
}

extension Notification.Name {
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
}
