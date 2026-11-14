# Security Policy

Contact: [GitHub Private Vulnerability Reporting](https://github.com/Beingpax/VoiceInk/security/advisories/new)

Based on: https://supabase.com/.well-known/security.txt

VoiceInk is a macOS app that captures audio, transcribes it, and types the result into other apps. It handles your microphone, your screen context, your transcripts, and your API keys. We consider the security of the app and its users a top priority. No matter how much effort we put into security, vulnerabilities can still be present.

If you discover a vulnerability, we would like to know about it so we can address it as quickly as possible. We ask you to help us better protect our users.

## Supported versions

- Latest release: supported.
- Older releases: not supported, please retest on the latest version.
- Forks and self-modified builds: not supported.
- Local `make local` builds differ from release builds. Issues that only affect a locally modified binary are generally out of scope.

## In scope

- API key and license key storage, retrieval, and migration (Keychain, `UserDefaults`, logs, exports, temp files).
- License activation and offline validation bypass.
- The `VoiceInkRefineXPC` service: request validation, path handling, resource limits.
- Update integrity: Sparkle feed trust, EdDSA signature checks, downgrade handling.
- Model and asset downloads: origin checks, checksum verification, archive path traversal or symlink escape.
- Custom endpoint handling: HTTPS enforcement, localhost exemption, key forwarding to unintended hosts.
- Injection sinks: transcript, model output, or remote config reaching AppleScript, Apple Events, shell, URL open, or file paths.
- Privacy boundaries: audio, screen captures, transcripts, or clipboard data sent somewhere unexpected.
- Entitlements and signing issues that enable code injection or TCC bypass.
- Remote config and announcements content that can cause code execution or phishing UI.
- Supply chain issues affecting the shipped build.

## Out of scope

- Issues requiring physical access to an unlocked device, a compromised account, or a jailbroken system.
- Clickjacking, CSRF, or missing security headers on pages with no sensitive actions.
- Vulnerabilities in third party providers (OpenAI, Anthropic, Google, Groq, Deepgram, ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral, OpenRouter, xAI, Cerebras, Polar). Report these to the provider.
- Vulnerabilities in upstream dependencies (Sparkle, whisper.cpp, FluidAudio, transcribe.cpp) not caused by our integration.
- Denial of service, including crashes from deliberately malformed or oversized local files with no attack path.
- Scanner output, best practice suggestions, or hardening requests with no demonstrated impact.
- Social engineering, phishing, spam, or attacks on third party applications.
- License cracking or piracy discussions.

## Please do the following

- Report privately through GitHub Security Advisories. Do not open a public issue, discussion, or pull request.
- Do not run automated scanners against our infrastructure. If you want to, contact us and we will set up a sandbox.
- Do not take advantage of the vulnerability, for example by downloading more data than needed or modifying other people's data.
- Do not reveal the problem to others until it has been resolved.
- Do not use attacks on physical security, social engineering, denial of service, spam, or third party applications.
- Use your own installation, accounts, API keys, and data.
- Do not attach real transcripts, audio, or API keys. Redact personal data and secrets.
- Provide enough information to reproduce the issue: version and build, macOS version, steps, proof of concept, and impact. Complex issues may need more detail.

## What we promise

- We will respond within 3 business days with an evaluation and an expected resolution date.
- If you followed the instructions above, we will not take legal action against you regarding the report.
- We will handle your report with strict confidentiality and will not share your personal details with third parties without your permission.
- We will keep you informed of progress.
- We will credit you as the discoverer in public information about the issue, unless you prefer otherwise.
- We will resolve issues as quickly as possible and work with you on publication after a fix ships.

## Disclosure timeline

These are best effort targets for a small project, not a contractual SLA.

- Acknowledge: 3 business days.
- Triage and severity: 10 business days.
- Fix for critical or high severity: next release, expedited where practical.
- Fix for medium or low severity: next scheduled release.
- Public advisory: after the fix ships, or 90 days after triage, whichever is sooner.

If a report needs faster publication, for example because of active exploitation, tell us and we will coordinate timing and a mitigation note.

## Intentional design

Please do not report these as vulnerabilities unless you can show impact beyond the documented behavior.

- Audio is transcribed on device by default. Cloud providers are opt in and use a key you supply.
- API keys and license data are stored in the Keychain, not in plain `UserDefaults`.
- Custom endpoints must use HTTPS. Plain HTTP is allowed only for `localhost`, `127.0.0.1`, and `::1` to support local servers such as Ollama.
- Microphone, Accessibility, Screen Recording, and Apple Events access are required for core features and are gated by macOS consent.
- The release build is outside the App Sandbox because it must control other apps and read screen context. It relies on code signing, notarization, and hardened runtime.
- Updates are verified with an EdDSA public key pinned in `Info.plist`.
- Large model inference runs in the `VoiceInkRefineXPC` service, isolated from the main app.
- The source is public under GPL-3.0. Public source code is not by itself a disclosure issue. An exploitable path in a shipped build is.

## No bounty

We do not operate a paid bug bounty program. Reports are handled as a courtesy, with public credit as thanks.

## Questions

For questions about this policy, scope, or disclosure timing, use the private advisory channel above. For regular bugs and feature requests, use the issue templates.
