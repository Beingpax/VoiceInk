# Fork Differentiation Opportunities

## Platform Reach & Accessibility
- **Current VoiceInk**: macOS-only app that depends on AppKit/SwiftUI infrastructure and officially targets macOS 14+.  
- **Fork Angle**: Deliver a cross-platform or broader Apple ecosystem build (older macOS, Catalyst/iPad, iPhone companion, or a Swift/Flutter reimplementation for Windows/Linux) with shared preferences and model storage.  
- **Why It Differentiates**: Expands the addressable market (enterprise fleets stuck on older OS versions, teams that float between desktop and mobile) and unlocks multi-device workflows competitors neglect.  
- **References**: `README.md:59`, `VoiceInk/VoiceInk.swift:4`

## Community & Licensing Philosophy
- **Current VoiceInk**: Ships with a gated “VoiceInk Pro” experience and paywall UI, and contributions are tightly stewarded by maintainers.  
- **Fork Angle**: Reposition as a community-driven distribution—fully free tier, community plugin marketplace, transparent governance, and looser contribution policy.  
- **Why It Differentiates**: Appeals to open-source purists and organizations wary of licensing toggles, while inviting broader contributor energy. **Status: Shipped in VoiceInk Community.**
- **References**: `VoiceInk/Views/ContentView.swift:17`, `VoiceInk/Views/LicenseManagementView.swift:16`, `CONTRIBUTING.md:9`

## Live Overlay & Accessibility Workflows
- **Current VoiceInk**: UX revolves around discrete dashboard/history/settings panes; no persistent, on-screen captioning surface is exposed.  
- **Fork Angle**: Build an always-on caption HUD, configurable teleprompter, or floating transcript timeline with accessibility presets (font, contrast, multi-language subtitles).  
- **Why It Differentiates**: Targets streamers, hard-of-hearing users, and presenters who need live captions without switching apps.  
- **References**: `VoiceInk/Views/ContentView.swift:6`

## Shared Workspaces & Sync
- **Current VoiceInk**: Stores transcripts via SwiftData in the user’s Application Support folder with no sync logic.  
- **Fork Angle**: Introduce optional encrypted cloud sync, team workspaces, and automated backups (iCloud, Nextcloud, Supabase, or self-hosted backends).  
- **Why It Differentiates**: Aligns with team note-taking needs, offers compliance-friendly audit logs, and provides resilience for power users juggling multiple Macs. **Status: Planned.**
- **References**: `VoiceInk/VoiceInk.swift:40`

## Meeting & Conversation Intelligence
- **Current VoiceInk**: Records a single audio channel with a lightweight VAD pipeline; there is no diarization or structured meeting summary stack.  
- **Fork Angle**: Layer in multi-channel capture, speaker diarization, calendar-aware meeting detection, and automated action-item drafting.  
- **Why It Differentiates**: Creates a turnkey alternative to SaaS meeting assistants while keeping processing local or self-hosted.  
- **References**: `VoiceInk/Recorder.swift:92`

## Automation & Extensibility
- **Current VoiceInk**: Automation hinges on global hotkeys and middle-click toggles; no plugin, CLI, or API surface exists.  
- **Fork Angle**: Ship a scriptable engine (Apple Shortcuts, command-line client, HTTP/WebSocket API) and lightweight plugin SDK so users can wire custom post-processing or exports.  
- **Why It Differentiates**: Gives developers and ops teams tooling parity with SaaS transcription services and encourages third-party ecosystem growth. **Status: In progress.**
- **References**: `VoiceInk/HotkeyManager.swift:76`

## Model Onboarding & Ops
- **Current VoiceInk**: Users must juggle API keys and external model choices; only Ollama offers a turnkey local story.  
- **Fork Angle**: Provide curated, auto-updating on-device model bundles, streaming while-downloading, and policy presets (privacy tiers, cost controls) plus self-hosted inference adapters.  
- **Why It Differentiates**: Reduces setup friction, attracts privacy-conscious teams, and positions the fork as the quickest path to productive transcription. **Status: Shipped in VoiceInk Community.**
- **References**: `VoiceInk/Services/AIService.swift:149`
