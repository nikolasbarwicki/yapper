# Architecture

## Overview

Yapper is a SwiftUI + AppKit hybrid menu bar application with a centralized observable state pattern.

```
┌─────────────────────────────────────────────────────────────┐
│                        AppDelegate                           │
│                    (Orchestration Hub)                       │
├─────────────────────────────────────────────────────────────┤
│  AppState          Services              Views               │
│  (@Observable)     - AudioRecorder       - OverlayWindow     │
│                    - Transcription       - SettingsView      │
│                    - TextInjector        - HistoryView       │
│                    - LLMService          - AIEnhancement     │
│                    - HotkeyManager       - FileTranscription │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Architectural Decisions

### 1. Menu Bar App (LSUIElement)

**Decision**: Run as agent app without dock icon.

**Why**:
- Always accessible from menu bar
- Doesn't clutter dock
- Background operation is expected behavior
- Minimal visual footprint

**Trade-off**: No Cmd+Tab switching - must use menu bar or hotkeys.

### 2. Single Observable State

**Decision**: One `AppState` class with `@Observable` macro.

**Why**:
- Simplest state management for app size
- Automatic SwiftUI binding
- No external dependencies (Redux-like libraries)
- Modern Swift Observation framework (macOS 14+)

### 3. AppDelegate as Orchestrator

**Decision**: Services instantiated in AppDelegate, coordinates all flows.

**Why**:
- Natural lifecycle owner
- Services have app-scope lifetime
- Clear ownership hierarchy
- Avoids singletons (mostly)

**Exception**: `TranscriptHistoryManager` is a singleton for shared access.

### 4. CGEvent Text Injection (not Clipboard)

**Decision**: Type text via Accessibility API keyboard simulation.

**Why**:
- Native typing experience
- Undo works naturally
- Doesn't modify user's clipboard
- Works in password fields

**Trade-off**: Requires manual Accessibility permission grant.

### 5. Offline-First Transcription

**Decision**: WhisperKit for 100% local transcription.

**Why**:
- Privacy by default
- No API costs for core feature
- Works without internet
- Apple Silicon Neural Engine optimization

**Trade-off**: ~1.5GB model download, memory usage while loaded.

### 6. Dual Hotkey System

**Decision**: Use both HotKey library AND NSEvent local monitor.

**Why**:
- HotKey works when app not focused (essential for menu bar app)
- NSEvent monitor provides backup for some keyboard layouts
- Redundancy improves reliability

---

## Data Flow

### Recording Flow

```
User presses hotkey
       ↓
HotkeyManager → AppDelegate.handleRecordingToggle()
       ↓
AppDelegate → AppState.startRecording()
       ↓
AppDelegate → AudioRecorder.startRecording()
       ↓
[User speaks, audio captured at 16kHz]
       ↓
User presses hotkey again
       ↓
AudioRecorder.stopRecording() → audio samples
       ↓
TranscriptionService.transcribe(samples) → text
       ↓
[If AI enabled] LLMService.enhance(text) → enhanced text (via selected provider)
       ↓
TranscriptHistoryManager.addRecord()
       ↓
TextInjector.typeText(finalText) → text injected into app
       ↓
AppState.completeTranscription() → shows "Success" overlay for 1 second
```

### State Updates

All services update `AppState`, which automatically notifies SwiftUI views via `@Observable`.

```
Service → AppState property change → SwiftUI view re-render
```

---

## Threading Model

| Component | Thread |
|-----------|--------|
| AppState, AppDelegate, all Views | Main (`@MainActor`) |
| Audio capture callback | AVAudioEngine queue → dispatched to main |
| WhisperKit transcription | Background → results on main |
| Network calls (LLM APIs) | URLSession → results on main |
| Hotkey events | Carbon background → dispatched to main |

**Rule**: All UI updates happen on `@MainActor`.

---

## Extension Points

### Adding a New AI Provider

Currently supported: Gemini, OpenAI, Anthropic, xAI (Grok)

1. Implement `LLMProvider` protocol in `LLMService.swift`
2. Add case to `LLMService.Provider` enum with `displayName` and `apiKeyURL`
3. Add models to `LLMModel` enum with `provider` mapping
4. Add provider instance variable and configure in `LLMService.configure()`
5. Add storage account constant in `APIKeyStorage`
6. Add UI for API key in `AIEnhancementSettingsView`

### Adding a New Audio Source

1. Match AudioRecorder's output format (16kHz mono Float32)
2. Integrate with AppDelegate orchestration

### Adding a New Shortcut Action

1. Add property to `AppState`
2. Add case to `ShortcutType` enum
3. Register in `HotkeyManager`
4. Add UI in shortcuts settings
