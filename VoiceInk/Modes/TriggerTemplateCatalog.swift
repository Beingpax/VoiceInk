import Foundation

struct TriggerTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let systemImage: String
    let apps: [TriggerTemplateApp]
    let websites: [String]

    func availableGroup(
        installedApps: [InstalledAppInfo],
        existingAppBundleIds: Set<String>,
        existingWebsites: Set<String>,
        cleanURL: (String) -> String
    ) -> ModeTriggerGroup {
        let installedAppsByBundleId = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.bundleId, $0) })
        let appConfigs = apps.compactMap { app -> AppConfig? in
            guard
                let installedApp = installedApp(
                    matching: app,
                    installedApps: installedApps,
                    installedAppsByBundleId: installedAppsByBundleId,
                    existingAppBundleIds: existingAppBundleIds
                )
            else { return nil }
            return AppConfig(bundleIdentifier: installedApp.bundleId, appName: installedApp.name)
        }

        let urlConfigs = websites.compactMap { website -> URLConfig? in
            let cleanedURL = cleanURL(website)
            guard !existingWebsites.contains(cleanedURL) else { return nil }
            return URLConfig(url: cleanedURL)
        }

        return ModeTriggerGroup(
            templateId: id,
            name: name,
            appConfigs: appConfigs,
            urlConfigs: urlConfigs
        )
    }

    private func installedApp(
        matching app: TriggerTemplateApp,
        installedApps: [InstalledAppInfo],
        installedAppsByBundleId: [String: InstalledAppInfo],
        existingAppBundleIds: Set<String>
    ) -> InstalledAppInfo? {
        if let installedApp = installedAppsByBundleId[app.bundleIdentifier],
            !existingAppBundleIds.contains(installedApp.bundleId)
        {
            return installedApp
        }

        let appNames = Set(app.nameHints.map { normalizedAppName($0) })
        guard !appNames.isEmpty else { return nil }

        return installedApps.first { installedApp in
            appNames.contains(normalizedAppName(installedApp.name))
                && !existingAppBundleIds.contains(installedApp.bundleId)
        }
    }

    private func normalizedAppName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

struct TriggerTemplateApp: Equatable {
    let bundleIdentifier: String
    let nameHints: [String]

    init(bundleIdentifier: String, names: [String] = []) {
        self.bundleIdentifier = bundleIdentifier
        self.nameHints = names
    }
}

enum TriggerTemplateCatalog {
    static let templates: [TriggerTemplate] = [
        TriggerTemplate(
            id: "ai",
            name: "AI",
            systemImage: "sparkles",
            apps: [
                .init(bundleIdentifier: "com.openai.codex", names: ["Codex"]),
                .init(bundleIdentifier: "com.openai.chat", names: ["ChatGPT"]),
                .init(bundleIdentifier: "com.anthropic.claudefordesktop", names: ["Claude"]),
                .init(bundleIdentifier: "ai.perplexity.mac", names: ["Perplexity"]),
                .init(bundleIdentifier: "com.todesktop.230313mzl4w4u92", names: ["Cursor"]),
                .init(bundleIdentifier: "com.exafunction.windsurf", names: ["Windsurf"]),
                .init(bundleIdentifier: "dev.kiro.desktop", names: ["Kiro"]),
                .init(bundleIdentifier: "ai.lmstudio.LMStudio", names: ["LM Studio"]),
                .init(bundleIdentifier: "com.ollama.ollama", names: ["Ollama"]),
                .init(bundleIdentifier: "ai.jan", names: ["Jan"]),
                .init(bundleIdentifier: "com.msty.app", names: ["Msty"]),
                .init(bundleIdentifier: "com.microsoft.VSCode", names: ["Visual Studio Code", "Code"]),
                .init(bundleIdentifier: "com.jetbrains.intellij", names: ["IntelliJ IDEA"]),
                .init(bundleIdentifier: "com.jetbrains.WebStorm", names: ["WebStorm"]),
                .init(bundleIdentifier: "com.jetbrains.pycharm", names: ["PyCharm"]),
            ],
            websites: [
                "chatgpt.com", "chat.openai.com", "claude.ai", "perplexity.ai", "gemini.google.com",
                "copilot.microsoft.com", "grok.com",
            ]
        ),
        TriggerTemplate(
            id: "email",
            name: "Email",
            systemImage: "envelope",
            apps: [
                .init(bundleIdentifier: "com.apple.mail", names: ["Mail"]),
                .init(bundleIdentifier: "com.microsoft.Outlook", names: ["Microsoft Outlook", "Outlook"]),
                .init(bundleIdentifier: "com.mimestream.Mimestream", names: ["Mimestream"]),
                .init(bundleIdentifier: "com.readdle.smartemail-Mac", names: ["Spark"]),
                .init(bundleIdentifier: "com.readdle.SparkDesktop", names: ["Spark Desktop"]),
                .init(bundleIdentifier: "io.canarymail.mac", names: ["Canary Mail"]),
                .init(bundleIdentifier: "com.emclient.mailclient", names: ["eM Client"]),
                .init(bundleIdentifier: "ch.protonmail.protonmail", names: ["Proton Mail"]),
                .init(bundleIdentifier: "com.spikenow.spike", names: ["Spike"]),
                .init(bundleIdentifier: "com.freron.MailMate", names: ["MailMate"]),
                .init(bundleIdentifier: "it.bloop.airmail2", names: ["Airmail"]),
                .init(bundleIdentifier: "org.mozilla.thunderbird", names: ["Thunderbird"]),
                .init(bundleIdentifier: "com.getmailspring.mailspring", names: ["Mailspring"]),
                .init(bundleIdentifier: "com.superhuman.mail", names: ["Superhuman"]),
                .init(bundleIdentifier: "com.missiveapp.desktop", names: ["Missive"]),
                .init(bundleIdentifier: "com.edisonmail.desktop", names: ["Edison Mail"]),
                .init(bundleIdentifier: "com.polymail.mac", names: ["Polymail"]),
            ],
            websites: [
                "mail.google.com", "gmail.com", "outlook.live.com", "outlook.office.com", "icloud.com/mail",
                "mail.proton.me", "app.superhuman.com", "app.shortwave.com", "hey.com", "fastmail.com",
                "missiveapp.com",
            ]
        ),
        TriggerTemplate(
            id: "chat",
            name: "Messaging",
            systemImage: "bubble.left.and.bubble.right",
            apps: [
                .init(bundleIdentifier: "com.tinyspeck.slackmacgap", names: ["Slack"]),
                .init(bundleIdentifier: "com.hnc.Discord", names: ["Discord"]),
                .init(bundleIdentifier: "com.microsoft.teams2", names: ["Microsoft Teams", "Teams"]),
                .init(bundleIdentifier: "net.whatsapp.WhatsApp", names: ["WhatsApp"]),
                .init(bundleIdentifier: "org.telegram.desktop", names: ["Telegram"]),
                .init(bundleIdentifier: "ru.keepcoder.Telegram", names: ["Telegram Lite"]),
                .init(bundleIdentifier: "org.whispersystems.signal-desktop", names: ["Signal"]),
                .init(bundleIdentifier: "com.facebook.archon", names: ["Messenger"]),
                .init(bundleIdentifier: "com.apple.MobileSMS", names: ["Messages"]),
                .init(bundleIdentifier: "com.viber.osx", names: ["Rakuten Viber", "Viber"]),
                .init(bundleIdentifier: "jp.naver.line.mac", names: ["LINE"]),
                .init(bundleIdentifier: "com.tencent.xinWeChat", names: ["WeChat"]),
                .init(bundleIdentifier: "im.riot.app", names: ["Element"]),
                .init(bundleIdentifier: "com.automattic.beeper.desktop", names: ["Beeper"]),
            ],
            websites: [
                "slack.com", "discord.com", "teams.microsoft.com", "web.whatsapp.com", "web.telegram.org",
                "messenger.com", "messages.google.com", "chat.google.com", "app.element.io", "web.wechat.com",
                "line.me",
            ]
        ),
        TriggerTemplate(
            id: "writing",
            name: "Writing",
            systemImage: "square.and.pencil",
            apps: [
                .init(bundleIdentifier: "com.apple.Notes", names: ["Notes"]),
                .init(bundleIdentifier: "com.apple.iWork.Pages", names: ["Pages"]),
                .init(bundleIdentifier: "com.microsoft.Word", names: ["Microsoft Word", "Word"]),
                .init(bundleIdentifier: "notion.id", names: ["Notion"]),
                .init(bundleIdentifier: "md.obsidian", names: ["Obsidian"]),
                .init(bundleIdentifier: "net.shinyfrog.bear", names: ["Bear"]),
                .init(bundleIdentifier: "com.lukilabs.lukiapp", names: ["Craft"]),
                .init(bundleIdentifier: "abnerworks.Typora", names: ["Typora"]),
                .init(bundleIdentifier: "com.soulmen.ulysses3", names: ["Ulysses"]),
                .init(bundleIdentifier: "pro.writer.mac", names: ["iA Writer"]),
                .init(bundleIdentifier: "com.agiletortoise.Drafts-OSX", names: ["Drafts"]),
                .init(bundleIdentifier: "com.getupnote.desktop", names: ["UpNote"]),
                .init(bundleIdentifier: "com.literatureandlatte.scrivener3", names: ["Scrivener"]),
            ],
            websites: [
                "docs.google.com", "notion.so", "medium.com", "dropbox.com/paper", "craft.do", "bear.app",
                "ulysses.app",
            ]
        ),
    ]
}
