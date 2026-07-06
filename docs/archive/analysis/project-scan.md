# Yapper - Project Analysis

**Generated**: 2026-01-31
**Last Updated**: 2026-03-28
**Codebase Version**: 2.0.0
**Analysis Type**: First-pass exploration for documentation agents

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Technology Stack](#technology-stack)
3. [Directory Structure](#directory-structure)
4. [Architecture Patterns](#architecture-patterns)
5. [Core Components](#core-components)
6. [Service Layer](#service-layer)
7. [View Layer](#view-layer)
8. [Data Flow](#data-flow)
9. [External Dependencies](#external-dependencies)
10. [Configuration & Settings](#configuration--settings)
11. [File Inventory](#file-inventory)
12. [Key Observations](#key-observations)
13. [Recommended Next Steps](#recommended-next-steps)

---

## Project Overview

**Yapper** is a native macOS menu bar application for voice-to-text dictation. It enables users to:

- Record speech using a global keyboard shortcut
- Transcribe audio locally using WhisperKit (on-device ML)
- Transform selected text via voice instructions using LLM APIs (Gemini, OpenAI, Anthropic, xAI)
- Ask questions via "Hey Yapper" voice assistant for AI-generated answers
- Inject the transcribed text directly into any focused text field
- Select a specific microphone for recording input
- Maintain a searchable history of transcriptions

### Key Characteristics

| Attribute | Value |
|-----------|-------|
| **Language** | Swift (100%) |
| **UI Framework** | SwiftUI + AppKit |
| **Target Platform** | macOS 14+ (Sonoma) |
| **Architecture** | Menu bar app (no dock icon) |
| **Distribution** | Direct (notarized, non-sandboxed) |
| **Codebase Size** | 43 Swift files, ~12,000 lines of code |

---

## Technology Stack

### Primary Technologies

| Technology | Purpose | Version |
|------------|---------|---------|
| **Swift** | Primary language | Swift 5+ |
| **SwiftUI** | Declarative UI framework | macOS 14+ |
| **AppKit** | Menu bar, windows, system integration | Native |
| **WhisperKit** | On-device speech-to-text (Whisper models) | 0.9.0+ |
| **FluidAudio** | On-device speech-to-text (NVIDIA Parakeet models) | 0.12.1+ |
| **HotKey** | Global keyboard shortcut registration | 0.2.0+ |
| **Sparkle** | Automatic app updates | 2.x |
| **MarkdownUI** | Markdown rendering in AI response overlays | 2.4.x |

### Framework Usage

| Framework | Use Case |
|-----------|----------|
| `AVFoundation` | Audio recording from microphone |
| `CoreAudio` | HAL device enumeration, property listeners, mic selection (AudioDeviceManager) |
| `CoreGraphics` | Keyboard event simulation (text injection) |
| `Carbon.HIToolbox` | Key code definitions |
| `ApplicationServices` | Accessibility API for text injection and text selection reading (AXUIElement) |
| `Foundation` | Core utilities, JSON, UserDefaults |
| `Observation` | Modern Swift observation (`@Observable`) |

### Build Configuration

- **Xcode Project**: `Yapper.xcodeproj`
- **Minimum macOS**: Defined via `MACOSX_DEPLOYMENT_TARGET`
- **Sandbox**: Disabled (required for Accessibility API)
- **Entitlements**: Audio input, Apple Events automation

---

## Directory Structure

```
/Users/nikolas.b/Dev/yapper/app/
├── .build/                    # Swift Package Manager build artifacts
├── .claude/                   # Claude Code configuration
│   └── agents/               # Agent definitions (if any)
├── .git/                      # Git repository
├── .gitignore                 # Git ignore rules
├── .vscode/                   # VS Code settings
├── dist/                      # Distribution output (builds)
├── docs/                      # Documentation
│   └── analysis/             # Analysis documents (this file)
├── notarized/                 # Notarized app bundles
│   ├── Yapper-1.0.1.app/
│   └── Yapper-0.6.0.app/
├── scripts/
│   └── build-release.sh      # Release build script
├── Yapper/                    # Main source directory
│   ├── App/                  # Application entry points and lifecycle
│   │   ├── YapperApp.swift           # @main entry point
│   │   ├── AppDelegate.swift         # App lifecycle, service coordination
│   │   ├── Bundle+Extensions.swift   # Bundle utilities
│   │   └── Notifications.swift       # NotificationCenter name definitions
│   ├── Models/               # Data models and state
│   │   ├── AppState.swift            # Central observable state (@Observable)
│   │   ├── TranscriptionEngine.swift # Engine enum, ModelIdentifier, AvailableModels, SupportedLanguages
│   │   ├── KeyboardShortcut.swift    # Shortcut model with HotKey conversion
│   │   └── TranscriptRecord.swift    # Transcript history record model
│   ├── Services/             # Business logic and external integrations
│   │   ├── AccessibilityReader.swift  # Selected text reading via AXUIElement API
│   │   ├── AudioRecorder.swift       # Microphone capture (AVAudioEngine)
│   │   ├── AudioDeviceManager.swift  # CoreAudio HAL device enumeration, hot-plug, level metering
│   │   ├── AudioInputDevice.swift    # Audio device model (dual ID: volatile audioDeviceID + stable UID)
│   │   ├── TranscriptionService.swift # Thin coordinator actor (delegates to backends)
│   │   ├── TranscriptionBackend.swift # Backend protocol for pluggable engines
│   │   ├── WhisperKitBackend.swift   # WhisperKit engine implementation
│   │   ├── FluidAudioBackend.swift   # FluidAudio (NVIDIA Parakeet) engine implementation
│   │   ├── LLMService.swift          # Multi-provider LLM enhancement
│   │   ├── TextInjector.swift        # Accessibility-based text typing + streaming
│   │   ├── HotkeyManager.swift       # Global shortcut registration
│   │   ├── LicenseService.swift      # Polar license key validation
│   │   ├── APIKeyStorage.swift       # Keychain storage for API keys
│   │   ├── AudioFileReader.swift     # File-based audio transcription
│   │   ├── SoundFeedbackService.swift # Audio feedback for state changes
│   │   ├── TranscriptHistoryManager.swift # History persistence
│   │   └── TrialService.swift        # 7-day free trial (Keychain, HMAC-SHA256)
│   ├── Views/                # SwiftUI views and window controllers
│   │   ├── OverlayWindow.swift       # Floating recording indicator
│   │   ├── LanguageSwitchWindow.swift # Language switch confirmation pill
│   │   ├── SettingsView.swift        # Settings window (tabbed)
│   │   ├── AIEnhancementSettingsView.swift # LLM configuration
│   │   ├── HistoryView.swift         # Transcript history browser
│   │   ├── FileTranscriptionView.swift # File transcription UI
│   │   ├── LicenseActivationView.swift # License entry modal
│   │   ├── MicrophoneLevelView.swift   # Real-time mic level meter (green/yellow/red)
│   │   ├── PermissionStatusView.swift  # Permission indicators
│   │   ├── ShortcutRecorderView.swift  # Keyboard shortcut capture
│   │   ├── MarkdownTheme+Yapper.swift  # Custom Markdown theme for AI response overlay
│   │   └── *WindowController.swift   # NSWindowController wrappers
│   ├── Utilities/            # Shared utilities
│   │   ├── DesignTokens.swift        # Centralized design constants (radius, padding, colors, typography)
│   │   ├── Logging.swift             # Centralized os.Logger definitions
│   │   ├── Formatters.swift          # Duration formatting utilities
│   │   └── ModelStorageManager.swift # Model disk usage tracking and cleanup
│   ├── Resources/            # Asset catalogs
│   ├── Assets.xcassets/      # App icons and images
│   ├── Logo.icon/            # App icon source files
│   ├── Info.plist            # App metadata and permissions
│   └── Yapper.entitlements   # macOS entitlements
└── Yapper.xcodeproj/         # Xcode project configuration
    ├── project.pbxproj       # Build settings and targets
    └── xcshareddata/         # Shared schemes
```

---

## Architecture Patterns

### Overall Architecture

The application follows a **layered architecture** with clear separation:

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                          │
│  (OverlayView, SettingsView, HistoryView, etc.)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    AppDelegate (Coordinator)                 │
│  - Service initialization                                   │
│  - Recording flow orchestration                             │
│  - Menu bar management                                      │
│  - NotificationCenter event routing                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      AppState (@Observable)                  │
│  - Centralized reactive state                               │
│  - UserDefaults persistence                                 │
│  - State machine (RecordingState enum)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Service Layer                          │
│  AudioRecorder | TranscriptionService | LLMService          │
│  TextInjector | HotkeyManager | LicenseService              │
└─────────────────────────────────────────────────────────────┘
```

### Key Patterns

1. **Observable State Pattern**
   - `AppState` uses Swift's `@Observable` macro (macOS 14+)
   - Views automatically re-render on state changes
   - Similar to MobX/Zustand in React ecosystem

2. **Coordinator Pattern (AppDelegate)**
   - `AppDelegate` acts as the central coordinator
   - Initializes and wires together all services
   - Handles the recording/transcription/injection flow
   - Manages window lifecycle

3. **Actor Isolation**
   - `TranscriptionService` is an `actor` for thread-safe Whisper access
   - Services use `@MainActor` annotation for UI-bound state

4. **NotificationCenter for Decoupling**
   - Settings changes broadcast via NotificationCenter
   - AppDelegate subscribes and reacts (e.g., shortcut updates, API key changes)

5. **Protocol-Based Abstraction**
   - `LLMProvider` protocol enables multi-provider LLM support
   - `TranscriptionBackend` protocol enables multi-engine transcription (WhisperKit, FluidAudio)
   - Each provider/backend implements the same interface for interchangeability

---

## Core Components

### Entry Point: `YapperApp.swift`

```swift
@main
struct YapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}
```

- Uses `@main` attribute as Swift entry point
- Bridges SwiftUI lifecycle with AppKit's `AppDelegate`
- Only defines a `Settings` scene (menu bar apps don't need windows)

### AppDelegate: Service Coordinator

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/App/AppDelegate.swift`

Responsibilities:
- Initialize all services on app launch
- Set up menu bar (`NSStatusBar`)
- Register global keyboard shortcuts
- Orchestrate recording flow: start → record → stop → transcribe → enhance → inject
- Check/prompt for permissions (microphone, accessibility)
- Handle license validation on launch

### AppState: Observable State Container

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Models/AppState.swift`

Key state properties:
- `recordingState: RecordingState` - State machine (idle, recording, processing, aiTransforming, aiTransformResult, aiQA, aiQAResult, error)
- `audioLevel: Float` - Real-time audio level for visualization
- `selectedModel: String` - Model selection in colon format (e.g. `"parakeet:tdt-0.6b-v3"`)
- `primaryLanguage: String` - Primary transcription language
- `secondaryLanguage: String?` - Optional secondary language
- `activeLanguage: String` - Computed: current language for transcription
- `customVocabulary: [String]` - User-defined terms
- `isModelLoaded: Bool` - Model readiness
- `isLoadingModel: Bool` - True while model loading is in progress
- `loadedModel: String?` - The model that is actually loaded (nil if none)
- `selectedMicrophoneUID: String?` - Persisted microphone selection (nil = system default)
- `availableInputDevices: [AudioInputDevice]` - Connected audio input devices
- `hasMicrophonePermission: Bool` - Permission status
- `hasAccessibilityPermission: Bool` - Permission status
- `isInTrial: Bool` - Whether app is in free trial
- `trialDaysRemaining: Int?` - Days remaining in trial

Persisted via UserDefaults:
- Model selection, language, vocabulary
- Keyboard shortcuts
- AI enhancement settings
- History retention period

### RecordingState Enum

```swift
enum RecordingState: Equatable {
    case idle                     // Ready to record
    case recording                // Actively capturing audio
    case processing               // WhisperKit transcribing
    case aiTransforming           // AI Transform streaming in progress
    case aiTransformResult        // AI Transform result ready
    case aiQA                     // AI Q&A streaming in progress
    case aiQAResult               // AI Q&A result ready
    case error(message: String)   // Error state with message
}
```

---

## Service Layer

### AudioRecorder

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/AudioRecorder.swift`

- Uses `AVAudioEngine` for real-time microphone capture
- Resamples audio to 16kHz mono (WhisperKit requirement)
- Provides real-time audio level callbacks for visualization
- Returns raw PCM `Data` when recording stops
- `startRecording(deviceID:callback:) -> Bool` accepts optional device ID for mic selection
- `setInputDevice(_:)` configures AudioUnit via CoreAudio HAL

### TranscriptionService

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TranscriptionService.swift`

- Actor-based thin coordinator that delegates to active `TranscriptionBackend`
- Supports both batch and streaming transcription
- Parses colon-format model IDs (`"whisper:large-v3-turbo"`, `"parakeet:tdt-0.6b-v3"`)
- Creates appropriate backend (WhisperKitBackend or FluidAudioBackend)
- Automatically unloads previous backend before loading new one

### TranscriptionBackend Protocol

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TranscriptionBackend.swift`

- Defines `loadModel`, `transcribe`, `transcribeStreaming`, `unloadModel` interface
- Implemented by `WhisperKitBackend` (WhisperKit) and `FluidAudioBackend` (NVIDIA Parakeet)
- WhisperKit: downloads from HuggingFace, supports streaming, Neural Engine + CoreML
- FluidAudio: NVIDIA Parakeet TDT models, 110-190x real-time speed, batch-only

### TranscriptionEngine & Model Registry

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Models/TranscriptionEngine.swift`

- `TranscriptionEngine` enum: `.whisper`, `.parakeet`
- `ModelIdentifier` struct: colon-format parsing, legacy migration, WhisperKit name mapping
- `AvailableModels`: static registry of all downloadable models with metadata
- `SupportedLanguages`: centralized language code/name/flag metadata (single source of truth)

### LLMService

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/LLMService.swift`

Multi-provider LLM integration:
- **Gemini** (Google) - gemini-3-flash-preview, gemini-3-pro-preview
- **OpenAI** - gpt-5-mini, gpt-5-nano
- **Anthropic** - claude-sonnet-4-5, claude-haiku-4-5
- **xAI** - grok-4, grok-4-1-fast

Features:
- AI Transform: `transform()` / `transformStream()` for voice-driven text rewriting
- AI Q&A: `qaStream(question:)` for voice assistant answers
- Native SSE streaming via `LLMProvider.enhanceStream()` for all 4 providers
- API key storage via `APIKeyStorage` (Keychain)
- Validation of API keys before saving
- AI is strictly user-initiated (no auto-enhancement)

### TextInjector

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TextInjector.swift`

- Simulates keyboard input using CoreGraphics events
- Injects text character-by-character into focused field
- `typeStringAtomically()` for streaming: posts up to 20 UTF-16 units per CGEvent (prevents interleaving)
- `typeIncremental()` for streaming: no initial delay, 10ms/char
- Requires Accessibility permission (System Settings)
- Fallback: clipboard-based paste method

### HotkeyManager

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/HotkeyManager.swift`

- Uses HotKey library (wraps Carbon APIs)
- Supports smart detection: quick-press (toggle) vs. hold-to-record
- Default shortcuts:
  - Start/Stop: Option+Space
  - Cancel: Escape
  - Toggle Language: Shift+Option+L

### LicenseService

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/LicenseService.swift`

- Integrates with Polar for license key validation
- Supports sandbox (DEBUG) and production environments
- Manages activation, validation, and deactivation
- Stores license info in UserDefaults
- New `LicenseState` cases: `.trialActive(daysRemaining:)`, `.trialExpired`
- `canUseApp` returns `true` for both `.valid` and `.trialActive`

### TrialService

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TrialService.swift`

- 7-day free trial with Keychain storage (opaque service/account identifiers)
- HMAC-SHA256 signing for tamper detection
- Tombstone pattern prevents fresh-start bypasses
- Clock rollback detection
- Purchase URL: `yapper.to`

### TranscriptHistoryManager

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TranscriptHistoryManager.swift`

- Persists transcripts to JSON in Application Support
- Configurable retention period (default 90 days)
- Search, filter by date, statistics (time saved calculations)
- Observable for reactive UI updates

---

## View Layer

### OverlayWindow

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Views/OverlayWindow.swift`

- Floating pill-shaped indicator during recording
- Positioned near cursor (default) or fixed at top-center of screen (configurable)
- Shows state: recording (red), processing (blue), AI modes (purple), success (green)
- Audio waveform visualization during recording
- AI response card (480x360) with Markdown rendering, auto-scroll, copy button
- Glassmorphism design with `ultraThinMaterial` backgrounds, DesignTokens system
- Spring-based animations for card expand/collapse
- Cursor-anchored positioning for AI cards
- Non-activating window (doesn't steal focus)

### SettingsView

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Views/SettingsView.swift`

NavigationSplitView sidebar settings (macOS System Settings style):
1. **Transcription** - Model selection, primary/secondary language pickers, custom vocabulary, input device selection with live level meter
2. **AI** - Provider/model selection, API keys; explains Transform and Q&A modes (user-initiated only, no auto-enhancement)
3. **Preferences** - Keyboard shortcuts (recording, cancel, language toggle), merged Output section (sound, overlay position, text output), license management
- Permissions banner (orange gradient) at top when mic/accessibility missing
- Window: 750x520, resizable (min 650x400), 12pt corner radius

### HistoryView

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Views/HistoryView.swift`

- Searchable list of past transcriptions
- Copy/delete individual records
- Statistics display (total time saved)
- Bulk selection and deletion

### FileTranscriptionView

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Views/FileTranscriptionView.swift`

- Drag-and-drop audio file transcription
- Progress indicator during processing
- Copy result to clipboard

---

## Data Flow

### Recording Flow

```
1. User presses Option+Space (HotkeyManager)
         │
         ▼
2. AppDelegate.handleRecordingKeyDown()
         │
         ├── Check permissions (mic, accessibility)
         ├── Check model loaded
         │
         ▼
3. AppDelegate.startRecording()
         │
         ├── appState.startRecording() → recordingState = .recording
         ├── overlayWindow.show()
         │
         ▼
4. AudioRecorder.startRecording(deviceID:callback:)
         │
         ├── AVAudioEngine captures audio (optional device selection)
         ├── Resamples to 16kHz mono
         ├── Calls callback with RMS values
         │
         ▼
5. User releases shortcut / presses again
         │
         ▼
6. AppDelegate.stopRecording()
         │
         ├── appState.stopRecording() → recordingState = .processing
         ├── audioData = audioRecorder.stopRecording()
         │
         ▼
7. AppDelegate.transcribeAudio(audioData)
         │
         ├── transcriptionService.transcribe(audioData, language, vocabulary)
         ├── WhisperKit/FluidAudio processes audio → text
         │
         ▼
8. Post-transcription routing (priority order):
         │
         ├── AI Transform mode (text was selected)?
         │   └── llmService.transformStream() → overlay result card
         │
         ├── "Hey Yapper" detected in transcription?
         │   └── llmService.qaStream(question:) → overlay Q&A card
         │
         └── Normal dictation:
             └── TextInjector.typeText(finalText)
         │
         ▼
9. appState.completeTranscription(text)
         │
         ├── recordingState = .idle
         ├── showCompletedIndicator = true (1 second)
         ├── overlayWindow.hide()
         │
         ▼
10. TranscriptHistoryManager.addRecord(record)
         │
         └── Persist to JSON file
```

### Notification Flow

| Notification | Source | Handler |
|--------------|--------|---------|
| `.toggleRecording` | Menu bar | AppDelegate.handleToggleRecordingNotification |
| `.menuBarNeedsUpdate` | AppState | AppDelegate.handleMenuBarUpdate |
| `.shortcutsChanged` | SettingsView | AppDelegate.handleShortcutsChanged |
| `.apiKeyChanged` | Settings | AppDelegate.handleAPIKeyChanged |
| `.llmProviderChanged` | Settings | AppDelegate.handleLLMProviderChanged |
| `.modelSelectionChanged` | Settings | AppDelegate.handleModelSelectionChanged |
| `.permissionsNeedRefresh` | Settings | AppDelegate.handlePermissionsRefresh |
| `.modelDownloadCancelled` | Settings | AppDelegate cancels in-progress download |
| `.modelsCleared` | Settings | AppDelegate re-downloads selected model |
| `.licenseStateChanged` | LicenseService | AppDelegate.handleLicenseStateChanged |

---

## External Dependencies

### Swift Package Dependencies

| Package | Repository | Version | Purpose |
|---------|-----------|---------|---------|
| **WhisperKit** | [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit.git) | 0.9.0+ | On-device speech-to-text using Whisper models |
| **FluidAudio** | FluidAudio | 0.12.1+ | On-device speech-to-text using NVIDIA Parakeet models |
| **HotKey** | [soffes/HotKey](https://github.com/soffes/HotKey.git) | 0.2.0+ | Global keyboard shortcut registration |
| **MarkdownUI** | [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | 2.4.x | Markdown rendering in AI response overlay (uses cmark-gfm C parser) |

### External Services

| Service | API | Purpose |
|---------|-----|---------|
| **HuggingFace** | Model downloads | WhisperKit model hosting |
| **Polar** | License API | License key validation |
| **Gemini** | generativelanguage.googleapis.com | Text enhancement |
| **OpenAI** | api.openai.com | Text enhancement |
| **Anthropic** | api.anthropic.com | Text enhancement |
| **xAI** | api.x.ai | Text enhancement (Grok) |
| **Sparkle appcast** | R2/CDN hosted appcast.xml | Automatic update feed |

---

## Configuration & Settings

### Info.plist

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Info.plist`

Key settings:
- `LSUIElement = true` - Menu bar only (no dock icon)
- `NSMicrophoneUsageDescription` - Permission dialog text
- `LSApplicationCategoryType = public.app-category.productivity`
- `SUFeedURL` - Sparkle appcast.xml feed URL for auto-updates
- `SUPublicEDKey` - Sparkle EdDSA public key for update signature verification

### Entitlements

**Location**: `/Users/nikolas.b/Dev/yapper/app/Yapper/Yapper.entitlements`

```xml
com.apple.security.app-sandbox = false
com.apple.security.device.audio-input = true
com.apple.security.automation.apple-events = true
```

### UserDefaults Keys

| Key | Type | Purpose |
|-----|------|---------|
| `selectedModel` | String | Model in colon format (e.g. `"parakeet:tdt-0.6b-v3"`, `"whisper:large-v3-turbo"`) |
| `selectedLanguage` | String | Language code (en, es, fr, etc.) |
| `customVocabulary` | [String] | Custom terms for recognition |
| `primaryLanguage` | String | Primary transcription language |
| `secondaryLanguage` | String | Optional secondary language |
| `shortcut_recordingToggle` | Data (JSON) | Encoded KeyboardShortcut |
| `shortcut_cancelRecording` | Data (JSON) | Encoded KeyboardShortcut |
| `shortcut_languageToggle` | Data (JSON) | Language toggle shortcut |
| `historyRetentionDays` | Int | Days to keep transcripts (default 90) |
| `selectedLLMProvider` | String | gemini, openai, anthropic, xai |
| `selectedLLMModel` | String | Model identifier |
| `soundFeedbackEnabled` | Bool | Audio feedback toggle |
| `selectedMicrophoneUID` | String? | Persisted microphone selection (nil = system default) |
| `com.yapper.trial.welcomed` | Bool | Whether trial welcome toast was shown |
| `overlayPositionFixed` | Bool | Fixed vs cursor-following overlay |
| `com.yapper.license.*` | Various | License state persistence |

**Orphaned keys (v1.x, no longer read):**
| `isAIEnhancementEnabled` | Bool | Removed: auto-enhancement feature removed in 2.0 |
| `aiEnhancementPrompt` | String | Removed: custom prompt editor removed in 2.0 |

---

## File Inventory

### Source Files by Category

#### App Layer (4 files, ~1,540 lines)
| File | Lines | Purpose |
|------|-------|---------|
| AppDelegate.swift | ~1,449 | Main coordinator |
| YapperApp.swift | 36 | Entry point |
| Notifications.swift | 43 | Notification names |
| Bundle+Extensions.swift | 8 | Bundle utilities |

#### Models (4 files, ~1,240 lines)
| File | Lines | Purpose |
|------|-------|---------|
| AppState.swift | ~552 | Central state (incl. language switching) |
| TranscriptionEngine.swift | ~298 | Engine enum, ModelIdentifier, AvailableModels, SupportedLanguages |
| KeyboardShortcut.swift | ~235 | Shortcut model (3 shortcut types) |
| TranscriptRecord.swift | ~153 | History record |

#### Services (17 files, ~4,600 lines)
| File | Lines | Purpose |
|------|-------|---------|
| LicenseService.swift | 744 | License validation |
| LLMService.swift | ~750 | Multi-provider LLM (transform, Q&A, streaming) |
| HotkeyManager.swift | ~570 | Global shortcuts (recording, cancel, language toggle) |
| AudioDeviceManager.swift | ~200 | CoreAudio HAL device enumeration, hot-plug, level metering |
| WhisperKitBackend.swift | 253 | WhisperKit engine implementation |
| AudioRecorder.swift | ~260 | Mic capture + device selection |
| AudioFileReader.swift | ~236 | File transcription |
| TranscriptHistoryManager.swift | 226 | History persistence |
| TextInjector.swift | ~240 | Text injection + streaming + deleteSelection() |
| TrialService.swift | 175 | 7-day trial (Keychain, HMAC-SHA256) |
| TranscriptionService.swift | 155 | Thin coordinator actor |
| FluidAudioBackend.swift | 147 | FluidAudio (Parakeet) engine |
| AccessibilityReader.swift | 112 | Selected text reading via AXUIElement API |
| AudioInputDevice.swift | ~50 | Audio device model struct |
| APIKeyStorage.swift | ~56 | Keychain storage |
| TranscriptionBackend.swift | 53 | Backend protocol definition |
| SoundFeedbackService.swift | ~35 | Audio feedback |

#### Views (15 files, ~4,700 lines)
| File | Lines | Purpose |
|------|-------|---------|
| SettingsView.swift | ~850 | NavigationSplitView settings (Transcription, AI, Preferences) |
| OverlayWindow.swift | ~750 | Recording overlay + AI response cards (480x360) + glassmorphism |
| FileTranscriptionView.swift | ~580 | File transcription |
| LicenseActivationView.swift | ~450 | License entry + trial expired modal |
| HistoryView.swift | ~394 | History browser |
| AIEnhancementSettingsView.swift | ~386 | AI settings (Transform + Q&A mode descriptions) |
| ShortcutRecorderView.swift | ~200 | Shortcut capture |
| LanguageSwitchWindow.swift | ~152 | Language switch confirmation pill |
| MicrophoneLevelView.swift | ~100 | Real-time mic level meter (green/yellow/red) |
| MarkdownTheme+Yapper.swift | 145 | Custom Markdown theme for AI overlay |
| PermissionStatusView.swift | ~149 | Permission display |
| *WindowController.swift (3) | ~280 | Window wrappers |

#### Utilities (4 files, ~270 lines)
| File | Lines | Purpose |
|------|-------|---------|
| DesignTokens.swift | 119 | Centralized design constants (radius, padding, colors, typography, animation) |
| ModelStorageManager.swift | 91 | Model disk usage tracking and cleanup |
| Formatters.swift | ~43 | Duration formatting |
| Logging.swift | 16 | Logger definitions |

### Total: ~43 Swift files, ~12,000 lines

---

## Key Observations

### Strengths

1. **Well-Documented Code**
   - Extensive inline comments explaining Swift/SwiftUI concepts
   - Analogies to TypeScript/React for developer onboarding
   - Clear MARK sections for code organization

2. **Modern Swift Patterns**
   - Uses `@Observable` macro (macOS 14+)
   - Actor isolation for thread safety
   - Async/await throughout

3. **Clean Separation of Concerns**
   - Services are isolated and focused
   - State management centralized in AppState
   - NotificationCenter for loose coupling

4. **Multi-Provider Support**
   - Extensible LLM integration via protocol
   - Easy to add new providers

5. **Thoughtful UX**
   - Non-activating overlay (doesn't steal focus)
   - Smart shortcut detection (toggle vs. hold)
   - Comprehensive permissions handling

### Areas for Future Exploration

1. **Error Handling**
   - Some error paths could use more graceful recovery
   - Network errors during transcription need robust handling

2. **Testing**
   - No test files identified in the codebase
   - Unit tests for services would be valuable

3. **Localization**
   - UI strings are hardcoded
   - No .strings files for internationalization

4. **Analytics**
   - No crash reporting or usage analytics observed
   - Could help with debugging production issues

---

## Recommended Next Steps

### For Documentation Agents

1. **API Documentation**
   - Document public interfaces of each service
   - Create type definitions for all models
   - Generate method signatures with parameter descriptions

2. **User Flow Documentation**
   - Map all user interactions to code paths
   - Document error states and recovery flows
   - Create sequence diagrams for complex flows

3. **Architecture Deep Dive**
   - Document the AppDelegate coordination pattern in detail
   - Explain the state machine (RecordingState) transitions
   - Map NotificationCenter event flows

4. **Integration Guide**
   - Document LLM provider integration pattern
   - Explain WhisperKit model management
   - Cover Polar license integration

5. **Developer Onboarding**
   - Create setup guide (Xcode requirements, dependencies)
   - Document the build-release.sh workflow
   - Explain entitlements and permissions

### Priority Files for Deeper Analysis

1. `/Users/nikolas.b/Dev/yapper/app/Yapper/App/AppDelegate.swift` - Central coordinator, complex flow
2. `/Users/nikolas.b/Dev/yapper/app/Yapper/Models/AppState.swift` - State management
3. `/Users/nikolas.b/Dev/yapper/app/Yapper/Models/TranscriptionEngine.swift` - Engine enum, model registry, language metadata
4. `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/TranscriptionService.swift` - Multi-engine coordinator
5. `/Users/nikolas.b/Dev/yapper/app/Yapper/Services/LLMService.swift` - Multi-provider pattern
6. `/Users/nikolas.b/Dev/yapper/app/Yapper/Views/OverlayWindow.swift` - Complex SwiftUI + AppKit bridge

---

*This document was generated as a first-pass exploration of the Yapper codebase and updated for v2.0.0. It is intended to provide context for subsequent documentation agents and should be updated as the codebase evolves.*
