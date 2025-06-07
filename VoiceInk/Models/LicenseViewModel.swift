import Foundation

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case licensed
    }
    
    @Published private(set) var licenseState: LicenseState = .licensed // Default to licensed
    
    var canUseApp: Bool {
        return true
    }
}
