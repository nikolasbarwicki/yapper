import AppKit
import SwiftUI

// MARK: - History Window Controller

/// Manages the dedicated transcript history window.
/// Provides a standalone window for browsing and managing transcript history,
/// separate from the settings window.
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {

    private var windowController: NSWindowController?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Show the history window (creates if needed)
    func showWindow() {
        // If window already exists, just bring it to front
        if let windowController = windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI view
        let historyView = HistoryView(isStandalone: true)
            .environment(appState)

        let hostingController = NSHostingController(rootView: historyView)

        // Create the window
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Transcript History"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 550))
        window.minSize = NSSize(width: 400, height: 400)
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

    /// Called when the window is about to close
    nonisolated func windowWillClose(_ notification: Notification) {
        // Clean up the window controller reference on the main actor
        Task { @MainActor [weak self] in
            self?.windowController = nil
        }
    }
}
