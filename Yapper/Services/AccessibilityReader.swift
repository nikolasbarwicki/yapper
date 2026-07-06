import AppKit
import ApplicationServices

// MARK: - Accessibility Reader

/// Reads the currently selected text from the frontmost application using the Accessibility API.
///
/// HOW THIS WORKS:
/// 1. Get the frontmost app's PID → create an AXUIElement for it
/// 2. Query for the focused UI element (the text field, editor, etc.)
/// 3. Skip secure text fields (password fields)
/// 4. Read the kAXSelectedTextAttribute to get highlighted text
///
/// ACCESSIBILITY PERMISSION:
/// Yapper must already have Accessibility access for this to work.
/// The same permission used for TextInjector covers reading too.
@MainActor
final class AccessibilityReader {

    /// Maximum allowed selection length to prevent sending huge payloads to the LLM
    static let maxSelectionLength = 10_000

    /// Read the currently selected text from the frontmost application.
    /// Returns nil if:
    /// - No app is frontmost
    /// - No element is focused
    /// - The focused element is a secure text field (password)
    /// - No text is selected
    /// - The AX call times out (200ms)
    /// - Any AX error occurs
    ///
    /// Returning nil is a safe fallback — the caller treats it as "no selection"
    /// and proceeds with normal dictation mode.
    func readSelectedText() -> String? {
        // Run the AX work on a background thread with a timeout,
        // since AX calls can hang if the target app is unresponsive.
        // nonisolated(unsafe) silences the "mutation of captured var in concurrently-executing
        // code" warning — synchronization is handled by the semaphore below.
        nonisolated(unsafe) var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInteractive).async {
            result = self.readSelectedTextSync()
            semaphore.signal()
        }

        // 200ms timeout — if AX hangs, we bail and treat as no selection
        let timeout = semaphore.wait(timeout: .now() + .milliseconds(200))
        if timeout == .timedOut {
            AppLogger.transcription.warning("AX readSelectedText timed out after 200ms")
            return nil
        }

        return result
    }

    /// Synchronous AX reading — called on a background thread.
    /// Must not touch any @MainActor state.
    private nonisolated func readSelectedTextSync() -> String? {
        // 1. Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 2. Get the focused UI element
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusResult == .success, let focusedElement = focusedValue else {
            return nil
        }

        // The focused element is an AXUIElement
        let element = focusedElement as! AXUIElement

        // 3. Check if it's a secure text field (password field) — skip these
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        if roleResult == .success, let role = roleValue as? String {
            // AXSecureTextField is the role for password fields
            if role == "AXSecureTextField" {
                return nil
            }
        }

        // 4. Read the selected text
        var selectedTextValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )

        guard selectedResult == .success, let selectedText = selectedTextValue as? String else {
            return nil
        }

        // Return nil for empty selections (treat same as no selection)
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : selectedText
    }
}
