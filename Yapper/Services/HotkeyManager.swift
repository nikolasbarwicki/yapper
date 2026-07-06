import AppKit
import Foundation
import HotKey
import Carbon.HIToolbox

// MARK: - Hotkey Manager

/// Manages global keyboard shortcuts for the app.
///
/// WHY GLOBAL SHORTCUTS ARE TRICKY:
/// Normal keyboard events only work when your app is focused.
/// For a menu bar app, we need to capture keystrokes even when
/// other apps are in the foreground. This requires special APIs.
///
/// THE HOTKEY LIBRARY:
/// We're using the "HotKey" library by Sam Soffes, which wraps
/// Apple's Carbon API (yes, Carbon from the 90s - it still works!).
/// It provides a clean Swift interface for global shortcuts.
@MainActor
final class HotkeyManager {

    // MARK: - Properties

    /// Global hotkey for starting/stopping recording
    private var recordingHotkey: HotKey?

    /// Global hotkey for cancelling recording
    private var cancelHotkey: HotKey?

    /// Global hotkey for language toggle
    private var languageToggleHotkey: HotKey?

    /// Global hotkey for auto-type toggle
    private var autoTypeToggleHotkey: HotKey?

    /// Local event monitor for cancel shortcut (more reliable for some keys)
    private var cancelMonitor: Any?

    /// Handler for recording toggle (key-down)
    private var recordingHandler: (() -> Void)?

    /// Handler for cancel recording
    private var cancelHandler: (() -> Void)?

    /// Handler for language toggle
    private var languageToggleHandler: (() -> Void)?

    /// Handler for auto-type toggle
    private var autoTypeToggleHandler: (() -> Void)?

    /// Current cancel shortcut (for local monitor matching)
    private var currentCancelShortcut: KeyboardShortcut?

    // MARK: - Smart Detection Properties

    /// Timestamp when recording shortcut key-down occurred (for mode detection)
    private var recordingKeyDownTime: Date?

    /// Whether we're currently in hold-to-record mode (determined by timing on key-up)
    private var isHoldMode: Bool = false

    /// Legacy global monitor for detecting key-up (kept for cleanup, replaced by CGEventTap)
    private var keyUpMonitor: Any?

    /// CGEventTap for detecting key-up events at the HID level
    /// This is needed because the HotKey library's Carbon handler consumes events
    /// before they reach NSEvent global monitors
    private var eventTap: CFMachPort?

    /// Run loop source for the CGEventTap
    private var runLoopSource: CFRunLoopSource?

    /// Current recording shortcut (needed for matching key-up events)
    private var currentRecordingShortcut: KeyboardShortcut?

    /// Handler called when key is released in hold mode
    private var recordingKeyUpHandler: (() -> Void)?

    /// Threshold in seconds: quick press (<threshold) = toggle, hold (>=threshold) = hold-to-record
    private let holdThresholdSeconds: TimeInterval = 0.3

    // MARK: - Registration

    /// Register the recording toggle hotkey with smart detection (supports both toggle and hold-to-record modes)
    /// - Parameters:
    ///   - shortcut: The keyboard shortcut to register
    ///   - keyDownHandler: Called when the shortcut is pressed (starts recording)
    ///   - keyUpHandler: Called when any key in the combo is released in hold mode (stops recording)
    func registerRecordingHotkey(
        shortcut: KeyboardShortcut,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: @escaping () -> Void
    ) {
        // Store handlers and shortcut for re-registration and event matching
        recordingHandler = keyDownHandler
        recordingKeyUpHandler = keyUpHandler
        currentRecordingShortcut = shortcut

        // Unregister existing hotkey and monitors
        recordingHotkey = nil
        unregisterKeyUpMonitor()

        // Get the HotKey Key from the shortcut
        guard let key = shortcut.hotKeyKey else {
            print("⚠️ Could not create hotkey for recording shortcut")
            return
        }

        // Register the global hotkey for key-down events
        recordingHotkey = HotKey(
            key: key,
            modifiers: shortcut.modifiers.hotKeyModifiers,
            keyDownHandler: { [weak self] in
                self?.handleRecordingKeyDown()
            }
        )

        // Register global monitor for key-up and flags changed events
        registerKeyUpMonitor()

        print("✅ Registered recording hotkey with smart detection: \(shortcut.displayString)")
    }

    /// Internal handler for recording key-down - records timestamp and calls external handler
    private func handleRecordingKeyDown() {
        guard let shortcut = currentRecordingShortcut else {
            print("🎹 Recording hotkey key-down BLOCKED: no shortcut configured")
            return
        }

        print("🎹 Recording hotkey key-down: \(shortcut.displayString) (previous keyDownTime: \(recordingKeyDownTime?.description ?? "nil"))")

        // Record the key-down time for mode detection on key-up
        recordingKeyDownTime = Date()
        isHoldMode = false  // Will be determined when key is released

        // Call the external handler to start recording
        print("🎹 Calling recordingHandler...")
        recordingHandler?()
        print("🎹 recordingHandler completed")
    }

    /// Register the cancel hotkey with a custom shortcut
    func registerCancelHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void) {
        // Store the handler and shortcut for re-registration
        cancelHandler = handler
        currentCancelShortcut = shortcut

        // Unregister existing hotkey and monitor
        cancelHotkey = nil
        if let monitor = cancelMonitor {
            NSEvent.removeMonitor(monitor)
            cancelMonitor = nil
        }

        // Get the HotKey Key from the shortcut
        guard let key = shortcut.hotKeyKey else {
            print("⚠️ Could not create hotkey for cancel shortcut")
            return
        }

        // Use a local event monitor for more reliable key capture
        // This is especially important for Escape and other special keys
        cancelMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self = self,
                  let currentShortcut = self.currentCancelShortcut else {
                return event
            }

            // Check if the event matches the cancel shortcut
            if self.eventMatchesShortcut(event, shortcut: currentShortcut) {
                print("🎹 Cancel hotkey pressed: \(currentShortcut.displayString)")
                handler()
                return nil // Consume the event
            }
            return event // Pass other events through
        }

        // Also register a global hotkey as backup for when app doesn't have focus
        cancelHotkey = HotKey(
            key: key,
            modifiers: shortcut.modifiers.hotKeyModifiers,
            keyDownHandler: {
                print("🎹 Cancel hotkey pressed (global): \(shortcut.displayString)")
                handler()
            }
        )

        print("✅ Registered cancel hotkey: \(shortcut.displayString)")
    }

    /// Unregister the cancel hotkey (frees the key for other apps)
    func unregisterCancelHotkey() {
        cancelHotkey = nil
        if let monitor = cancelMonitor {
            NSEvent.removeMonitor(monitor)
            cancelMonitor = nil
        }
        print("✅ Unregistered cancel hotkey")
    }

    /// Re-register the cancel hotkey using the stored shortcut and handler
    func reregisterCancelHotkey() {
        guard let shortcut = currentCancelShortcut,
              let handler = cancelHandler else { return }
        registerCancelHotkey(shortcut: shortcut, handler: handler)
    }

    /// Check if an NSEvent matches a KeyboardShortcut
    private func eventMatchesShortcut(_ event: NSEvent, shortcut: KeyboardShortcut) -> Bool {
        // Check key code
        guard event.keyCode == UInt16(shortcut.keyCode) else { return false }

        // Check modifiers
        let eventModifiers = KeyboardShortcut.ShortcutModifiers(modifierFlags: event.modifierFlags)
        return eventModifiers == shortcut.modifiers
    }

    // MARK: - Smart Detection (Key-Up Monitoring via CGEventTap)

    /// Register CGEventTap for detecting key releases (for hold-to-record mode)
    /// We use CGEventTap instead of NSEvent.addGlobalMonitorForEvents because
    /// the HotKey library's Carbon handler consumes events before they reach
    /// Cocoa-level monitors. CGEventTap operates at the HID level and sees all events.
    private func registerKeyUpMonitor() {
        // Remove existing monitor/tap first
        unregisterKeyUpMonitor()

        // Create event mask for keyUp and flagsChanged events
        let eventMask = (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // Store weak reference to self for the callback
        // We need to use Unmanaged because CGEventTap callback is a C function pointer
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Create the event tap at session level (captures events for current login session)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // We only observe, don't modify events
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            print("⚠️ Failed to create CGEventTap for key-up monitoring (check Accessibility permissions)")
            return
        }

        // Add the event tap to the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("✅ Registered CGEventTap for key-up monitoring")
    }

    /// Unregister the key-up monitor (CGEventTap and legacy NSEvent monitor)
    private func unregisterKeyUpMonitor() {
        // Clean up CGEventTap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }

        // Clean up legacy NSEvent monitor if present
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }

    /// Handle global key events for hold-mode detection
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        // Only process if we have an active key-down time (meaning recording might be in progress)
        guard let keyDownTime = recordingKeyDownTime,
              let shortcut = currentRecordingShortcut else {
            // Don't log every event - only when we have partial state
            if recordingKeyDownTime != nil || currentRecordingShortcut != nil {
                print("🔑 Global key event ignored: keyDownTime=\(recordingKeyDownTime?.description ?? "nil"), shortcut=\(currentRecordingShortcut?.displayString ?? "nil")")
            }
            return
        }

        print("🔑 Global key event: type=\(event.type == .keyUp ? "keyUp" : "flagsChanged"), keyCode=\(event.keyCode)")

        // Determine if this event represents a release of our shortcut keys
        let isMatchingRelease: Bool

        switch event.type {
        case .keyUp:
            // Check if the released key matches our shortcut's main key code
            isMatchingRelease = event.keyCode == UInt16(shortcut.keyCode)

        case .flagsChanged:
            // Check if any of our required modifiers were released
            isMatchingRelease = checkModifierReleased(event: event, shortcut: shortcut)

        default:
            return
        }

        guard isMatchingRelease else { return }

        // Calculate how long the key was held
        let duration = Date().timeIntervalSince(keyDownTime)

        if duration >= holdThresholdSeconds {
            // Hold mode: key was held long enough, release should stop recording
            print("🎹 Hold mode release detected (duration: \(String(format: "%.2f", duration))s)")
            isHoldMode = true
            recordingKeyUpHandler?()
        } else {
            // Quick press mode: this was a toggle-style press, ignore the release
            print("🎹 Quick press detected (duration: \(String(format: "%.2f", duration))s), toggle mode active")
            isHoldMode = false
        }

        // Clear the key-down time to prevent double-handling
        recordingKeyDownTime = nil
    }

    /// Check if a required modifier key was released (for NSEvent - legacy)
    private func checkModifierReleased(event: NSEvent, shortcut: KeyboardShortcut) -> Bool {
        let currentFlags = event.modifierFlags
        let requiredModifiers = shortcut.modifiers

        // Check each required modifier - if any is no longer pressed, it was released
        if requiredModifiers.contains(.command) && !currentFlags.contains(.command) {
            return true
        }
        if requiredModifiers.contains(.shift) && !currentFlags.contains(.shift) {
            return true
        }
        if requiredModifiers.contains(.option) && !currentFlags.contains(.option) {
            return true
        }
        if requiredModifiers.contains(.control) && !currentFlags.contains(.control) {
            return true
        }

        return false
    }

    // MARK: - CGEventTap Handling

    /// Handle CGEvent for hold-mode detection (called from CGEventTap callback)
    /// This is the primary method for detecting key releases since CGEventTap
    /// operates at a lower level than NSEvent monitors and sees all events.
    /// Note: This is called from a CGEventTap callback on a different thread,
    /// so we need nonisolated and dispatch to main actor for state access.
    nonisolated private func handleCGEvent(type: CGEventType, event: CGEvent) {
        // Extract data from CGEvent before crossing actor boundary (CGEvent isn't Sendable)
        let keyCode: Int64? = type == .keyUp ? event.getIntegerValueField(.keyboardEventKeycode) : nil
        let flags: CGEventFlags? = type == .flagsChanged ? event.flags : nil

        // Dispatch to main actor to safely access state
        Task { @MainActor in
            self.processCGEvent(type: type, keyCode: keyCode, flags: flags)
        }
    }

    /// Process CGEvent data on the main actor (called from handleCGEvent)
    /// - Parameters:
    ///   - type: The event type (keyUp or flagsChanged)
    ///   - keyCode: The key code if this was a keyUp event
    ///   - flags: The modifier flags if this was a flagsChanged event
    private func processCGEvent(type: CGEventType, keyCode: Int64?, flags: CGEventFlags?) {
        // Only process if we have an active key-down time (meaning recording might be in progress)
        guard let keyDownTime = recordingKeyDownTime,
              let shortcut = currentRecordingShortcut else {
            return
        }

        // Determine if this event represents a release of our shortcut keys
        let isMatchingRelease: Bool

        switch type {
        case .keyUp:
            // Check if the released key matches our shortcut's main key code
            guard let keyCode = keyCode else { return }
            isMatchingRelease = keyCode == Int64(shortcut.keyCode)
            if isMatchingRelease {
                print("🔑 CGEventTap keyUp: keyCode=\(keyCode) matches shortcut")
            }

        case .flagsChanged:
            // Check if any of our required modifiers were released
            guard let flags = flags else { return }
            isMatchingRelease = checkModifierReleasedCG(flags: flags, shortcut: shortcut)
            if isMatchingRelease {
                print("🔑 CGEventTap flagsChanged: modifier released")
            }

        default:
            return
        }

        guard isMatchingRelease else { return }

        // Calculate how long the key was held
        let duration = Date().timeIntervalSince(keyDownTime)

        // Clear the key-down time first to prevent double-handling
        recordingKeyDownTime = nil

        if duration >= holdThresholdSeconds {
            // Hold mode: key was held long enough, release should stop recording
            print("🎹 Hold mode release detected via CGEventTap (duration: \(String(format: "%.2f", duration))s)")
            isHoldMode = true
            // Already on main actor via processCGEvent
            recordingKeyUpHandler?()
        } else {
            // Quick press mode: this was a toggle-style press, ignore the release
            print("🎹 Quick press detected via CGEventTap (duration: \(String(format: "%.2f", duration))s), toggle mode active")
            isHoldMode = false
        }
    }

    /// Check if a required modifier key was released (for CGEventFlags)
    private func checkModifierReleasedCG(flags: CGEventFlags, shortcut: KeyboardShortcut) -> Bool {
        let requiredModifiers = shortcut.modifiers

        // Check each required modifier - if any is no longer pressed, it was released
        if requiredModifiers.contains(.command) && !flags.contains(.maskCommand) {
            return true
        }
        if requiredModifiers.contains(.shift) && !flags.contains(.maskShift) {
            return true
        }
        if requiredModifiers.contains(.option) && !flags.contains(.maskAlternate) {
            return true
        }
        if requiredModifiers.contains(.control) && !flags.contains(.maskControl) {
            return true
        }

        return false
    }

    /// Reset hold mode state (call when recording stops for any reason)
    func resetHoldState() {
        print("🔄 resetHoldState called (was: keyDownTime=\(recordingKeyDownTime?.description ?? "nil"), isHoldMode=\(isHoldMode))")
        recordingKeyDownTime = nil
        isHoldMode = false
    }

    // MARK: - Language Toggle Hotkey

    /// Register a simple hotkey for language toggle (key-down only, no hold logic)
    func registerLanguageToggleHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void) {
        languageToggleHandler = handler
        languageToggleHotkey = nil

        guard let key = shortcut.hotKeyKey else {
            print("⚠️ Could not create hotkey for language toggle shortcut")
            return
        }

        languageToggleHotkey = HotKey(
            key: key,
            modifiers: shortcut.modifiers.hotKeyModifiers,
            keyDownHandler: handler
        )

        print("✅ Registered language toggle hotkey: \(shortcut.displayString)")
    }

    /// Unregister the language toggle hotkey
    func unregisterLanguageToggleHotkey() {
        languageToggleHotkey = nil
    }

    // MARK: - Auto-Type Toggle Hotkey

    /// Register a simple hotkey for auto-type toggle (key-down only, no hold logic)
    func registerAutoTypeToggleHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void) {
        autoTypeToggleHandler = handler
        autoTypeToggleHotkey = nil

        guard let key = shortcut.hotKeyKey else {
            print("⚠️ Could not create hotkey for auto-type toggle shortcut")
            return
        }

        autoTypeToggleHotkey = HotKey(
            key: key,
            modifiers: shortcut.modifiers.hotKeyModifiers,
            keyDownHandler: handler
        )

        print("✅ Registered auto-type toggle hotkey: \(shortcut.displayString)")
    }

    /// Unregister the auto-type toggle hotkey
    func unregisterAutoTypeToggleHotkey() {
        autoTypeToggleHotkey = nil
    }

    // MARK: - Shortcut Updates

    /// Re-register all hotkeys with new shortcuts
    func updateShortcuts(recordingShortcut: KeyboardShortcut, cancelShortcut: KeyboardShortcut, languageToggleShortcut: KeyboardShortcut? = nil, autoTypeToggleShortcut: KeyboardShortcut? = nil) {
        if let keyDownHandler = recordingHandler,
           let keyUpHandler = recordingKeyUpHandler {
            registerRecordingHotkey(
                shortcut: recordingShortcut,
                keyDownHandler: keyDownHandler,
                keyUpHandler: keyUpHandler
            )
        }
        if let handler = cancelHandler {
            registerCancelHotkey(shortcut: cancelShortcut, handler: handler)
        }
        // Re-register language toggle if a handler was previously set
        if let shortcut = languageToggleShortcut, let handler = languageToggleHandler {
            registerLanguageToggleHotkey(shortcut: shortcut, handler: handler)
        }
        // Re-register auto-type toggle if a handler was previously set
        if let shortcut = autoTypeToggleShortcut, let handler = autoTypeToggleHandler {
            registerAutoTypeToggleHotkey(shortcut: shortcut, handler: handler)
        }
    }

    /// Unregister all hotkeys (call on app termination)
    func unregisterAll() {
        // Setting to nil automatically unregisters the hotkey
        recordingHotkey = nil
        cancelHotkey = nil
        languageToggleHotkey = nil
        autoTypeToggleHotkey = nil

        // Remove the cancel local event monitor
        if let monitor = cancelMonitor {
            NSEvent.removeMonitor(monitor)
            cancelMonitor = nil
        }

        // Remove the key-up global monitor
        unregisterKeyUpMonitor()

        // Clear all handlers and state
        recordingHandler = nil
        recordingKeyUpHandler = nil
        cancelHandler = nil
        languageToggleHandler = nil
        autoTypeToggleHandler = nil
        currentCancelShortcut = nil
        currentRecordingShortcut = nil
        recordingKeyDownTime = nil
        isHoldMode = false

        print("✅ Unregistered all hotkeys")
    }

    // MARK: - Legacy Methods (for backward compatibility)

    /// Register the recording toggle hotkey with default shortcut (Option+Space)
    /// Note: This legacy method uses toggle-only mode (no hold-to-record)
    func registerRecordingHotkey(handler: @escaping () -> Void) {
        registerRecordingHotkey(
            shortcut: .defaultRecordingToggle,
            keyDownHandler: handler,
            keyUpHandler: { } // No-op for legacy toggle-only mode
        )
    }

    /// Register the cancel hotkey with default shortcut (Esc)
    func registerCancelHotkey(handler: @escaping () -> Void) {
        registerCancelHotkey(shortcut: .defaultCancelRecording, handler: handler)
    }
}

// MARK: - Key Codes Reference

/*
 MACOS KEY CODES (for reference):

 These come from Carbon's HIToolbox/Events.h
 You can use them with NSEvent.keyCode

 kVK_Return       = 0x24  (36)
 kVK_Tab          = 0x30  (48)
 kVK_Space        = 0x31  (49)
 kVK_Delete       = 0x33  (51)
 kVK_Escape       = 0x35  (53)
 kVK_Command      = 0x37  (55)
 kVK_Shift        = 0x38  (56)
 kVK_CapsLock     = 0x39  (57)
 kVK_Option       = 0x3A  (58)
 kVK_Control      = 0x3B  (59)

 The HotKey library uses the Key enum which maps these for you.
 */
