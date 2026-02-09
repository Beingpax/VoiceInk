import Foundation
import IOKit

/// Simple utility to obfuscate sensitive data stored in UserDefaults
struct Obfuscator {
    
    /// Encodes a string using Base64 with a device-specific salt
    static func encode(_ string: String, salt: String) -> String {
        let salted = salt + string + salt
        let data = Data(salted.utf8)
        return data.base64EncodedString()
    }
    
    /// Decodes a Base64 string using a device-specific salt
    static func decode(_ base64: String, salt: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let salted = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Remove the salt from both ends
        guard salted.hasPrefix(salt), salted.hasSuffix(salt) else { 
            return nil 
        }
        
        return String(salted.dropFirst(salt.count).dropLast(salt.count))
    }
    
    /// Gets a device-specific identifier to use as salt
    /// Uses the same logic as PolarService for consistency
    static func getDeviceIdentifier() -> String {
        // Try to get Mac serial number first
        if let serialNumber = getMacSerialNumber() {
            return serialNumber
        }
        
        // Fallback to stored UUID
        let defaults = UserDefaults.standard
        if let storedId = defaults.string(forKey: "VoiceInkDeviceIdentifier") {
            return storedId
        }
        
        // Create and store new UUID
        let newId = UUID().uuidString
        defaults.set(newId, forKey: "VoiceInkDeviceIdentifier")
        return newId
    }
    
    /// Try to get the Mac serial number
    private static func getMacSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if platformExpert == 0 { return nil }
        
        defer { IOObjectRelease(platformExpert) }
        
        if let serialNumber = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0) {
            return (serialNumber.takeRetainedValue() as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}
