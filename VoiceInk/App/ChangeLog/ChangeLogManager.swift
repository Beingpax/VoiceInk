import Foundation
import SwiftUI

struct ChangeLogItem: Identifiable {
    let id: String
    let title: LocalizedStringKey
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
        title: "Dictionary Auto Learn",
        summary:
            "Fix a word after VoiceInk pastes it, and Auto Learn can turn that edit into a reusable Dictionary replacement. Names and phrases become more accurate without entering every rule yourself.",
        youtubeVideoID: "YEDxTrr1Jco"
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
    private let wasOnboardedAtLaunch: Bool

    init(
        defaults: UserDefaults = .standard,
        item: ChangeLogItem = ChangeLogCatalog.latest
    ) {
        self.defaults = defaults
        self.item = item
        wasOnboardedAtLaunch = defaults.bool(forKey: "hasCompletedOnboardingV2")
    }

    var isPresenting: Bool {
        presentedItem != nil
    }

    func presentIfNeeded() {
        // First-time users already learn the app through onboarding. Mark this
        // release item as seen so it does not interrupt their second launch.
        guard wasOnboardedAtLaunch else {
            rememberDismissal(of: item.id)
            return
        }
        guard presentedItem == nil else { return }
        guard !dismissedItemIDs.contains(item.id) else { return }

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
