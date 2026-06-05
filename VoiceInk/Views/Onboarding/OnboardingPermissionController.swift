import AVFoundation
import AppKit
import ApplicationServices

@MainActor
final class OnboardingPermissionController {
    private unowned let coordinator: OnboardingCoordinator

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
    }

    func stepNumber(for permission: OnboardingPermissionKind) -> Int {
        guard let index = OnboardingPermissionKind.allCases.firstIndex(of: permission) else {
            return 1
        }

        return index + 1
    }

    func status(for permission: OnboardingPermissionKind) -> OnboardingPermissionStatus {
        coordinator.permissionStatuses[permission] ?? diagnose(permission)
    }

    func setActivePermission(_ permission: OnboardingPermissionKind) {
        coordinator.storedActivePermission = permission.rawValue
    }

    func refreshPermissionStatuses() {
        let diagnosedStatuses = Dictionary(
            uniqueKeysWithValues: OnboardingPermissionKind.allCases.map { permission in
                (permission, diagnose(permission))
            }
        )

        coordinator.permissionStatuses = diagnosedStatuses
        reconcileActivePermission(with: diagnosedStatuses)
    }

    func reconcileActivePermission(with statuses: [OnboardingPermissionKind: OnboardingPermissionStatus]) {
        if let storedPermission = OnboardingPermissionKind(rawValue: coordinator.storedActivePermission),
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
        isLocked(permission, statuses: coordinator.permissionStatuses)
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

    func actionTitle(for permission: OnboardingPermissionKind) -> String {
        let permissionStatus = status(for: permission)

        if permissionStatus.isGranted {
            return "Done"
        }

        switch permission {
        case .microphone:
            return permissionStatus.requiresSettings ? "Open Settings" : "Allow"
        case .accessibility, .screenRecording:
            return "Allow"
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

    func cancelRefreshTask() {
        coordinator.refreshTask?.cancel()
        coordinator.refreshTask = nil
    }

    private func diagnose(_ permission: OnboardingPermissionKind) -> OnboardingPermissionStatus {
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

    private func handleMicrophoneAction() {
        if status(for: .microphone).requiresSettings {
            openPrivacySettings(.microphone)
            startPollingPermissionStatus()
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshPermissionStatuses()
                self?.startPollingPermissionStatus()
            }
        }
    }

    private func requestAccessibility() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
        openPrivacySettings(.accessibility)
        startPollingPermissionStatus()
    }

    private func requestScreenRecording() {
        coordinator.hasRequestedScreenRecording = true
        startPollingPermissionStatus()

        Task { @MainActor [weak self] in
            guard let self else { return }

            let isGranted = await ScreenCaptureService.requestScreenCapturePermissionRegistration()
            refreshPermissionStatuses()

            if !isGranted {
                openPrivacySettings(.screenRecording)
            }
        }
    }

    private func advanceFrom(_ permission: OnboardingPermissionKind) {
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

    private func startPollingPermissionStatus() {
        cancelRefreshTask()
        coordinator.refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for _ in 0..<60 {
                guard !Task.isCancelled else { return }
                refreshPermissionStatuses()

                if coordinator.requiredPermissionsGranted {
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func openPrivacySettings(_ pane: PrivacySettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
