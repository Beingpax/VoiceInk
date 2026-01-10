import SwiftUI
import LaunchAtLogin

// MARK: - General Settings

extension SettingsView {
    var generalSettings: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            if sectionMatches("App Behavior", in: .general) {
                VoiceInkSection(
                    icon: "gear",
                    title: "App Behavior",
                    subtitle: "Appearance, startup, and updates"
                ) {
                VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                    Toggle("Hide Dock Icon (Menu Bar Only)", isOn: $menuBarManager.isMenuBarOnly)
                        .toggleStyle(.switch)
                    
                    LaunchAtLogin.Toggle()
                        .toggleStyle(.switch)

                    Toggle("Enable automatic update checks", isOn: $autoUpdateCheck)
                        .toggleStyle(.switch)
                        .onChange(of: autoUpdateCheck) { _, newValue in
                            updaterViewModel.toggleAutoUpdates(newValue)
                        }
                    
                    Toggle("Show app announcements", isOn: $enableAnnouncements)
                        .toggleStyle(.switch)
                        .onChange(of: enableAnnouncements) { _, newValue in
                            if newValue {
                                AnnouncementsService.shared.start()
                            } else {
                                AnnouncementsService.shared.stop()
                            }
                        }
                    
                    Button("Check for Updates Now") {
                        updaterViewModel.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!updaterViewModel.canCheckForUpdates)
                    
                    Divider()

                    Button("Reset Onboarding") {
                        showResetOnboardingAlert = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                }
            }
            
            if sectionMatches("Community & License", in: .general) {
                VoiceInkSection(
                    icon: "hands.sparkles.fill",
                    title: "Community & License",
                    subtitle: "Manage your license and community features"
                ) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                        HStack(spacing: VoiceInkSpacing.sm) {
                            Image(systemName: "seal.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(AppBrand.communityName) Edition")
                                    .font(.headline)
                                Text("All features unlocked • Privacy-first • Open source")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        Button("View License & Community Info") {
                            showLicenseSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            
            #if DEBUG
            if #available(macOS 12.0, *), sectionMatches("Performance Metrics", in: .general) {
                VoiceInkSection(
                    icon: "chart.bar.xaxis",
                    title: "Performance Metrics",
                    subtitle: "MetricKit production monitoring (DEBUG only)"
                ) {
                    DebugMetricsView()
                }
            }
            #endif
        }
    }
}