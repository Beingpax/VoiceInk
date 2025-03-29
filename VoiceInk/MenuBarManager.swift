import SwiftUI
import LaunchAtLogin
import SwiftData
import AppKit

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.isMenuBarOnly = isMenuBarOnly
            updateAppActivationPolicy()
        }
    }
    
    private var updaterViewModel: UpdaterViewModel
    private var whisperState: WhisperState
    private var container: ModelContainer
    private var enhancementService: AIEnhancementService
    private var aiService: AIService
    private var hotkeyManager: HotkeyManager
    private var mainWindow: NSWindow?  // Store window reference
    
    init(updaterViewModel: UpdaterViewModel, 
         whisperState: WhisperState, 
         container: ModelContainer,
         enhancementService: AIEnhancementService,
         aiService: AIService,
         hotkeyManager: HotkeyManager) {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: UserDefaultsKeys.MenuBar.isMenuBarOnly)
        self.updaterViewModel = updaterViewModel
        self.whisperState = whisperState
        self.container = container
        self.enhancementService = enhancementService
        self.aiService = aiService
        self.hotkeyManager = hotkeyManager
        updateAppActivationPolicy()
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    private func updateAppActivationPolicy() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up existing window if switching to menu bar mode
            if self.isMenuBarOnly && self.mainWindow != nil {
                self.mainWindow?.close()
                self.mainWindow = nil
            }
            
            // Update activation policy
            if self.isMenuBarOnly {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        print("MenuBarManager: Navigating to \(destination)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Activate the app
            NSApp.activate(ignoringOtherApps: true)
            
            // Clean up existing window if it's no longer valid
            if let existingWindow = self.mainWindow, !existingWindow.isVisible {
                self.mainWindow = nil
            }
            
            // Get or create main window
            if self.mainWindow == nil {
                self.mainWindow = self.createMainWindow()
            }
            
            guard let window = self.mainWindow else { return }
            
            // Make the window key and order front
            window.makeKeyAndOrderFront(nil)
            window.center()  // Always center the window for consistent positioning
            
            // Post a notification to navigate to the desired destination
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": destination]
                )
                print("MenuBarManager: Posted navigation notification for \(destination)")
            }
        }
    }
    
    private func createMainWindow() -> NSWindow {
        print("MenuBarManager: Creating new main window")
        
        // Create the content view with all required environment objects
        let contentView = ContentView()
            .environmentObject(whisperState)
            .environmentObject(hotkeyManager)
            .environmentObject(self)
            .environmentObject(updaterViewModel)
            .environmentObject(enhancementService)
            .environmentObject(aiService)
            .environment(\.modelContext, ModelContext(container))
        
        // Create window using WindowManager
        let hostingView = NSHostingView(rootView: contentView)
        let window = WindowManager.shared.createMainWindow(contentView: hostingView)
        
        // Set window delegate to handle window closing
        let delegate = WindowDelegate { [weak self] in
            self?.mainWindow = nil
        }
        window.delegate = delegate
        
        print("MenuBarManager: Window setup complete")
        
        return window
    }
}

// Window delegate to handle window closing
class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

extension Notification.Name {
    static let navigateToDestination = Notification.Name("navigateToDestination")
}
