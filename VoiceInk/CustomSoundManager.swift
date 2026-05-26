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

        var isUsingKey: String { "isUsingCustom\(rawValue.capitalized)Sound" }
        var filenameKey: String { "custom\(rawValue.capitalized)SoundFilename" }
        var builtInSoundKey: String { "selected\(rawValue.capitalized)BuiltInSound" }
        var standardName: String { "Custom\(rawValue.capitalized)Sound" }
        var defaultBuiltInSound: BuiltInSound {
            switch self {
            case .start:
                return .sound1
            case .stop:
                return .sound2
            }
        }
    }

    @Published var isUsingCustomStartSound: Bool {
        didSet { UserDefaults.standard.set(isUsingCustomStartSound, forKey: SoundType.start.isUsingKey) }
    }

    @Published var isUsingCustomStopSound: Bool {
        didSet { UserDefaults.standard.set(isUsingCustomStopSound, forKey: SoundType.stop.isUsingKey) }
    }

    @Published private(set) var selectedStartBuiltInSound: BuiltInSound {
        didSet { UserDefaults.standard.set(selectedStartBuiltInSound.rawValue, forKey: SoundType.start.builtInSoundKey) }
    }

    @Published private(set) var selectedStopBuiltInSound: BuiltInSound {
        didSet { UserDefaults.standard.set(selectedStopBuiltInSound.rawValue, forKey: SoundType.stop.builtInSoundKey) }
    }

    private let maxSoundDuration: TimeInterval = 3.0

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
        self.isUsingCustomStartSound = UserDefaults.standard.bool(forKey: SoundType.start.isUsingKey)
        self.isUsingCustomStopSound = UserDefaults.standard.bool(forKey: SoundType.stop.isUsingKey)
        self.selectedStartBuiltInSound = Self.savedBuiltInSound(for: .start)
        self.selectedStopBuiltInSound = Self.savedBuiltInSound(for: .stop)
        self.customStartSoundFilename = UserDefaults.standard.string(forKey: SoundType.start.filenameKey)
        self.customStopSoundFilename = UserDefaults.standard.string(forKey: SoundType.stop.filenameKey)

        createCustomSoundsDirectoryIfNeeded()
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
        let isUsing = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename
        
        guard isUsing, let filename = filename, let directory = customSoundsDirectory() else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }

    func builtInSoundURL(for type: SoundType) -> URL? {
        selectedBuiltInSound(for: type).bundleURL
    }

    func selectedBuiltInSound(for type: SoundType) -> BuiltInSound {
        switch type {
        case .start:
            return selectedStartBuiltInSound
        case .stop:
            return selectedStopBuiltInSound
        }
    }

    func selectBuiltInSound(_ sound: BuiltInSound, for type: SoundType) {
        switch type {
        case .start:
            selectedStartBuiltInSound = sound
            isUsingCustomStartSound = false
        case .stop:
            selectedStopBuiltInSound = sound
            isUsingCustomStopSound = false
        }

        notifyCustomSoundsChanged()
    }

    func useCustomSound(for type: SoundType) {
        guard getSoundDisplayName(for: type) != nil else { return }

        switch type {
        case .start:
            isUsingCustomStartSound = true
        case .stop:
            isUsingCustomStopSound = true
        }

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
                    isUsingCustomStartSound = true
                } else {
                    customStopSoundFilename = filename
                    isUsingCustomStopSound = true
                }
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
            selectedStartBuiltInSound = type.defaultBuiltInSound
            isUsingCustomStartSound = false
            customStartSoundFilename = nil
        } else {
            selectedStopBuiltInSound = type.defaultBuiltInSound
            isUsingCustomStopSound = false
            customStopSoundFilename = nil
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
        let isUsingCustom = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        return !isUsingCustom && selectedBuiltInSound(for: type) == type.defaultBuiltInSound
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
