import AppKit
import SwiftUI

/// Picks the apps where the ambient light should stay off.
///
/// The light covers the whole display, which is right almost everywhere and wrong in a few specific
/// places — a video call where it frames your face, a colour-critical editor, a presentation.
/// Recording is unaffected; only the light goes away.
///
/// Screen capture is handled separately and needs no setting: the panel sets `sharingType = .none`,
/// so it is already absent from recordings and shared screens.
struct AmbientExclusionsSettings: View {
    @AppStorage(AmbientBackgroundMode.userDefaultsKey) private var backgroundMode =
        AmbientBackgroundMode.auto.rawValue
    @State private var bundleIdentifiers: [String] = AmbientAppExclusions.bundleIdentifiers
    @State private var isPickingApp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Ambient Light", selection: $backgroundMode) {
                ForEach(AmbientBackgroundMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)

            Divider().padding(.vertical, 2)
            HStack {
                Text("Hide ambient light in")
                    .font(.system(size: 13))

                InfoTip(
                    "Recording still works normally in these apps — only the light is hidden. Screen recordings never capture it."
                )

                Spacer()

                Button("Add App…") { isPickingApp = true }
                    .controlSize(.small)
            }

            if bundleIdentifiers.isEmpty {
                Text("No apps excluded")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bundleIdentifiers, id: \.self) { identifier in
                    HStack(spacing: 8) {
                        if let icon = Self.icon(for: identifier) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }

                        Text(Self.displayName(for: identifier))
                            .font(.system(size: 12))

                        Spacer()

                        Button {
                            remove(identifier)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(
                                String(
                                    format: String(localized: "Stop excluding %@"),
                                    Self.displayName(for: identifier)
                                )
                            )
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingApp,
            allowedContentTypes: [.application],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            add(urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }

    private func add(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        AmbientAppExclusions.bundleIdentifiers = bundleIdentifiers + identifiers
        bundleIdentifiers = AmbientAppExclusions.bundleIdentifiers
    }

    private func remove(_ identifier: String) {
        AmbientAppExclusions.bundleIdentifiers = bundleIdentifiers.filter { $0 != identifier }
        bundleIdentifiers = AmbientAppExclusions.bundleIdentifiers
    }

    private static func url(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private static func displayName(for bundleIdentifier: String) -> String {
        guard let url = url(for: bundleIdentifier) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path)
    }

    private static func icon(for bundleIdentifier: String) -> NSImage? {
        guard let url = url(for: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
