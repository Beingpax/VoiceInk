import Foundation
import SwiftUI

struct ChangeLogItem: Identifiable {
    let id: String
    let summary: LocalizedStringKey
    let youtubeVideoID: String

    var previewImageURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(youtubeVideoID)/maxresdefault.jpg")
    }

    var videoURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoID)")
    }
}

enum ChangeLogCatalog {
    /// Add the next release highlight here with a new stable ID. The manager
    /// remembers dismissed IDs, so each item is presented only once per user.
    static let latest = ChangeLogItem(
        id: "dictionary-auto-learn",
        summary:
            "VoiceInk automatically learns from the corrections you make to improve transcription accuracy over time. Dictionary Auto Learn uses your currently configured AI provider and AI model. You can change them anytime in Dictionary Settings.",
        youtubeVideoID: "29Wy0SkoWk8"
    )
}

@MainActor
final class ChangeLogManager: ObservableObject {
    private enum DefaultsKey {
        static let dismissedItemIDs = "VoiceInkDismissedChangeLogItemIDs"
    }

    @Published private(set) var presentedItem: ChangeLogItem?

    private let defaults: UserDefaults
    private let item: ChangeLogItem

    init(
        defaults: UserDefaults = .standard,
        item: ChangeLogItem = ChangeLogCatalog.latest
    ) {
        self.defaults = defaults
        self.item = item
    }

    var isPresenting: Bool {
        presentedItem != nil
    }

    static func needsPresentation(
        defaults: UserDefaults = .standard,
        item: ChangeLogItem = ChangeLogCatalog.latest
    ) -> Bool {
        defaults.bool(forKey: OnboardingSettings.completedV2Key)
            && !(defaults.stringArray(forKey: DefaultsKey.dismissedItemIDs) ?? []).contains(item.id)
    }

    func presentIfNeeded() {
        guard Self.needsPresentation(defaults: defaults, item: item) else { return }
        guard presentedItem == nil else { return }

        presentedItem = item
    }

    func dismiss() {
        guard let item = presentedItem else { return }
        rememberDismissal(of: item.id)
        presentedItem = nil
    }

    private func rememberDismissal(of itemID: String) {
        var itemIDs = dismissedItemIDs
        guard !itemIDs.contains(itemID) else { return }

        itemIDs.append(itemID)
        defaults.set(Array(itemIDs.suffix(20)), forKey: DefaultsKey.dismissedItemIDs)
    }

    private var dismissedItemIDs: [String] {
        defaults.stringArray(forKey: DefaultsKey.dismissedItemIDs) ?? []
    }
}
