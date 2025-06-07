import Foundation
import IOKit

class PolarService {
    private let organizationId = "Org"
    private let apiToken = "Token"
    private let baseURL = "https://api.polar.sh"
    
    // Generate a unique device identifier
    private func getDeviceIdentifier() -> String {
        // Use the macOS serial number or a generated UUID that persists
        if let serialNumber = getMacSerialNumber() {
            return serialNumber
        }
        
        // Fallback to a stored UUID if we can't get the serial number
        let defaults = UserDefaults.standard
        if let storedId = defaults.string(forKey: "VoiceInkDeviceIdentifier") {
            return storedId
        }
        
        // Create and store a new UUID if none exists
        let newId = UUID().uuidString
        defaults.set(newId, forKey: "VoiceInkDeviceIdentifier")
        return newId
    }
    
    // Try to get the Mac serial number
    private func getMacSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if platformExpert == 0 { return nil }
        
        defer { IOObjectRelease(platformExpert) }
        
        if let serialNumber = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0) {
            return (serialNumber.takeRetainedValue() as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}
