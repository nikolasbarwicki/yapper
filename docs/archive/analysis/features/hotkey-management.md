# Hotkey Management - Deep Dive

## Purpose

The Hotkey Management feature provides global keyboard shortcuts that work across all applications, enabling users to start/stop/cancel voice recording without switching focus to Yapper. It implements a "smart detection" system that automatically distinguishes between quick toggle presses and hold-to-record gestures.

---

## User-Facing Behavior

- **Quick Press (< 0.3s)**: Toggle mode - press once to start, press again to stop
- **Hold (>= 0.3s)**: Hold-to-record mode - hold keys to record, release to stop
- **Cancel Recording**: Cancel shortcut (default: Escape) cancels without transcribing
- **Toggle Language**: Language toggle shortcut (default: Shift+Option+L) switches between primary and secondary language
- **Toggle Auto-Type**: Auto-type toggle shortcut (default: Shift+Option+T) enables/disables automatic text injection, shows toast pill confirmation
- **Shortcut Recording**: Click shortcut in Settings, press desired key combination
- **Escape Cancellation**: Bare Escape while recording cancels
- **Reset to Defaults**: Restore Option+Space, Escape, Shift+Option+L, and Shift+Option+T
- **Validation**: Regular keys require modifier; F1-F12/Escape work without

---

## Public Interface

### HotkeyManager

**Location**: `Yapper/Services/HotkeyManager.swift`

```swift
/// Register recording shortcut with smart toggle/hold detection
func registerRecordingHotkey(
    shortcut: KeyboardShortcut,
    keyDownHandler: @escaping () -> Void,
    keyUpHandler: @escaping () -> Void
)

/// Register cancel hotkey
func registerCancelHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void)

/// Register language toggle hotkey (simple key-down, no hold detection)
func registerLanguageToggleHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void)

/// Register auto-type toggle hotkey (simple key-down, no hold detection)
func registerAutoTypeToggleHotkey(shortcut: KeyboardShortcut, handler: @escaping () -> Void)

/// Re-register all hotkeys with new shortcuts
func updateShortcuts(
    recordingShortcut: KeyboardShortcut,
    cancelShortcut: KeyboardShortcut,
    languageToggleShortcut: KeyboardShortcut?,
    autoTypeToggleShortcut: KeyboardShortcut?
)

/// Reset hold mode state
func resetHoldState()

/// Unregister all hotkeys
func unregisterAll()
```

### KeyboardShortcut

**Location**: `Yapper/Models/KeyboardShortcut.swift`

```swift
struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32        // Carbon key code
    let modifiers: ShortcutModifiers

    var displayString: String  // e.g., "⌥Space"
    var displayKeys: [String]  // e.g., ["⌥", "Space"]
    var hotKeyKey: Key?        // HotKey library Key enum
    var isValid: Bool          // Validation

    static let defaultRecordingToggle: KeyboardShortcut  // Option+Space
    static let defaultCancelRecording: KeyboardShortcut  // Escape
    static let defaultLanguageToggle: KeyboardShortcut   // Shift+Option+L
    static let defaultAutoTypeToggle: KeyboardShortcut   // Shift+Option+T
}

enum ShortcutType: String, CaseIterable {
    case recordingToggle
    case cancelRecording
    case languageToggle
    case autoTypeToggle

    var storageKey: String     // "shortcut_languageToggle" for .languageToggle
    var defaultShortcut: KeyboardShortcut
    var displayName: String    // "Toggle Auto-Type" for .autoTypeToggle
}
```

### ShortcutModifiers

```swift
struct ShortcutModifiers: OptionSet, Codable {
    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)

    var hotKeyModifiers: NSEvent.ModifierFlags
}
```

---

## Dependencies

- **External**: `HotKey` library - wraps Carbon Event API
- **System**: `Carbon.HIToolbox` for key codes
- **System**: `NSEvent` for event monitoring
- **Internal**: `AppState` for shortcut persistence
- **Internal**: `NotificationCenter.shortcutsChanged` for updates

---

## Implementation Notes

### Global Shortcut Registration (Carbon API via HotKey)

```swift
var hotKeyKey: Key? {
    Key(carbonKeyCode: keyCode)
}

recordingHotkey = HotKey(
    key: key,
    modifiers: shortcut.modifiers.hotKeyModifiers,
    keyDownHandler: { [weak self] in
        self?.handleRecordingKeyDown()
    }
)
```

### Toggle vs Hold-to-Record Detection

Threshold: 0.3 seconds

```swift
private let holdThresholdSeconds: TimeInterval = 0.3
```

Flow:
1. Key-down: Record timestamp, call `keyDownHandler` (starts recording)
2. Key-up: Calculate duration
3. If >= 0.3s: Hold mode - call `keyUpHandler` (stops)
4. If < 0.3s: Toggle mode - ignore (user presses again)

```swift
let duration = Date().timeIntervalSince(keyDownTime)

if duration >= holdThresholdSeconds {
    isHoldMode = true
    recordingKeyUpHandler?()
} else {
    isHoldMode = false
}
recordingKeyDownTime = nil
```

### Key-Up Monitoring

HotKey only provides key-down. Two mechanisms detect key-up:

1. **CGEventTap** (primary): Low-level event tap that intercepts key releases even when HotKey's Carbon handler consumes them. Monitors for both regular key-up events and modifier flag changes.

```swift
let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: eventTapCallback,
    userInfo: pointer
)
```

2. **NSEvent global monitor** (fallback): Standard AppKit event monitoring.

```swift
keyUpMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.keyUp, .flagsChanged]
) { [weak self] event in
    self?.handleGlobalKeyEvent(event)
}
```

Both `.keyUp` (main key) and `.flagsChanged` (modifiers) monitored.

### Cancel Hotkey Dual Registration

Local and global monitors for reliability:

```swift
// Local (when app has focus)
cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ... }

// Global (when app lacks focus)
cancelHotkey = HotKey(key: key, modifiers: ..., keyDownHandler: { ... })
```

### Carbon Key Code Mapping

```swift
private static let keyCodeDisplayNames: [Int: String] = [
    kVK_Space: "Space",
    kVK_Return: "Return",
    kVK_Escape: "ESC",
    kVK_UpArrow: "↑",
    kVK_F1: "F1",
    // ...
]
```

For regular characters, `UCKeyTranslate` queries current keyboard layout.

### Modifier Display Order

macOS convention (Control-Option-Shift-Command):

```swift
if modifiers.contains(.control) { keys.append("⌃") }
if modifiers.contains(.option) { keys.append("⌥") }
if modifiers.contains(.shift) { keys.append("⇧") }
if modifiers.contains(.command) { keys.append("⌘") }
```

---

## State & Data

### Persisted (UserDefaults)

- `shortcut_recordingToggle` - JSON-encoded KeyboardShortcut
- `shortcut_cancelRecording` - JSON-encoded KeyboardShortcut
- `shortcut_languageToggle` - JSON-encoded KeyboardShortcut
- `shortcut_autoTypeToggle` - JSON-encoded KeyboardShortcut

### Runtime (HotkeyManager)

- `recordingKeyDownTime: Date?` - For hold detection
- `isHoldMode: Bool` - Current session type
- `currentRecordingShortcut` / `currentCancelShortcut` - Active shortcuts
- `languageToggleHotkey: HotKey?` - Registered language toggle hotkey
- `languageToggleHandler: (() -> Void)?` - Language toggle callback
- `autoTypeToggleHotkey: HotKey?` - Registered auto-type toggle hotkey
- `autoTypeToggleHandler: (() -> Void)?` - Auto-type toggle callback

### State Flow

1. App launch: `AppState.init()` loads from UserDefaults
2. `AppDelegate.setupHotkeys()` registers with HotkeyManager
3. Settings change: Posts `.shortcutsChanged` notification
4. AppDelegate calls `hotkeyManager?.updateShortcuts()`

---

## Edge Cases & Gotchas

1. **Modifier-only not supported**: HotKey requires base key

2. **Key-up detection failure**: App switch during hold may miss key-up; `resetHoldState()` handles this

3. **Local vs Global race**: Both handlers fire for cancel; handler is idempotent

4. **Function keys without modifiers**: F1-F12 and Escape special-cased in `isValid`

5. **Non-US keyboards**: `characterForKeyCode()` adapts to layout; key codes are hardware-based

6. **Escape double-duty**: Cancels shortcut recording AND can be cancel shortcut

7. **No conflict handling**: No detection of conflicts between shortcuts

8. **First responder**: ShortcutRecorderView uses `DispatchQueue.main.async` for SwiftUI cycle

---

## Technical Debt

1. **No shortcut conflict validation**: Same shortcut for both actions allowed

2. **Carbon API dependency**: Deprecated but still supported

3. **Debug logging**: Heavy print statements should use proper logging

4. **Legacy method**: `registerRecordingHotkey(handler:)` without key-up exists for "backward compatibility"

5. **No global monitor when app focused**: Key-up only globally monitored

6. **Hardcoded threshold**: 0.3s not customizable

7. **Memory management**: Monitors must be explicitly removed

---

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `Yapper/Services/HotkeyManager.swift` | ~570 | Global shortcut registration (recording, cancel, language toggle, auto-type toggle) |
| `Yapper/Models/KeyboardShortcut.swift` | ~250 | Shortcut model with 4 shortcut types |
| `Yapper/Views/ShortcutRecorderView.swift` | 201 | Recording UI |
