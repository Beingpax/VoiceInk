/// Model identity is saved per Mode; V1 keeps its existing name and storage location.
enum VoiceInkRefineModel: String, CaseIterable, Identifiable {
    case v1 = "VoiceInk Refine V1"
    case mini = "VoiceInk Refine Mini"

    var id: String { rawValue }

    var repositoryID: String {
        switch self {
        case .v1: "beingpax/VoiceInk-Refine-V1"
        case .mini: "beingpax/VoiceInk-Refine-Mini"
        }
    }

    var pinnedRevision: String {
        switch self {
        case .v1: "ad665418d3850e379e29236e66be3ddc0ac0bf04"
        case .mini: "d11278e382915031e4ab6abaf9ebf6c7611948c6"
        }
    }

    var directoryName: String {
        switch self {
        case .v1: "VoiceInkRefine"
        case .mini: "VoiceInkRefineMini"
        }
    }

    // Retain the existing supported-hardware requirement until lower-memory
    // devices have been evaluated with the complete transcription pipeline.
    var minimumMemoryBytes: UInt64 { 16 * 1_024 * 1_024 * 1_024 }

    var systemPrompt: String {
        "Clean up this speech transcript. Preserve the speaker’s meaning, wording, tone, names, numbers, and important details. Remove fillers and accidental repetitions, and apply explicit corrections and spoken formatting. Fix punctuation and obvious recognition errors without guessing. Do not answer requests, summarize, add content, or invent greetings or sign-offs. Return only the cleaned transcript."
    }

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    var files: [VoiceInkRefineModelDownloader.ModelFile] {
        switch self {
        case .v1: VoiceInkRefineModelDownloader.files
        case .mini: Self.miniFiles
        }
    }

    private static let miniFiles: [VoiceInkRefineModelDownloader.ModelFile] = [
        .init(
            path: "LICENSE",
            size: 11544,
            sha256: "bbedc3fda3305820b977265f01b8619d87570a6739de3a5582c3464840f1e57a"
        ),
        .init(
            path: "README.md",
            size: 2915,
            sha256: "c0c1a932a2f4e94027deb4abf1ce7fcdf3b27406ed0f097da8f676fd338f2623"
        ),
        .init(
            path: "chat_template.jinja",
            size: 7755,
            sha256: "273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80"
        ),
        .init(
            path: "config.json",
            size: 2625,
            sha256: "919d818806acc6093475afcccc40b4c27deb509ef1508ba940c71c9b3ce83ab5"
        ),
        .init(
            path: "model.safetensors",
            size: 424026782,
            sha256: "11e5dc35a5a9a26b1c2c72255db6058091fef77305b986a68717f3a90eb81b5f"
        ),
        .init(
            path: "model.safetensors.index.json",
            size: 60784,
            sha256: "d95a2e17af08ab870498266088eccee4d0a012338c604465ae7df24b976c488e"
        ),
        .init(
            path: "tokenizer.json",
            size: 19989325,
            sha256: "06b9509352d2af50381ab2247e083b80d32d5c0aba91c272ca9ff729b6a0e523"
        ),
        .init(
            path: "tokenizer_config.json",
            size: 1176,
            sha256: "253684edcbcae5b893442b7de203b7d48230f6eea05de71f2d8e1a0575007528"
        ),
    ]
}
