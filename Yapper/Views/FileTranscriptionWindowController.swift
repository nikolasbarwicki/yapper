import AppKit
import SwiftUI

// MARK: - File Transcription Window Controller

/// Manages the file transcription window with close confirmation support.
/// Implements NSWindowDelegate to handle the windowShouldClose check during transcription.
@MainActor
final class FileTranscriptionWindowController: NSObject, NSWindowDelegate {

    private var windowController: NSWindowController?
    private let appState: AppState
    private let transcriptionService: TranscriptionService

    /// Callback to cancel the current transcription when window is force-closed
    var cancelHandler: (() -> Void)?

    init(appState: AppState, transcriptionService: TranscriptionService) {
        self.appState = appState
        self.transcriptionService = transcriptionService
        super.init()
    }

    /// Show the file transcription window (creates if needed)
    func showWindow() {
        // If window already exists, just bring it to front
        if let windowController = windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI view with transcription service
        let fileTranscriptionView = FileTranscriptionView(
            transcriptionService: transcriptionService,
            onCancelHandlerReady: { [weak self] handler in
                self?.cancelHandler = handler
            }
        )
        .environment(appState)

        let hostingController = NSHostingController(rootView: fileTranscriptionView)

        // Create the window with explicit size to ensure proper centering
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Transcribe Audio File"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 400))
        window.level = .floating
        window.delegate = self

        // Create the window controller
        let controller = NSWindowController(window: window)
        self.windowController = controller

        // Show the window and center it
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the window
    func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    // MARK: - NSWindowDelegate

    /// Called when the user tries to close the window
    /// We intercept this to show a confirmation if transcription is in progress
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Check if transcription is in progress
        if appState.isTranscribingFile {
            showCancelConfirmation(window: sender)
            return false
        }
        return true
    }

    /// Called when the window is about to close
    func windowWillClose(_ notification: Notification) {
        // Clean up the window controller reference
        windowController = nil
    }

    // MARK: - Private Methods

    private func showCancelConfirmation(window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Cancel Transcription?"
        alert.informativeText = "The transcription is still in progress. Are you sure you want to cancel?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue Transcription")
        alert.addButton(withTitle: "Cancel Transcription")

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn {
                // User chose to cancel - call the cancel handler to properly cancel the task
                self?.cancelHandler?()
                self?.closeWindow()
            }
        }
    }
}
