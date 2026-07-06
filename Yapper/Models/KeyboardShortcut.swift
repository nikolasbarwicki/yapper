import AppKit
import Foundation
import HotKey
import Carbon.HIToolbox

// MARK: - Keyboard Shortcut Model

/// Represents a configurable keyboard shortcut with a key and modifiers.
/// This model can be persisted to UserDefaults and converted to HotKey format.
struct KeyboardShortcut: Codable, Equatable {

    /// The key code (using Carbon key codes for compatibility with HotKey library)
    let keyCode: UInt32

    /// The modifier flags (command, shift, option, control)
    let modifiers: ShortcutModifiers

    // MARK: - Key Code Display Names

    /// Mapping of Carbon key codes to human-readable display names
    private static let keyCodeDisplayNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Delete: "Delete",
        kVK_Escape: "ESC",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12"
    ]

    // MARK: - Modifier Flags

    struct ShortcutModifiers: OptionSet, Codable, Equatable {
        let rawValue: UInt

        static let command = ShortcutModifiers(rawValue: 1 << 0)
        static let shift = ShortcutModifiers(rawValue: 1 << 1)
        static let option = ShortcutModifiers(rawValue: 1 << 2)
        static let control = ShortcutModifiers(rawValue: 1 << 3)

        /// Convert to HotKey's NSEvent.ModifierFlags format
        var hotKeyModifiers: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.command) { flags.insert(.command) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.option) { flags.insert(.option) }
            if contains(.control) { flags.insert(.control) }
            return flags
        }

        /// Create from NSEvent.ModifierFlags
        init(modifierFlags flags: NSEvent.ModifierFlags) {
            var result: ShortcutModifiers = []
            if flags.contains(.command) { result.insert(.command) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.control) { result.insert(.control) }
            self = result
        }

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }
    }

    // MARK: - Initialization

    init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Create from an NSEvent (used when recording shortcuts)
    init?(from event: NSEvent) {
        guard event.type == .keyDown else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.modifiers = ShortcutModifiers(modifierFlags: event.modifierFlags)
    }

    // MARK: - Default Shortcuts

    /// Default shortcut for recording toggle: Option+Space
    static let defaultRecordingToggle = KeyboardShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.option]
    )

    /// Default shortcut for cancel recording: Escape (no modifiers)
    static let defaultCancelRecording = KeyboardShortcut(
        keyCode: UInt32(kVK_Escape),
        modifiers: []
    )

    /// Default shortcut for language toggle: Shift+Option+L
    static let defaultLanguageToggle = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: [.shift, .option]
    )

    /// Default shortcut for auto-type toggle: Shift+Option+T
    static let defaultAutoTypeToggle = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.shift, .option]
    )

    // MARK: - Display

    /// Human-readable display of the key
    var keyDisplayName: String {
        if let name = Self.keyCodeDisplayNames[Int(keyCode)] {
            return name
        }
        return characterForKeyCode(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Array of display strings for the shortcut (e.g., ["⌘", "⇧", "Space"])
    var displayKeys: [String] {
        var keys: [String] = []

        // Add modifiers in standard macOS order
        if modifiers.contains(.control) { keys.append("⌃") }
        if modifiers.contains(.option) { keys.append("⌥") }
        if modifiers.contains(.shift) { keys.append("⇧") }
        if modifiers.contains(.command) { keys.append("⌘") }

        // Add the key
        keys.append(keyDisplayName)

        return keys
    }

    /// Single string representation (e.g., "⌥Space")
    var displayString: String {
        displayKeys.joined()
    }

    // MARK: - HotKey Conversion

    /// Convert keyCode to HotKey's Key enum
    var hotKeyKey: Key? {
        Key(carbonKeyCode: keyCode)
    }

    // MARK: - Validation

    /// Check if the shortcut is valid (has at least one modifier for non-special keys)
    var isValid: Bool {
        // Special keys like Escape can work without modifiers
        let specialKeys: Set<Int> = [kVK_Escape, kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
                                      kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

        if specialKeys.contains(Int(keyCode)) {
            return true
        }

        // Regular keys need at least one modifier
        return !modifiers.isEmpty
    }
}

// MARK: - Helper Functions

/// Get the character for a key code (for display purposes)
/// This is internal so it can be used by AppDelegate for menu item key equivalents
func characterForKeyCode(_ keyCode: UInt32) -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }

    let dataRef = unsafeBitCast(layoutData, to: CFData.self)
    let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0

    let status = UCKeyTranslate(
        keyboardLayout,
        UInt16(keyCode),
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &length,
        &chars
    )

    guard status == noErr, length > 0 else { return nil }

    return String(utf16CodeUnits: chars, count: length)
}

// MARK: - Shortcut Type

/// Identifies the type of shortcut for storage and UI purposes
enum ShortcutType: String, CaseIterable, Identifiable {
    case recordingToggle = "recordingToggle"
    case cancelRecording = "cancelRecording"
    case languageToggle = "languageToggle"
    case autoTypeToggle = "autoTypeToggle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recordingToggle: return "Start/Stop Recording"
        case .cancelRecording: return "Cancel Recording"
        case .languageToggle: return "Toggle Language"
        case .autoTypeToggle: return "Toggle Auto-type"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .recordingToggle: return .defaultRecordingToggle
        case .cancelRecording: return .defaultCancelRecording
        case .languageToggle: return .defaultLanguageToggle
        case .autoTypeToggle: return .defaultAutoTypeToggle
        }
    }

    /// UserDefaults key for storing this shortcut
    var storageKey: String {
        "shortcut_\(rawValue)"
    }
}
