import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut Recorder View

/// A view that captures keyboard shortcuts when clicked.
/// Shows the current shortcut and allows recording a new one.
struct ShortcutRecorderView: View {
    let shortcutType: ShortcutType
    @Binding var shortcut: KeyboardShortcut
    let onShortcutChanged: (KeyboardShortcut) -> Void

    @State private var isRecording = false
    @State private var showInvalidAlert = false

    var body: some View {
        HStack(spacing: 8) {
            // Shortcut display / recording indicator
            Button(action: { startRecording() }) {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Press shortcut...")
                            .foregroundStyle(.secondary)
                            .font(.system(.caption, design: .rounded))
                    } else {
                        KeyboardShortcutView(keys: shortcut.displayKeys)
                    }
                }
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Reset button
            if shortcut != shortcutType.defaultShortcut {
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
        .alert("Invalid Shortcut", isPresented: $showInvalidAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please add at least one modifier key (⌘, ⌥, ⌃, or ⇧) for this key.")
        }
        .background(
            ShortcutRecorderEventHandler(
                isRecording: $isRecording,
                onKeyEvent: handleNSEvent
            )
        )
    }

    // MARK: - Actions

    private func startRecording() {
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
    }

    private func resetToDefault() {
        shortcut = shortcutType.defaultShortcut
        onShortcutChanged(shortcut)
    }

    // MARK: - Key Handling

    private func handleNSEvent(_ event: NSEvent) {
        guard isRecording else { return }

        // Escape without modifiers cancels recording
        if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            stopRecording()
            return
        }

        // Create the new shortcut
        guard let newShortcut = KeyboardShortcut(from: event) else { return }

        // Validate the shortcut
        guard newShortcut.isValid else {
            showInvalidAlert = true
            return
        }

        // Update the shortcut
        shortcut = newShortcut
        onShortcutChanged(newShortcut)
        stopRecording()
    }
}

// MARK: - NSEvent Handler

/// A hidden view that captures NSEvents for keyboard shortcut recording.
/// This is necessary because SwiftUI's onKeyPress doesn't provide raw key codes.
struct ShortcutRecorderEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onKeyEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.isRecordingEnabled = isRecording
        nsView.onKeyEvent = onKeyEvent

        if isRecording {
            // Make the view first responder to capture key events
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

/// Custom NSView that captures key events for shortcut recording
class ShortcutRecorderNSView: NSView {
    var isRecordingEnabled = false
    var onKeyEvent: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isRecordingEnabled {
            onKeyEvent?(event)
        } else {
            super.keyDown(with: event)
        }
    }

    // Prevent the beep sound when pressing keys
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecordingEnabled {
            onKeyEvent?(event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Shortcut Row View

/// A complete row for editing a shortcut in settings
struct ShortcutSettingRow: View {
    let shortcutType: ShortcutType
    @Binding var shortcut: KeyboardShortcut
    let onShortcutChanged: (KeyboardShortcut) -> Void

    var body: some View {
        HStack {
            Text(shortcutType.displayName)
            Spacer()
            ShortcutRecorderView(
                shortcutType: shortcutType,
                shortcut: $shortcut,
                onShortcutChanged: onShortcutChanged
            )
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ShortcutSettingRow(
            shortcutType: .recordingToggle,
            shortcut: .constant(.defaultRecordingToggle),
            onShortcutChanged: { _ in }
        )

        ShortcutSettingRow(
            shortcutType: .cancelRecording,
            shortcut: .constant(.defaultCancelRecording),
            onShortcutChanged: { _ in }
        )
    }
    .padding()
    .frame(width: 400)
}
