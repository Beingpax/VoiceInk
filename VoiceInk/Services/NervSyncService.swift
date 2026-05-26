import Foundation
import os

/// NervSyncService coordinates deep integrations between VoiceInk transcriptions and the local Nerv Cockpit server on port 3080.
class NervSyncService {
    static let shared = NervSyncService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NervSyncService")
    private let cockpitBaseURL = "http://127.0.0.1:3080"

    private init() {}

    /// Process the final transcribed text: either triggers a custom command or syncs it as a memory log.
    func processTranscription(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Intercept voice commands intended for local/remote agents
        if trimmed.lowercased().contains("agent") {
            logger.notice("🤖 Intercepted agent bus voice command: \(trimmed, privacy: .public)")
            AgentBusService.shared.sendMessage(trimmed, recipientId: "all")
            return
        }

        // Check if the transcription matches a custom automation trigger command
        if let commandEndpoint = parseTriggerCommand(trimmed) {
            logger.notice("🎯 Detected voice command. Triggering cockpit endpoint: \(commandEndpoint, privacy: .public)")
            triggerCockpitEndpoint(path: commandEndpoint, actionName: trimmed)
        } else {
            // Otherwise, sync as a persistent memory in Nerve's database
            logger.notice("📝 No voice command matched. Syncing transcript as a memory log.")
            syncMemoryToCockpit(text: trimmed)
        }
    }

    /// Parses the transcription for trigger keywords (e.g. trigger, run, start) and maps to appropriate Hono API routes.
    private func parseTriggerCommand(_ text: String) -> String? {
        let lower = text.lowercased()

        // 1. Core automation triggers
        if lower.contains("trigger sync") || lower.contains("run sync") || lower.contains("start sync") {
            return "/api/triage/trigger/sync"
        }
        if lower.contains("trigger unsubscribe") || lower.contains("run unsubscribe") || lower.contains("start unsubscribe") {
            return "/api/triage/trigger/unsubscribe"
        }
        if lower.contains("trigger report") || lower.contains("run report") || lower.contains("start report") {
            return "/api/triage/trigger/report"
        }

        // 2. DAG Workflow trigger matching (e.g., "trigger dag daily_report" or "run dag system_audit")
        let pattern = #"\b(trigger|run|start)\s+dag\s+([a-zA-Z0-9_-]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
                if let dagNameRange = Range(match.range(at: 2), in: text) {
                    let dagName = String(text[dagNameRange])
                    return "/api/triage/trigger/dag/\(dagName)"
                }
            }
        }

        return nil
    }

    /// Triggers a specific local cockpit action endpoint via HTTP POST.
    private func triggerCockpitEndpoint(path: String, actionName: String) {
        guard let url = URL(string: cockpitBaseURL + path) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Simple feedback payload
        let payload: [String: String] = ["source": "VoiceInk", "voiceCommand": actionName]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.logger.error("❌ Failed to execute cockpit trigger: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    NotificationManager.shared.showNotification(title: "Voice command failed", type: .error)
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                self?.logger.notice("✓ Successfully executed cockpit action: \(actionName, privacy: .public)")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.logger.error("❌ Cockpit trigger returned status code: \(code, privacy: .public)")
                Task { @MainActor in
                    NotificationManager.shared.showNotification(title: "Command failed (Status \(code))", type: .warning)
                }
            }
        }
        task.resume()
    }

    /// Syncs a normal voice transcript as a memory fact log inside the local Nerve workspace database.
    private func syncMemoryToCockpit(text: String) {
        guard let url = URL(string: cockpitBaseURL + "/api/memories") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format parameters matching Nerve's createMemorySchema
        let payload: [String: Any] = [
            "text": text,
            "section": "Voice Notes",
            "category": "fact",
            "importance": 0.5,
            "agentId": "main"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.logger.error("❌ Failed to sync memory log: \(error.localizedDescription, privacy: .public)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                self?.logger.notice("✓ Successfully synced transcription memory to Nerve cockpit!")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.logger.error("❌ Sync memory returned status code: \(code, privacy: .public)")
            }
        }
        task.resume()
    }
}
