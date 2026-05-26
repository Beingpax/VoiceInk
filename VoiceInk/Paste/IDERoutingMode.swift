import Foundation

enum IDERoutingMode: String, CaseIterable, Identifiable {
    case activeApp = "active"
    case cursor = "cursor"
    case windsurf = "windsurf"
    case vscode = "vscode"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .activeApp:
            return "Active Application (Default)"
        case .cursor:
            return "Cursor Editor"
        case .windsurf:
            return "Windsurf Editor"
        case .vscode:
            return "VS Code Editor"
        }
    }
    
    var bundleIdentifier: String? {
        switch self {
        case .activeApp:
            return nil
        case .cursor:
            return "com.todesktop.perty"
        case .windsurf:
            return "com.codeium.windsurf"
        case .vscode:
            return "com.microsoft.VSCode"
        }
    }
    
    var appName: String? {
        switch self {
        case .activeApp:
            return nil
        case .cursor:
            return "Cursor"
        case .windsurf:
            return "Windsurf"
        case .vscode:
            return "Visual Studio Code"
        }
    }
}
