import Foundation
import Carbon
import OSLog

final class KeyboardInputSourceMonitor: ObservableObject {
    static let shared = KeyboardInputSourceMonitor()

    @Published private(set) var currentKeyboardLanguage: String = ""
    @Published private(set) var currentKeyboardDisplayName: String = ""

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeyboardInputSourceMonitor")
    private var isMonitoring = false

    private init() {
        updateCurrentKeyboard()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardInputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        logger.debug("Started monitoring keyboard input source changes")
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        logger.debug("Stopped monitoring keyboard input source changes")
    }

    @objc private func keyboardInputSourceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateCurrentKeyboard()
            self?.syncLanguageIfEnabled()
        }
    }

    private func updateCurrentKeyboard() {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            logger.warning("Could not get current keyboard input source")
            return
        }

        if let languagePtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(languagePtr).takeUnretainedValue() as? [String]
            if let primaryLanguage = languages?.first {
                currentKeyboardLanguage = primaryLanguage
            }
        }

        if let namePtr = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            currentKeyboardDisplayName = name
        }

        logger.debug("Keyboard changed to: \(self.currentKeyboardDisplayName) (\(self.currentKeyboardLanguage))")
    }

    func syncLanguageIfEnabled() {
        let autoSwitch = UserDefaults.standard.bool(forKey: "AutoSwitchLanguageByKeyboard")
        guard autoSwitch else { return }

        let mappedLanguage = mapKeyboardToAppLanguage(currentKeyboardLanguage)

        guard isLanguageSupported(mappedLanguage) else {
            logger.info("Keyboard language '\(self.currentKeyboardLanguage)' maps to '\(mappedLanguage)' which is not supported by current model")
            return
        }

        let currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        guard mappedLanguage != currentLanguage else { return }

        UserDefaults.standard.set(mappedLanguage, forKey: "SelectedLanguage")
        logger.info("Auto-switched language from '\(currentLanguage)' to '\(mappedLanguage)' based on keyboard")

        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func mapKeyboardToAppLanguage(_ keyboardLanguage: String) -> String {
        let baseCode = keyboardLanguage.components(separatedBy: "-").first ?? keyboardLanguage

        switch keyboardLanguage.lowercased() {
        case let lang where lang.hasPrefix("zh-hans"):
            return "zh"
        case let lang where lang.hasPrefix("zh-hant"):
            return "zh"
        case let lang where lang.hasPrefix("yue-hans"), let lang where lang.hasPrefix("yue-hant"):
            return "yue"
        default:
            break
        }

        switch baseCode.lowercased() {
        case "nb":
            return "no"
        case "cmn":
            return "zh"
        default:
            return baseCode.lowercased()
        }
    }

    private func isLanguageSupported(_ languageCode: String) -> Bool {
        return PredefinedModels.allLanguages.keys.contains(languageCode)
    }
}
