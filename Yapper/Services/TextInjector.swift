import Foundation
import AppKit
import ApplicationServices

// MARK: - Text Injector

/// Injects text into the currently focused input field by simulating keyboard input.
///
/// HOW THIS WORKS:
/// macOS has an "Accessibility API" that lets apps interact with other apps.
/// We use it to simulate keyboard typing, character by character.
///
/// WHY NOT CLIPBOARD + PASTE?
/// 1. It overwrites the user's clipboard (frustrating)
/// 2. Some apps block paste in certain fields
/// 3. Typing looks more natural (and works in more places)
///
/// ACCESSIBILITY PERMISSION:
/// The user MUST enable Accessibility access for Yapper in:
/// System Settings > Privacy & Security > Accessibility
/// Without this, text injection will silently fail.
@MainActor
final class TextInjector {

    // MARK: - Permission Check

    /// Check if we have Accessibility permission
    var hasPermission: Bool {
        // AXIsProcessTrusted() returns true if we have Accessibility access
        // This is a Carbon API but still works fine
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission
    func requestPermission() {
        // Show the system prompt to enable Accessibility
        // The raw string key for kAXTrustedCheckOptionPrompt is "AXTrustedCheckOptionPrompt"
        // Using the string directly avoids Swift 6 concurrency warnings about the C global
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Text Injection

    /// Type text into the currently focused input field
    /// - Parameter text: The text to type
    func typeText(_ text: String) async throws {
        guard hasPermission else {
            throw TextInjectionError.accessibilityNotEnabled
        }

        print("⌨️ Typing: \(text)")

        // Small delay to ensure the overlay is hidden and focus returns
        try await Task.sleep(for: .milliseconds(100))

        // Type each character
        for character in text {
            try typeCharacter(character)

            // Small delay between characters for reliability
            // This makes it look like natural typing and works better with some apps
            try await Task.sleep(for: .milliseconds(10))
        }

        print("✅ Finished typing")
    }

    /// Type a single character by simulating keyboard events
    private func typeCharacter(_ character: Character) throws {
        // SWIFT CONCEPT: CGEvent
        // CGEvent is Core Graphics' way to create synthetic input events.
        // We create a "key down" event, then a "key up" event.

        // Get the string representation
        let string = String(character)

        // Create a key down event
        // IMPORTANT: We use a generic key code and set the characters directly
        // This handles special characters and non-ASCII text properly
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            throw TextInjectionError.eventCreationFailed
        }

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw TextInjectionError.eventCreationFailed
        }

        // Set the characters for the event
        // This is the trick: instead of figuring out which key to press,
        // we just tell the event "pretend these characters were typed"
        var unicodeChars = Array(string.utf16)
        keyDown.keyboardSetUnicodeString(
            stringLength: unicodeChars.count,
            unicodeString: &unicodeChars
        )

        // Post the events to the system
        // .cghidEventTap means we're injecting at the HID (Human Interface Device) level
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Incremental Typing (for streaming)

    /// Type incremental text without the initial 100ms delay.
    /// Used during streaming transcription where focus is already set.
    /// - Parameter text: The delta text to type
    func typeIncremental(_ text: String) async throws {
        guard hasPermission else {
            throw TextInjectionError.accessibilityNotEnabled
        }

        for character in text {
            try typeCharacter(character)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Type a delta string atomically using CGEvent's multi-character support.
    ///
    /// Unlike `typeIncremental`, this method has NO async suspension points per character.
    /// Each chunk (up to 20 UTF-16 units) is posted as a single CGEvent, making it
    /// impossible for a concurrent task to interleave characters within a chunk.
    /// This is the primary defense against garbled/interleaved streaming output.
    ///
    /// - Parameter text: The delta text to type
    func typeStringAtomically(_ text: String) throws {
        guard hasPermission else {
            throw TextInjectionError.accessibilityNotEnabled
        }

        // CGEventKeyboardSetUnicodeString supports up to 20 UTF-16 units per event
        let maxChunkSize = 20
        let utf16 = Array(text.utf16)

        for chunkStart in stride(from: 0, to: utf16.count, by: maxChunkSize) {
            let chunkEnd = min(chunkStart + maxChunkSize, utf16.count)
            var chunk = Array(utf16[chunkStart..<chunkEnd])

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                throw TextInjectionError.eventCreationFailed
            }
            guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw TextInjectionError.eventCreationFailed
            }

            keyDown.keyboardSetUnicodeString(
                stringLength: chunk.count,
                unicodeString: &chunk
            )
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Delete Selection

    /// Delete the currently selected text by simulating the Delete key.
    /// Used by AI Transform to clear the selection before pasting the transformed result.
    func deleteSelection() async throws {
        guard hasPermission else {
            throw TextInjectionError.accessibilityNotEnabled
        }

        // Virtual key code for Delete (Backspace) is 0x33
        let deleteKeyCode: CGKeyCode = 0x33

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: true) else {
            throw TextInjectionError.eventCreationFailed
        }
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: false) else {
            throw TextInjectionError.eventCreationFailed
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Brief delay for the target app to process the deletion
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Alternative: Clipboard Method

    /// Paste text using clipboard (fallback method)
    /// This overwrites the clipboard but is more reliable in some apps
    func pasteText(_ text: String) async throws {
        // Save current clipboard contents (to restore later)
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set new clipboard contents
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        try await Task.sleep(for: .milliseconds(50))

        // Simulate Cmd+V
        try simulatePaste()

        // Small delay to ensure paste completes
        try await Task.sleep(for: .milliseconds(100))

        // Restore previous clipboard contents
        if let previous = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }

    /// Simulate pressing Cmd+V (paste)
    private func simulatePaste() throws {
        // Create Cmd+V key events
        // Virtual key code for 'V' is 9 (kVK_ANSI_V)
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else {
            throw TextInjectionError.eventCreationFailed
        }

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            throw TextInjectionError.eventCreationFailed
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// MARK: - Errors

enum TextInjectionError: LocalizedError {
    case accessibilityNotEnabled
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotEnabled:
            return "Accessibility permission required. Please enable in System Settings."
        case .eventCreationFailed:
            return "Failed to create keyboard event."
        }
    }
}
