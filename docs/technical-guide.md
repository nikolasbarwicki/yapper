# Yapper Technical Guide

Yapper is a native macOS menu bar app built with Swift, SwiftUI, and AppKit. Current builds are open source and start without activation, trials, or license checks.

## Architecture

```text
Yapper/
├── App/          App lifecycle, menu bar, notifications, bundle helpers
├── Models/       Observable app state and value models
├── Services/     Audio, transcription, LLM, hotkeys, text injection, storage
├── Views/        SwiftUI views and AppKit window controllers
├── Utilities/    Formatting, logging, model storage helpers
└── Resources/    Assets
```

`AppDelegate` owns startup and long-lived service coordination. `AppState` is the central observable model shared with SwiftUI settings, overlays, file transcription, and history windows.

## Runtime Flow

1. `YapperApp` installs `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching` marks the app as open source and continues setup.
3. `setupMenuBar` creates the menu bar item and menu commands.
4. `setupServices` creates the recorder, transcription service, text injector, LLM service, audio device manager, accessibility reader, and sound feedback service.
5. Global shortcuts toggle recording, language switching, auto-type, and cancellation.
6. Finished recordings are transcribed locally, optionally transformed with the selected LLM provider, saved to history, and typed into the focused app when auto-type is enabled.

## Core Components

| Component | File | Responsibility |
| --- | --- | --- |
| App coordinator | `Yapper/App/AppDelegate.swift` | Menu bar lifecycle, service setup, keyboard actions, recording pipeline |
| Shared state | `Yapper/Models/AppState.swift` | Preferences, model selection, recording state, permissions, open-source availability state |
| Audio capture | `Yapper/Services/AudioRecorder.swift` | Microphone recording and level updates |
| Transcription | `Yapper/Services/TranscriptionService.swift` | Backend selection and speech-to-text orchestration |
| WhisperKit backend | `Yapper/Services/WhisperKitBackend.swift` | WhisperKit model loading and transcription |
| FluidAudio backend | `Yapper/Services/FluidAudioBackend.swift` | Parakeet/FluidAudio model loading and transcription |
| Hotkeys | `Yapper/Services/HotkeyManager.swift` | Global shortcut registration and hold/toggle detection |
| Text injection | `Yapper/Services/TextInjector.swift` | Types output into the focused app |
| AI providers | `Yapper/Services/LLMService.swift` | Gemini, OpenAI, Anthropic, and xAI requests |
| API keys | `Yapper/Services/APIKeyStorage.swift` | Keychain storage for user-supplied provider keys |
| History | `Yapper/Services/TranscriptHistoryManager.swift` | Local transcript persistence and retention cleanup |
| Audio devices | `Yapper/Services/AudioDeviceManager.swift` | Input device enumeration and change monitoring |
| Accessibility | `Yapper/Services/AccessibilityReader.swift` | Selected-text reading for AI Transform |

## Dependencies

| Package | Purpose |
| --- | --- |
| WhisperKit | Local Whisper transcription |
| FluidAudio | Local Parakeet transcription |
| HotKey | Global keyboard shortcut integration |
| MarkdownUI | Markdown rendering for AI responses |

Sparkle is not wired into current open-source builds. Maintainers who want automatic updates should add their own update feed, signing key, and release workflow.

## State And Persistence

`AppState` stores user preferences through `UserDefaults`, including:

- Keyboard shortcuts
- Recording behavior
- Selected transcription backend and model
- Primary and secondary language settings
- Auto-type and sound preferences
- Overlay position
- Transcript history retention

Secrets such as LLM API keys are stored in Keychain through `APIKeyStorage`.

Transcript history is stored locally by `TranscriptHistoryManager`. Downloaded speech models remain on the user's Mac and can be inspected or cleared through settings.

## Permissions

Yapper needs microphone permission to record audio. Accessibility permission is needed when the user wants Yapper to type into other apps or read selected text for AI Transform.

Permission state is checked at startup and refreshed from settings through app notifications.

## Build Notes

Open `Yapper.xcodeproj` in Xcode, select the `Yapper` scheme, and run on a Mac destination. The checked-in `Package.resolved` pins Swift package dependencies for reproducible builds.

For local development, contributors should set their own signing team in Xcode if automatic signing requires it. The repository does not include a personal release team identifier.

## Archived Documentation

Older scans and release notes that mention the former paid licensing/trial system live under `docs/archive/`. They are historical only and do not describe current runtime behavior.
