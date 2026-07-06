# Yapper Feature Map

**Last Updated**: 2026-03-28

## Overview

This document identifies 22 distinct features and their bounded contexts in the Yapper codebase - a macOS menu bar voice-to-text dictation application.

---

## Feature 1: Voice Recording & Capture

**Purpose**: Captures live audio from a selectable microphone, converts to 16kHz mono PCM for transcription engines

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/AudioRecorder.swift` | Core AVAudioEngine service, device selection via CoreAudio HAL |
| `Yapper/Services/AudioDeviceManager.swift` | CoreAudio HAL enumeration, property listeners for hot-plug, level metering |
| `Yapper/Services/AudioInputDevice.swift` | Audio device model (volatile audioDeviceID + stable UID) |
| `Yapper/Views/MicrophoneLevelView.swift` | Real-time level meter (green/yellow/red, 80ms easeOut) |
| `Yapper/Models/AppState.swift` | audioLevel, hasMicrophonePermission, selectedMicrophoneUID, availableInputDevices state |
| `Yapper/App/AppDelegate.swift` | Orchestration (startRecording/stopRecording) |

**Entry Points**:
- `AppDelegate.startRecording()`
- `AppDelegate.stopRecording()`
- Settings > Transcription > Input Device picker

**Dependencies**:
- → Transcription (outputs audio data)

**Complexity**: Medium

---

## Feature 2: Speech Transcription (Multi-Engine)

**Purpose**: Converts audio to text using on-device models via pluggable backend architecture

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/TranscriptionService.swift` | Thin coordinator actor (delegates to backends) |
| `Yapper/Services/TranscriptionBackend.swift` | Backend protocol definition |
| `Yapper/Services/WhisperKitBackend.swift` | OpenAI Whisper via WhisperKit |
| `Yapper/Services/FluidAudioBackend.swift` | NVIDIA Parakeet via FluidAudio |
| `Yapper/Models/TranscriptionEngine.swift` | Engine enum, ModelIdentifier, AvailableModels, SupportedLanguages |
| `Yapper/Models/AppState.swift` | selectedModel, selectedLanguage, customVocabulary, isLoadingModel |
| `Yapper/Utilities/ModelStorageManager.swift` | Disk usage tracking, download cleanup |
| `Yapper/Views/SettingsView.swift` | Model/language selection UI, download progress, cancel, storage |

**Entry Points**:
- `TranscriptionService.transcribe(audioData:language:customVocabulary:)`
- `TranscriptionService.transcribeStreaming(audioData:language:customVocabulary:onToken:)`
- `TranscriptionService.loadModel(modelName:progressHandler:phaseHandler:)`

**Dependencies**:
- ← Voice Recording
- → LLM AI Services (AI Transform, AI Q&A routing)
- → Text Injection (batch or streaming)
- → History

**Complexity**: High

---

## Feature 3: LLM AI Services (Transform + Q&A)

**Purpose**: Provides user-initiated AI capabilities via external LLM APIs (Gemini, OpenAI, Anthropic, xAI). Two modes: Transform (voice-driven text rewriting) and Q&A ("Hey Yapper" voice assistant). No auto-enhancement -- AI is strictly user-initiated.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/LLMService.swift` | Multi-provider abstraction: transform(), transformStream(), qaStream() |
| `Yapper/Services/APIKeyStorage.swift` | UserDefaults-based key storage |
| `Yapper/Views/AIEnhancementSettingsView.swift` | Provider/model/key configuration, mode descriptions |

**Entry Points**:
- `LLMService.transformStream(text:instruction:)` - AI Transform
- `LLMService.qaStream(question:)` - AI Q&A
- `LLMProvider.enhanceStream(text:prompt:)` - SSE streaming (all 4 providers)

**Dependencies**:
- ← Transcription (receives text/instruction)
- ← API Key Storage
- ← AccessibilityReader (Transform mode: reads selected text)

**Complexity**: High

**Note**: The v1.x auto-enhancement feature (`enhance(text:)`, `setPrompt()`, `getPrompt()`, `defaultPrompt`, `RecordingState.enhancing`, `Notifications.aiPromptChanged`) has been removed. See `docs/analysis/features/llm-enhancement.md` for details.

---

## Feature 4: Text Injection

**Purpose**: Types transcribed text into focused app via macOS Accessibility APIs. Supports both batch and streaming modes. Gated behind `appState.autoTypeEnabled` — when disabled, text is not injected but still saved to history.

**User-Facing**: No (transparent operation)

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/TextInjector.swift` | CGEvent keyboard simulation + atomic streaming |

**Entry Points**:
- `TextInjector.typeText(_:)` - Batch: 100ms initial delay, 10ms/char
- `TextInjector.typeStringAtomically(_:)` - Streaming: atomic multi-char CGEvent chunks
- `TextInjector.typeIncremental(_:)` - Streaming: no initial delay, 10ms/char

**Dependencies**:
- ← Transcription/LLM (receives final text or token stream)
- ← Permissions (requires Accessibility)

**Complexity**: Medium

---

## Feature 5: Hotkey Management

**Purpose**: Global keyboard shortcuts with smart toggle/hold-to-record detection, language toggle, and auto-type toggle

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/HotkeyManager.swift` | HotKey library wrapper (~530 lines) |
| `Yapper/Models/KeyboardShortcut.swift` | Shortcut model with Carbon key codes (~240 lines) |
| `Yapper/Views/ShortcutRecorderView.swift` | Interactive shortcut capture |

**Entry Points**:
- `HotkeyManager.register(shortcut:action:)`
- `HotkeyManager.registerLanguageToggleHotkey(shortcut:handler:)`
- `HotkeyManager.registerAutoTypeToggleHotkey(shortcut:handler:)`
- `HotkeyManager.updateShortcuts()`

**Dependencies**:
- → Recording flow (triggers start/stop/cancel)
- → Language switching (triggers language toggle)
- → Auto-type toggle (triggers auto-type state change)

**Complexity**: Medium

---

## Feature 6: Transcript History

**Purpose**: Persists transcriptions with metadata, search, and time-saved statistics

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/TranscriptHistoryManager.swift` | Observable singleton, JSON persistence |
| `Yapper/Models/TranscriptRecord.swift` | Record model with source type |
| `Yapper/Views/HistoryView.swift` | Searchable card-based UI |
| `Yapper/Views/HistoryWindowController.swift` | Standalone window |

**Entry Points**:
- `TranscriptHistoryManager.shared.add(record:)`
- History menu item → `HistoryWindowController`
- Copy Last Transcript menu item → `AppDelegate.copyLastTranscript()`

**Dependencies**:
- ← Transcription
- ← File Transcription

**Complexity**: Medium

---

## Feature 7: File Transcription

**Purpose**: Transcribes existing audio files (MP3, WAV, M4A)

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/AudioFileReader.swift` | File loading/conversion |
| `Yapper/Views/FileTranscriptionView.swift` | File picker, progress, results |
| `Yapper/Views/FileTranscriptionWindowController.swift` | Window with close confirmation |

**Entry Points**:
- File Transcription menu item → `FileTranscriptionWindowController`
- `AudioFileReader.loadAudio(from:)`

**Dependencies**:
- → Transcription Service
- → History

**Complexity**: High

---

## Feature 8: Licensing & Free Trial

**Purpose**: Polar license validation, device activation, 7-day free trial, app gating

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/LicenseService.swift` | Polar API integration, LicenseState (incl. trial states) |
| `Yapper/Services/TrialService.swift` | 7-day trial (Keychain, HMAC-SHA256, tombstone, clock rollback) |
| `Yapper/Views/LicenseActivationView.swift` | Modal UI for all license states + trial expired |
| `Yapper/Views/LicenseWindowController.swift` | Blocking modal window |

**Entry Points**:
- `LicenseService.checkLicense()`
- `LicenseService.activateLicense(key:)`
- `TrialService.shared.checkOrStartTrial()`

**Dependencies**:
- → App lifecycle (blocks startup)
- → Keychain (trial storage)

**Complexity**: High

---

## Feature 9: Settings & Preferences

**Purpose**: Unified configuration interface for all features. Redesigned in v2.0 with NavigationSplitView sidebar (macOS System Settings style).

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Views/SettingsView.swift` | NavigationSplitView settings (~850 lines): Transcription, AI, Preferences |
| `Yapper/Views/AIEnhancementSettingsView.swift` | AI tab (Transform + Q&A mode descriptions) |
| `Yapper/Views/PermissionStatusView.swift` | Permission status component |
| `Yapper/Views/MicrophoneLevelView.swift` | Mic level meter in Transcription pane |

**Entry Points**:
- Settings menu item → `SettingsWindowController`
- `openSettingsWindow(initialPane:)` (renamed from `initialTab:`)

**Key Changes (v2.0)**:
- Tabs renamed: General → Preferences, AI Enhancement → AI
- `SettingsTab` enum → `SettingsPane`
- Permissions banner (orange gradient) at top when mic/accessibility missing
- "Sound", "Overlay Position", "Text Output" merged into single "Output" section
- Auto-enhancement toggle and custom prompt editor removed
- Window: 750x520, resizable (min 650x400)

**Dependencies**:
- → All features (configuration)

**Complexity**: Medium

---

## Feature 10: Recording Overlay UI

**Purpose**: Floating indicator showing recording state and audio visualization, with cursor-following or fixed top-center positioning. In v2.0, includes AI response cards with Markdown rendering.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Views/OverlayWindow.swift` | Non-activating window, waveform, AI response cards (~750 lines) |
| `Yapper/Views/MarkdownTheme+Yapper.swift` | Custom Markdown theme for AI response overlay |
| `Yapper/Utilities/DesignTokens.swift` | Centralized design constants (glassmorphism, typography, animation) |

**Entry Points**:
- `AppDelegate.showOverlay(state:)`

**Dependencies**:
- ← AppState
- ← MarkdownUI (SPM dependency)

**Complexity**: High

---

## Feature 11: Menu Bar Integration

**Purpose**: Primary app interface as status item with dynamic icon

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/App/AppDelegate.swift` | setupMenuBar(), updateMenuBarIcon() (partial) |

**Entry Points**:
- Click status item → show menu

**Dependencies**:
- → All windows

**Complexity**: Low

---

## Feature 12: Audio Feedback

**Purpose**: Plays system sounds for key state changes (recording start, transcription complete, error)

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/SoundFeedbackService.swift` | NSSound playback service |
| `Yapper/Models/AppState.swift` | soundFeedbackEnabled toggle |
| `Yapper/Views/SettingsView.swift` | Enable/disable toggle in General tab |

**Entry Points**:
- `SoundFeedbackService.play(_:)`

**Dependencies**:
- ← AppState (enabled flag)

**Complexity**: Low

---

## Feature 13: Auto-Updates (Sparkle)

**Purpose**: Automatic update checking and installation via Sparkle framework and appcast.xml

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/App/AppDelegate.swift` | Sparkle updater initialization and menu item |
| `Yapper/Info.plist` | Sparkle feed URL configuration |
| `appcast.xml` | Update feed with version info and signatures |

**Entry Points**:
- Menu bar → "Check for Updates"
- Automatic check on launch

**Dependencies**:
- → Sparkle framework (external)

**Complexity**: Low

---

## Feature 14: Language Switching

**Purpose**: Quick switching between primary and secondary transcription languages via a global hotkey, with visual confirmation

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Models/AppState.swift` | Language state (primaryLanguage, secondaryLanguage, activeLanguage, toggle logic, display name/flag mappings) |
| `Yapper/Views/LanguageSwitchWindow.swift` | Floating confirmation pill (LanguageSwitchWindowController + LanguageSwitchPillView) |
| `Yapper/Views/OverlayWindow.swift` | Shows language flag during recording when secondary language active |
| `Yapper/Views/SettingsView.swift` | Primary/secondary language pickers, language toggle shortcut setting |
| `Yapper/Services/HotkeyManager.swift` | Language toggle hotkey registration |
| `Yapper/Models/KeyboardShortcut.swift` | Default language toggle shortcut (Shift+Option+L), ShortcutType.languageToggle |
| `Yapper/App/AppDelegate.swift` | handleLanguageToggle() orchestration, language switch window management |
| `Yapper/App/Notifications.swift` | languageToggleShortcutChanged notification name |

**Entry Points**:
- Language toggle hotkey press → `AppDelegate.handleLanguageToggle()`
- Settings > Transcription > Primary/Secondary Language pickers

**Dependencies**:
- ← Hotkey Management (language toggle shortcut)
- → Transcription (provides activeLanguage for WhisperKit)
- → Recording Overlay (shows language flag)

**Complexity**: Medium

**Key Design Decisions**:
- Language toggle state resets on app launch (not persistent between sessions)
- Language switch window is intentionally decoupled from recording overlay to avoid state conflicts
- Toggle is ignored during active recording
- Primary and secondary languages cannot match

---

## Feature 15: Model Storage Management

**Purpose**: Track disk usage of downloaded speech models, cancel in-progress downloads, and clear downloaded models

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Utilities/ModelStorageManager.swift` | Stateless utility for disk usage tracking and model cleanup |
| `Yapper/Views/SettingsView.swift` | Disk usage display, "Clear Downloaded Models" button, cancel download button |
| `Yapper/App/AppDelegate.swift` | Cancellable `modelLoadingTask`, handles cancel/clear notifications |
| `Yapper/App/Notifications.swift` | `.modelDownloadCancelled`, `.modelsCleared` notification names |
| `Yapper/Models/AppState.swift` | `isLoadingModel`, `loadedModel` state |

**Entry Points**:
- Settings > Transcription > Cancel download button
- Settings > Transcription > "Clear Downloaded Models" button

**Dependencies**:
- ← Transcription (model files)
- → Transcription (triggers re-download after clear)

**Complexity**: Low

---

## Feature 16: Auto-Type Toggle

**Purpose**: Enables/disables automatic text injection into the focused application. When disabled, transcriptions are still saved to history but no text is typed — useful for dictating without inserting text.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Models/AppState.swift` | `autoTypeEnabled` property, persistence, `autoTypeToggleShortcut` |
| `Yapper/App/AppDelegate.swift` | Toggle handler, menu item (checkmark), conditional injection in streaming/batch paths |
| `Yapper/Models/KeyboardShortcut.swift` | `defaultAutoTypeToggle` (Shift+Option+T), `ShortcutType.autoTypeToggle` |
| `Yapper/Services/HotkeyManager.swift` | Auto-type toggle hotkey registration |
| `Yapper/Views/SettingsView.swift` | Shortcut row + "Text Output" toggle section |
| `Yapper/Views/ToastPillWindow.swift` | Toast pill confirmation (shows "Auto-type On/Off") |

**Entry Points**:
- Auto-type toggle hotkey press → `AppDelegate.handleAutoTypeToggle()`
- Menu bar → Auto-type checkmark item
- Settings > General > Text Output toggle

**Dependencies**:
- ← Hotkey Management (auto-type toggle shortcut)
- → Text Injection (gates `typeText()` and streaming injection)
- → Toast Pill Window (visual confirmation)

**Complexity**: Low

**Key Design Decisions**:
- Default enabled (`true`) — preserves existing behavior for upgrades
- Uses `object(forKey:)` with nil-coalescing so existing installations default to `true`
- Streaming path captures `shouldType` flag before entering async stream loop
- Transcripts always saved to history regardless of auto-type setting

---

## Feature 17: AI Transform Mode

**Purpose**: Voice-driven text rewriting. Select text in any app, press hotkey, speak an instruction, and the selected text is replaced with an AI-rewritten version streamed into an overlay card.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/AccessibilityReader.swift` | Read selected text via AXUIElement API (200ms timeout, secure field detection) |
| `Yapper/Models/AppState.swift` | InteractionMode.aiTransform, aiResponseText, isAIResponseStreaming |
| `Yapper/Services/LLMService.swift` | transform(), transformStream(), resolveProvider() |
| `Yapper/Services/TextInjector.swift` | deleteSelection() — simulates Delete key |
| `Yapper/Views/OverlayWindow.swift` | AI response card (480x360), cursor-anchored positioning |
| `Yapper/App/AppDelegate.swift` | Selection detection, transform flow branching |

**Entry Points**:
- Recording hotkey with text selected → `AccessibilityReader.readSelectedText()` → AI Transform flow

**Dependencies**:
- ← Voice Recording (transcribes instruction)
- ← LLM AI Services (transforms text)
- → Text Injection (replaces selected text)
- ← Accessibility permission (AXUIElement)

**Complexity**: High

---

## Feature 18: AI Q&A Voice Assistant ("Hey Yapper")

**Purpose**: Say "Hey Yapper" followed by a question during recording to get an AI-generated answer in a floating panel. 35+ wake-phrase variants recognized.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Models/AppState.swift` | InteractionMode.aiQA, detectHeyYapper(), shared streaming state |
| `Yapper/Services/LLMService.swift` | qaStream(question:) |
| `Yapper/Views/OverlayWindow.swift` | Q&A card UI (question bar, answer body, copy button) |
| `Yapper/App/AppDelegate.swift` | Post-transcription routing (Hey Yapper detection) |

**Entry Points**:
- Automatic detection of "Hey Yapper" in transcription

**Dependencies**:
- ← Voice Recording + Transcription
- ← LLM AI Services
- Shared streaming infrastructure with Transform mode

**Complexity**: Medium

---

## Feature 19: Microphone Selection

**Purpose**: Choose which microphone Yapper uses with hot-plug support and automatic fallback.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/AudioDeviceManager.swift` | CoreAudio HAL enumeration, property listeners, level metering |
| `Yapper/Services/AudioInputDevice.swift` | Device model (volatile audioDeviceID + stable UID) |
| `Yapper/Views/MicrophoneLevelView.swift` | Live level meter (4px bar, green/yellow/red thresholds) |
| `Yapper/Services/AudioRecorder.swift` | startRecording(deviceID:callback:), setInputDevice() |
| `Yapper/Views/SettingsView.swift` | Input Device picker in Transcription pane |

**Entry Points**:
- Settings > Transcription > Input Device

**Dependencies**:
- → Voice Recording (provides deviceID)

**Complexity**: Medium

---

## Feature 20: Free Trial Licensing

**Purpose**: 7-day free trial for new users with Keychain-based tamper-resistant storage.

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Services/TrialService.swift` | Keychain storage, HMAC-SHA256, tombstone pattern, clock rollback detection |
| `Yapper/Services/LicenseService.swift` | LicenseState.trialActive, .trialExpired, canUseApp |
| `Yapper/Views/LicenseActivationView.swift` | Trial expired modal |
| `Yapper/Views/SettingsView.swift` | Trial badge with remaining days |
| `Yapper/App/AppDelegate.swift` | Trial check flow on startup |

**Entry Points**:
- `TrialService.shared.checkOrStartTrial()` (called from AppDelegate)

**Dependencies**:
- → Licensing (extends LicenseState)
- → Keychain (trial payload)

**Complexity**: Medium

---

## Feature 21: Glassmorphism UI / DesignTokens

**Purpose**: Centralized design system with frosted-glass aesthetics and dark/light theme support.

**User-Facing**: Yes (visual)

**Files**:
| File | Role |
|------|------|
| `Yapper/Utilities/DesignTokens.swift` | Radius, padding, spacing, size, material, typography, animation constants |
| `Yapper/Views/OverlayWindow.swift` | ultraThinMaterial backgrounds, spring animations, 18pt corner radius |
| `Yapper/Views/ToastPillWindow.swift` | Glass-style toasts |

**Entry Points**:
- Used throughout overlay and toast views

**Dependencies**:
- ← ColorScheme (dark/light mode awareness)

**Complexity**: Low

---

## Feature 22: Markdown Rendering

**Purpose**: AI responses render with full Markdown formatting (headings, bold, code blocks, lists, tables).

**User-Facing**: Yes

**Files**:
| File | Role |
|------|------|
| `Yapper/Views/MarkdownTheme+Yapper.swift` | Custom Theme.yapperOverlay(for: ColorScheme) factory |
| `Yapper/Views/OverlayWindow.swift` | Markdown view in AI response cards |

**Entry Points**:
- Automatic when AI response contains Markdown

**Dependencies**:
- ← MarkdownUI SPM dependency (cmark-gfm C parser)
- ← DesignTokens (colors, typography)

**Complexity**: Low

---

## Shared/Core Code

| File | Purpose |
|------|---------|
| `Yapper/App/YapperApp.swift` | Entry point |
| `Yapper/App/AppDelegate.swift` | Central coordinator |
| `Yapper/App/Notifications.swift` | NotificationCenter names |
| `Yapper/Models/AppState.swift` | Central observable state |
| `Yapper/Utilities/Logging.swift` | Categorized loggers |
| `Yapper/Utilities/Formatters.swift` | Duration/size formatting |

---

## Feature Dependency Graph

```
┌─────────────────┐
│   Menu Bar      │
└────────┬────────┘
         │ opens
         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Settings     │     │     History     │     │ File Transcribe │
└─────────────────┘     └────────▲────────┘     └────────┬────────┘
                                 │                       │
                                 │ saves                 │ uses
                                 │                       ▼
┌─────────────────┐     ┌────────┴────────┐     ┌─────────────────┐
│    Hotkeys      │────▶│  Transcription  │◀────│  AudioFileReader│
└─────────────────┘     └────────┬────────┘     └─────────────────┘
         │ triggers              │
         ▼                       │ post-transcription routing
┌─────────────────┐              ▼
│ Voice Recording │     ┌─────────────────────────────────────────┐
│ (+ Mic Select)  │     │ AI Transform → AI Q&A → Normal Dictation│
└─────────────────┘     └────────┬──────────┬──────────┬──────────┘
                                 │          │          │
                                 ▼          ▼          ▼
                        ┌────────────┐ ┌────────┐ ┌─────────────┐
                        │LLM Service │ │LLM     │ │Text Injection│
                        │ Transform  │ │ Q&A    │ └─────────────┘
                        └────────────┘ └────────┘

┌─────────────────┐
│Licensing + Trial│ (gates entire app)
└─────────────────┘

┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Recording Overlay│   │ Markdown Render │   │  DesignTokens   │
│ (+ AI cards)    │◀──│ (MarkdownUI)    │   │ (glassmorphism) │
└─────────────────┘   └─────────────────┘   └─────────────────┘

┌─────────────────┐
│Language Switching│ ← Hotkeys → Transcription, Overlay
└─────────────────┘

┌─────────────────┐
│ Auto-Type Toggle│ ← Hotkeys → Text Injection (conditional gate)
└─────────────────┘
```

---

## Unclear Boundaries / Improvement Opportunities

1. **AppDelegate (~1,450 lines)** acts as a "god object" handling service initialization, recording orchestration (batch + streaming), model loading/cancellation, menu bar, windows, permissions, and licensing. Consider extracting:
   - `RecordingCoordinator`
   - `WindowManager`
   - `MenuBarController`

2. **AppState (~550 lines)** contains state for all features including language switching and model loading. Current size is manageable but could be split per feature for larger apps.

3. **RecordingState** defined in AppState vs. **OverlayDisplayState** in OverlayWindow creates some conceptual duplication.
