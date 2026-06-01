import SwiftUI
import AVFoundation
import AppKit
import ApplicationServices

extension OnboardingView {
    var permissionList: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingPermissionKind.allCases) { permission in
                PermissionStepRow(
                    stepNumber: stepNumber(for: permission),
                    descriptor: permission.descriptor,
                    status: status(for: permission),
                    isActive: !requiredPermissionsGranted && activePermission == permission,
                    isLocked: isLocked(permission),
                    showsRestartHint: permission == .screenRecording &&
                        hasRequestedScreenRecording &&
                        !status(for: .screenRecording).isGranted,
                    actionTitle: actionTitle(for: permission),
                    onSelect: {
                        guard !isLocked(permission) else { return }
                        setActivePermission(permission)
                    },
                    onAction: {
                        performAction(for: permission)
                    },
                    onQuit: {
                        NSApplication.shared.terminate(nil)
                    }
                )
            }
        }
    }

    func stepNumber(for permission: OnboardingPermissionKind) -> Int {
        guard let index = OnboardingPermissionKind.allCases.firstIndex(of: permission) else {
            return 1
        }

        return index + 1
    }

    func status(for permission: OnboardingPermissionKind) -> OnboardingPermissionStatus {
        permissionStatuses[permission] ?? diagnose(permission)
    }

    func setActivePermission(_ permission: OnboardingPermissionKind) {
        storedActivePermission = permission.rawValue
    }

    func refreshPermissionStatuses() {
        let diagnosedStatuses = Dictionary(
            uniqueKeysWithValues: OnboardingPermissionKind.allCases.map { permission in
                (permission, diagnose(permission))
            }
        )

        permissionStatuses = diagnosedStatuses
        reconcileActivePermission(with: diagnosedStatuses)
    }

    func reconcileActivePermission(with statuses: [OnboardingPermissionKind: OnboardingPermissionStatus]) {
        if let storedPermission = OnboardingPermissionKind(rawValue: storedActivePermission),
           !isLocked(storedPermission, statuses: statuses),
           !storedPermission.isRequired || !(statuses[storedPermission] ?? diagnose(storedPermission)).isGranted {
            return
        }

        if let firstMissingRequired = OnboardingPermissionKind.required.first(where: {
            !(statuses[$0] ?? diagnose($0)).isGranted
        }) {
            setActivePermission(firstMissingRequired)
            return
        }

        if let lastPermission = OnboardingPermissionKind.allCases.last {
            setActivePermission(lastPermission)
        }
    }

    func isLocked(_ permission: OnboardingPermissionKind) -> Bool {
        isLocked(permission, statuses: permissionStatuses)
    }

    func isLocked(
        _ permission: OnboardingPermissionKind,
        statuses: [OnboardingPermissionKind: OnboardingPermissionStatus]
    ) -> Bool {
        guard let index = OnboardingPermissionKind.allCases.firstIndex(of: permission) else {
            return false
        }

        let priorRequiredPermissions = OnboardingPermissionKind.allCases[..<index].filter(\.isRequired)
        return priorRequiredPermissions.contains { !(statuses[$0] ?? diagnose($0)).isGranted }
    }

    func diagnose(_ permission: OnboardingPermissionKind) -> OnboardingPermissionStatus {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                return .granted
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .needsAccess
            @unknown default:
                return .unknown
            }

        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .needsAccess

        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .needsAccess
        }
    }

    func actionTitle(for permission: OnboardingPermissionKind) -> String {
        let permissionStatus = status(for: permission)

        if permissionStatus.isGranted {
            return "Done"
        }

        switch permission {
        case .microphone:
            return permissionStatus.requiresSettings ? "Open Settings" : "Allow"
        case .accessibility, .screenRecording:
            return "Open Settings"
        }
    }

    func performAction(for permission: OnboardingPermissionKind) {
        guard !isLocked(permission) else { return }

        setActivePermission(permission)

        if status(for: permission).isGranted {
            advanceFrom(permission)
            return
        }

        switch permission {
        case .microphone:
            handleMicrophoneAction()
        case .accessibility:
            requestAccessibility()
        case .screenRecording:
            requestScreenRecording()
        }
    }

    func handleMicrophoneAction() {
        if status(for: .microphone).requiresSettings {
            openPrivacySettings(.microphone)
            startPollingPermissionStatus()
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                self.refreshPermissionStatuses()
                self.startPollingPermissionStatus()
            }
        }
    }

    func requestAccessibility() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
        openPrivacySettings(.accessibility)
        startPollingPermissionStatus()
    }

    func requestScreenRecording() {
        hasRequestedScreenRecording = true
        CGRequestScreenCaptureAccess()
        openPrivacySettings(.screenRecording)
        startPollingPermissionStatus()
    }

    func advanceFrom(_ permission: OnboardingPermissionKind) {
        guard let currentIndex = OnboardingPermissionKind.allCases.firstIndex(of: permission) else {
            refreshPermissionStatuses()
            return
        }

        let nextPermissions = OnboardingPermissionKind.allCases.dropFirst(currentIndex + 1)
        if let nextRequired = nextPermissions.first(where: { $0.isRequired && !status(for: $0).isGranted }) {
            setActivePermission(nextRequired)
            return
        }

        refreshPermissionStatuses()
    }

    func startPollingPermissionStatus() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            for _ in 0..<60 {
                guard !Task.isCancelled else { return }
                refreshPermissionStatuses()

                if requiredPermissionsGranted {
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func openPrivacySettings(_ pane: PrivacySettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

