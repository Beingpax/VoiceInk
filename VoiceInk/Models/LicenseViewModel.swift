import Foundation

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case communityEdition
    }

    struct CommunityResource: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let systemImage: String
        let description: String
        let url: URL
    }

    @Published private(set) var licenseState: LicenseState = .communityEdition

    let headline = "VoiceInk Community Edition is fully unlocked."
    let subheadline = "No license keys, no trials, and no upgrade prompts—everything you need ships out of the box."

    let contributionNote = "Consider supporting continued development or sharing improvements with the community."

    private func makeURL(_ string: String) -> URL {
        URL(string: string) ?? URL(string: "https://github.com/tmm22/VoiceInk")!
    }

    var communityResources: [CommunityResource] {
        [
            CommunityResource(
                title: "Star the Repository",
                systemImage: "star.fill",
                description: "Help others discover the project by starring the GitHub repo.",
                url: makeURL("https://github.com/tmm22/VoiceInk")
            ),
            CommunityResource(
                title: "Report an Issue",
                systemImage: "exclamationmark.bubble.fill",
                description: "Found a bug or have an idea? Open an issue and start a conversation.",
                url: makeURL("https://github.com/tmm22/VoiceInk/issues")
            ),
            CommunityResource(
                title: "Join the Discussion",
                systemImage: "bubble.left.and.bubble.right.fill",
                description: "Chat with other contributors, share workflows, and get help.",
                url: makeURL("https://discord.gg/xryDy57nYD")
            )
        ]
    }

    var supportLinks: [CommunityResource] {
        [
            CommunityResource(
                title: "Sponsor Development",
                systemImage: "hands.clap.fill",
                description: "Fund ongoing work via GitHub Sponsors or a one-time contribution.",
                url: makeURL("https://github.com/sponsors/tmm22")
            ),
            CommunityResource(
                title: "Read the Documentation",
                systemImage: "book.fill",
                description: "Explore guides, FAQs, and integration notes for power users.",
                url: makeURL("https://tryvoiceink.com/docs")
            )
        ]
    }
}
