import Foundation
import SwiftUI
import AppKit

struct EmailSupport {
    static func generateSupportEmailURL() -> URL? {
        let subject = "VoiceInk Support Request"
        let systemInfo = """
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Device: \(getMacModel())
        CPU: \(getCPUInfo())
        Memory: \(getMemoryInfo())
        """
        
        let body = """
        
        ------------------------
        ✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨
        ▶️ Create a quick screen recording showing the issue!
        ▶️ It helps me understand and fix the problem much faster.
        
        📝 ISSUE DETAILS:
        - What steps did you take before the issue occurred?
        - What did you expect to happen?
        - What actually happened instead?
        
        
        ## 📋 COMMON ISSUES:
        Check out our Common Issues page before sending an email: https://tryvoiceink.com/common-issues
        ------------------------
        
        System Information:
        \(systemInfo)

        
        """
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        return URL(string: "mailto:prakashjoshipax@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)")
    }
    
    static func openSupportEmail() {
        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
    
    private static func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }
    
    private static func getCPUInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
    
    private static func getMemoryInfo() -> String {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)
    }
    
} 
