import Foundation
import AVFoundation
import SwiftUI

class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    enum BuiltInSound: String, CaseIterable, Identifiable {
        case sound1
        case sound2
        case sound3
        case sound4
        case sound5
        case sound6
        case sound7

        var id: String { rawValue }

        var displayName: String {
            "Sound \(number)"
        }

        var fileExtension: String {
            switch self {
            case .sound1, .sound2, .sound3, .sound4, .sound7:
                return "wav"
            case .sound5, .sound6:
                return "mp3"
            }
        }

        var bundleURL: URL? {
            Bundle.main.url(forResource: rawValue, withExtension: fileExtension) ??
                Bundle.main.url(forResource: rawValue, withExtension: fileExtension, subdirectory: "Sounds")
        }

        private var number: Int {
            Int(rawValue.replacingOccurrences(of: "sound", with: "")) ?? 0
        }
    }

    enum SoundType: String {
        case start
        case stop

        var selectionKey: String { "selected\(rawValue.capitalized)SoundSelection" }
        var filenameKey: String { "custom\(rawValue.capitalized)SoundFilename" }
        var builtInSoundKey: String { "selected\(rawValue.capitalized)BuiltInSound" }
        var standardName: String { "Custom\(rawValue.capitalized)Sound" }
        var defaultBuiltInSound: BuiltInSound {
            switch self {
            case .start:
                return .sound5
            case .stop:
                return .sound6
            }
        }
    }

    enum SoundSelection: Equatable {
        case none
        case builtIn(BuiltInSound)
        case custom(String)

        var isEnabled: Bool {
            self != .none
        }

        var isCustom: Bool {
            if case .custom = self {
                return true
            }
            return false
        }

        fileprivate var storageValue: String {
            switch self {
            case .none:
                return "none"
            case .builtIn:
                return "builtIn"
            case .custom:
                return "custom"
            }
        }
    }

    private let maxSoundDuration: TimeInterval = 3.0

    @Published private var startSoundSelection: SoundSelection {
        didSet {
            saveSoundSelection(startSoundSelection, for: .start)
        }
    }

    @Published private var stopSoundSelection: SoundSelection {
        didSet {
            saveSoundSelection(stopSoundSelection, for: .stop)
        }
    }

    private var startBuiltInSound: BuiltInSound {
        didSet { UserDefaults.standard.set(startBuiltInSound.rawValue, forKey: SoundType.start.builtInSoundKey) }
    }

    private var stopBuiltInSound: BuiltInSound {
        didSet { UserDefaults.standard.set(stopBuiltInSound.rawValue, forKey: SoundType.stop.builtInSoundKey) }
    }

    private var customStartSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStartSoundFilename, for: .start) }
    }

    private var customStopSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStopSoundFilename, for: .stop) }
    }

    private func updateFilenameInUserDefaults(filename: String?, for type: SoundType) {
        if let filename = filename {
            UserDefaults.standard.set(filename, forKey: type.filenameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: type.filenameKey)
        }
    }

    private init() {
        let savedStartBuiltInSound = Self.savedBuiltInSound(for: .start)
        let savedStopBuiltInSound = Self.savedBuiltInSound(for: .stop)
        let savedStartFilename = UserDefaults.standard.string(forKey: SoundType.start.filenameKey)
        let savedStopFilename = UserDefaults.standard.string(forKey: SoundType.stop.filenameKey)
        let legacySoundFeedbackEnabled = UserDefaults.standard.object(forKey: "isSoundFeedbackEnabled")
            .map { _ in UserDefaults.standard.bool(forKey: "isSoundFeedbackEnabled") }

        self.startBuiltInSound = savedStartBuiltInSound
        self.stopBuiltInSound = savedStopBuiltInSound
        self.customStartSoundFilename = savedStartFilename
        self.customStopSoundFilename = savedStopFilename
        self.startSoundSelection = Self.savedSoundSelection(
            for: .start,
            builtInSound: savedStartBuiltInSound,
            customFilename: savedStartFilename,
            legacySoundFeedbackEnabled: legacySoundFeedbackEnabled
        )
        self.stopSoundSelection = Self.savedSoundSelection(
            for: .stop,
            builtInSound: savedStopBuiltInSound,
            customFilename: savedStopFilename,
            legacySoundFeedbackEnabled: legacySoundFeedbackEnabled
        )

        createCustomSoundsDirectoryIfNeeded()
        saveSoundSelection(startSoundSelection, for: .start)
        saveSoundSelection(stopSoundSelection, for: .stop)
    }

    private static func savedSoundSelection(
        for type: SoundType,
        builtInSound: BuiltInSound,
        customFilename: String?,
        legacySoundFeedbackEnabled: Bool?
    ) -> SoundSelection {
        switch UserDefaults.standard.string(forKey: type.selectionKey) {
        case "none":
            return .none
        case "custom":
            return customFilename.map(SoundSelection.custom) ?? .builtIn(builtInSound)
        case nil:
            guard let legacySoundFeedbackEnabled else {
                return .builtIn(builtInSound)
            }
            return legacySoundFeedbackEnabled ? .builtIn(builtInSound) : .none
        default:
            return .builtIn(builtInSound)
        }
    }

    private static func savedBuiltInSound(for type: SoundType) -> BuiltInSound {
        if let rawValue = UserDefaults.standard.string(forKey: type.builtInSoundKey),
           let sound = BuiltInSound(rawValue: rawValue) {
            return sound
        }

        return type.defaultBuiltInSound
    }

    private func customSoundsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("VoiceInk/CustomSounds")
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func getCustomSoundURL(for type: SoundType) -> URL? {
        guard case .custom(let filename) = soundSelection(for: type),
              let directory = customSoundsDirectory() else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }

    func builtInSoundURL(for type: SoundType) -> URL? {
        switch soundSelection(for: type) {
        case .none:
            return nil
        case .builtIn(let sound):
            return sound.bundleURL
        case .custom:
            return storedBuiltInSound(for: type).bundleURL
        }
    }

    var hasAnyRecordingSoundEnabled: Bool {
        startSoundSelection.isEnabled || stopSoundSelection.isEnabled
    }

    func isSoundEnabled(for type: SoundType) -> Bool {
        soundSelection(for: type).isEnabled
    }

    func soundSelection(for type: SoundType) -> SoundSelection {
        switch type {
        case .start:
            return startSoundSelection
        case .stop:
            return stopSoundSelection
        }
    }

    private func storedBuiltInSound(for type: SoundType) -> BuiltInSound {
        switch type {
        case .start:
            return startBuiltInSound
        case .stop:
            return stopBuiltInSound
        }
    }

    private func setSoundSelection(_ selection: SoundSelection, for type: SoundType) {
        switch type {
        case .start:
            startSoundSelection = selection
        case .stop:
            stopSoundSelection = selection
        }
    }

    private func saveSoundSelection(_ selection: SoundSelection, for type: SoundType) {
        UserDefaults.standard.set(selection.storageValue, forKey: type.selectionKey)
    }

    func selectNoSound(for type: SoundType) {
        switch type {
        case .start:
            startSoundSelection = .none
        case .stop:
            stopSoundSelection = .none
        }
        notifyCustomSoundsChanged()
    }

    func selectBuiltInSound(_ sound: BuiltInSound, for type: SoundType) {
        switch type {
        case .start:
            startBuiltInSound = sound
            startSoundSelection = .builtIn(sound)
        case .stop:
            stopBuiltInSound = sound
            stopSoundSelection = .builtIn(sound)
        }

        notifyCustomSoundsChanged()
    }

    func useCustomSound(for type: SoundType) {
        guard let filename = getSoundDisplayName(for: type) else { return }
        setSoundSelection(.custom(filename), for: type)

        notifyCustomSoundsChanged()
    }

    func setCustomSound(url: URL, for type: SoundType) -> Result<Void, CustomSoundError> {
        let result = validateAudioFile(url: url)
        switch result {
        case .success:
            let copyResult = copySoundFile(from: url, standardName: type.standardName)
            switch copyResult {
            case .success(let filename):
                if type == .start {
                    customStartSoundFilename = filename
                } else {
                    customStopSoundFilename = filename
                }
                setSoundSelection(.custom(filename), for: type)
                notifyCustomSoundsChanged()
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func resetSoundToDefault(for type: SoundType) {
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename

        if let filename = filename, let directory = customSoundsDirectory() {
            let fileURL = directory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: fileURL)
        }

        if type == .start {
            startBuiltInSound = type.defaultBuiltInSound
            customStartSoundFilename = nil
            startSoundSelection = .builtIn(type.defaultBuiltInSound)
        } else {
            stopBuiltInSound = type.defaultBuiltInSound
            customStopSoundFilename = nil
            stopSoundSelection = .builtIn(type.defaultBuiltInSound)
        }
        notifyCustomSoundsChanged()
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("CustomSoundsChanged"), object: nil)
    }

    func getSoundDisplayName(for type: SoundType) -> String? {
        return (type == .start) ? customStartSoundFilename : customStopSoundFilename
    }

    func isDefaultSelection(for type: SoundType) -> Bool {
        soundSelection(for: type) == .builtIn(type.defaultBuiltInSound)
    }

    private func copySoundFile(from sourceURL: URL, standardName: String) -> Result<String, CustomSoundError> {
        guard let directory = customSoundsDirectory() else {
            return .failure(.directoryCreationFailed)
        }

        let fileExtension = sourceURL.pathExtension
        let newFilename = "\(standardName).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(newFilename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return .success(newFilename)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return .success(newFilename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }

    private func validateAudioFile(url: URL) -> Result<Void, CustomSoundError> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }

        let asset = AVAsset(url: url)
        let duration = asset.duration.seconds

        guard duration.isFinite && duration > 0 else {
            return .failure(.invalidAudioFile)
        }

        if duration > maxSoundDuration {
            return .failure(.durationTooLong(duration: duration, maxDuration: maxSoundDuration))
        }

        do {
            _ = try AVAudioPlayer(contentsOf: url)
        } catch {
            return .failure(.invalidAudioFile)
        }

        return .success(())
    }
}

enum CustomSoundError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .durationTooLong(let duration, let maxDuration):
            return String(format: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter for start and stop sounds.", duration, maxDuration)
        case .directoryCreationFailed:
            return "Failed to create custom sounds directory"
        case .fileCopyFailed:
            return "Failed to copy audio file"
        }
    }
}
