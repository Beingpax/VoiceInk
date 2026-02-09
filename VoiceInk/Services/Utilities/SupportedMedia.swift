import Foundation
import UniformTypeIdentifiers

struct SupportedMedia {
    static let extensions: Set<String> = [
        "wav", "mp3", "m4a", "aiff", "mp4", "mov", "aac", "flac", "caf",
        "amr", "ogg", "oga", "opus", "3gp"
    ]

    static let contentTypes: [UTType] = [
        .audio, .movie
    ]

    static func isSupported(url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if !fileExtension.isEmpty, extensions.contains(fileExtension) {
            return true
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            return contentTypes.contains(where: { contentType.conforms(to: $0) })
        }

        return false
    }
}


