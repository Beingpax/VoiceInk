import Foundation
import UniformTypeIdentifiers

extension AudioSettings.AudioFormat {
    var displayName: String {
        switch self {
        case .mp3:
            return "MP3"
        case .wav:
            return "WAV (Lossless)"
        case .aac:
            return "AAC"
        case .flac:
            return "FLAC (Lossless)"
        case .opus:
            return "OGG Opus"
        }
    }

    var fileExtension: String {
        switch self {
        case .aac:
            return "m4a"
        case .opus:
            return "ogg"
        default:
            return rawValue
        }
    }

    var contentType: UTType? {
        switch self {
        case .opus:
            return UTType(filenameExtension: "ogg")
        default:
            return UTType(filenameExtension: fileExtension)
        }
    }

    init?(fileExtension: String) {
        let normalized = fileExtension.lowercased()
        switch normalized {
        case "mp3":
            self = .mp3
        case "wav":
            self = .wav
        case "aac", "m4a":
            self = .aac
        case "flac":
            self = .flac
        case "ogg", "opus":
            self = .opus
        default:
            return nil
        }
    }
}
