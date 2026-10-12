import AppKit
import SwiftData
import SwiftUI

@MainActor
final class QuickHistoryController: NSObject {
    static let shared = QuickHistoryController()

    private var panel: PersistentQuickPanel?
    private var viewModel: QuickHistoryViewModel?
    private var targetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    private override init() {
        super.init()

        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor in
                self?.rememberExternalApplication(application)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
        }
    }

    func show(modelContext: ModelContext, engine: VoiceInkEngine) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            viewModel?.reload()
            return
        }

        targetApplication = resolvedTargetApplication()

        guard let enhancementService = engine.enhancementService else {
            // Quick History's detail actions require the enhancement service.
            // Do not crash if an engine is intentionally configured without it.
            return
        }

        let viewModel = QuickHistoryViewModel(modelContext: modelContext)
        let rootView = QuickHistoryView(
                viewModel: viewModel,
                onPaste: { [weak self] transcription in
                    self?.paste(transcription)
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
            .modelContainer(modelContext.container)
            .environmentObject(engine)
            .environmentObject(enhancementService)

        let hostingController = NSHostingController(rootView: rootView)
        let panel = PersistentQuickPanel(
            size: NSSize(width: 680, height: 470),
            positionDefaultsKey: "VoiceInkHistoryQuickAccessOrigin"
        )
        panel.onEscape = { [weak self] in
            self?.handleEscape()
        }
        panel.onKeyDown = { [weak self] event in
            self?.handlePanelKeyDown(event) ?? false
        }
        panel.onDismissRequest = { [weak self] in
            self?.dismiss()
        }

        panel.contentViewController = hostingController

        self.panel = panel
        self.viewModel = viewModel
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard let panel else { return }

        panel.persistPosition()
        panel.onEscape = nil
        panel.onKeyDown = nil
        panel.onDismissRequest = nil
        self.panel = nil
        viewModel = nil
        panel.orderOut(nil)
        panel.close()
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

        switch event.keyCode {
        case 125 where viewModel?.isShowingDetail == false:
            viewModel?.moveSelection(by: 1)
            return true
        case 126 where viewModel?.isShowingDetail == false:
            viewModel?.moveSelection(by: -1)
            return true
        case 36, 76:
            if modifiers.contains(.command) {
                guard viewModel?.selectedTranscription != nil else { return true }
                viewModel?.isShowingInfo = false
                viewModel?.isShowingDetail = true
            } else {
                pasteSelectedTranscription()
            }
            return true
        default:
            return false
        }
    }

    private func pasteSelectedTranscription() {
        guard let transcription = viewModel?.transcriptionForPaste() else { return }
        performPaste(transcription)
    }

    private func paste(_ requestedTranscription: Transcription) {
        guard
            let transcription = viewModel?.transcriptionForPaste(
                preferredID: requestedTranscription.id
            )
        else {
            return
        }

        performPaste(transcription)
    }

    private func performPaste(_ transcription: Transcription) {
        let text = transcription.preferredHistoryText
        let targetApplication = resolvedTargetApplication() ?? targetApplication
        self.targetApplication = nil
        dismiss()

        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            CursorPaster.pasteAtCursor(text)
        }
    }

    private func resolvedTargetApplication() -> NSRunningApplication? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            isExternalApplication(frontmostApplication)
        {
            rememberExternalApplication(frontmostApplication)
            return frontmostApplication
        }

        if let lastExternalApplication, !lastExternalApplication.isTerminated {
            return lastExternalApplication
        }

        return nil
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application, isExternalApplication(application), !application.isTerminated else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func handleEscape() {
        if viewModel?.isShowingInfo == true {
            viewModel?.isShowingInfo = false
        } else if viewModel?.isShowingDetail == true {
            viewModel?.isShowingDetail = false
        } else if viewModel?.searchText.isEmpty == false {
            viewModel?.clearSearch()
        } else {
            dismiss()
        }
    }
}
