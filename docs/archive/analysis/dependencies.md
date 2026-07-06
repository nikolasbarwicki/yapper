# Yapper - Dependency Analysis

**Generated**: 2026-01-31
**Last Updated**: 2026-03-28
**Codebase Version**: 2.0.0
**Analysis Scope**: External packages, system frameworks, internal module dependencies, coupling patterns

---

## Table of Contents

1. [External Dependencies](#external-dependencies)
2. [System Framework Dependencies](#system-framework-dependencies)
3. [Internal Module Dependencies](#internal-module-dependencies)
4. [Coupling Analysis](#coupling-analysis)
5. [Dependency Direction & Cycles](#dependency-direction--cycles)
6. [Dependency Graph Visualization](#dependency-graph-visualization)
7. [Recommendations](#recommendations)

---

## External Dependencies

### Swift Package Dependencies

| Package | Repository | Purpose | Category |
|---------|-----------|---------|----------|
| **WhisperKit** | [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit.git) | On-device speech-to-text using OpenAI Whisper models via CoreML/Neural Engine | Core ML / Transcription |
| **FluidAudio** | FluidAudio | On-device speech-to-text using NVIDIA Parakeet TDT models | ML / Transcription |
| **HotKey** | [soffes/HotKey](https://github.com/soffes/HotKey.git) | Global keyboard shortcut registration (wraps Carbon APIs) | Input / System Integration |
| **Sparkle** | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | Automatic app update checking and installation | Distribution / Updates |
| **MarkdownUI** | [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering in AI response overlay (cmark-gfm C parser) | UI / Rendering |

### Dependency Analysis

#### WhisperKit
- **Used by**: `WhisperKitBackend.swift`
- **Import style**: `@preconcurrency import WhisperKit`
- **Key types used**: `WhisperKit`, `DecodingOptions`, `ModelComputeOptions`
- **Transitive dependencies**: CoreML, Accelerate, Neural Engine frameworks
- **Network calls**: Downloads models from HuggingFace on first use
- **Size impact**: Significant (includes CoreML model runners)

#### FluidAudio
- **Used by**: `FluidAudioBackend.swift`, `TranscriptionEngine.swift`
- **Import style**: `import FluidAudio`
- **Key types used**: `AsrModels`, `AsrModelVersion`, `AsrPipeline`
- **Transitive dependencies**: CoreML (for model loading)
- **Network calls**: Downloads Parakeet model files on first use
- **Size impact**: Moderate (includes model loading and inference runtime)

#### HotKey
- **Used by**: `HotkeyManager.swift`, `KeyboardShortcut.swift`
- **Import style**: `import HotKey`
- **Key types used**: `HotKey`, `Key`
- **Transitive dependencies**: Carbon (HIToolbox)
- **Size impact**: Minimal (thin wrapper around Carbon APIs)

#### Sparkle
- **Used by**: `AppDelegate.swift`
- **Import style**: `import Sparkle`
- **Key types used**: `SPUStandardUpdaterController`
- **Network calls**: Fetches appcast.xml from configured feed URL
- **Size impact**: Moderate (includes update UI and delta update support)

#### MarkdownUI
- **Used by**: `OverlayWindow.swift`, `MarkdownTheme+Yapper.swift`
- **Import style**: `import MarkdownUI`
- **Key types used**: `Markdown`, `Theme`, `MarkupContent`
- **Transitive dependencies**: cmark-gfm (C library for GitHub Flavored Markdown parsing)
- **Network calls**: None
- **Size impact**: Moderate (includes C parser and SwiftUI rendering engine)
- **Notes**: Custom theme via `Theme.yapperOverlay(for: ColorScheme)` factory method; re-parses on every streaming token append; supports headings, bold, italic, code blocks, lists, tables, blockquotes

---

## System Framework Dependencies

### By File

| Framework | Files Using It | Purpose |
|-----------|----------------|---------|
| **Foundation** | All files | Core utilities, Date, JSON, UserDefaults, URL |
| **SwiftUI** | All View files, AppState.swift | Declarative UI framework |
| **AppKit** | AppDelegate, Window Controllers, TextInjector, HotkeyManager, KeyboardShortcut | Menu bar, windows, NSEvent, NSPasteboard |
| **AVFoundation** | AudioRecorder.swift, AudioFileReader.swift | Audio capture and file reading (AVAudioEngine) |
| **CoreAudio** | AudioDeviceManager.swift, AudioRecorder.swift | HAL device enumeration, property listeners, mic selection, level metering |
| **Carbon.HIToolbox** | HotkeyManager.swift, KeyboardShortcut.swift, AppDelegate.swift | Virtual key codes (kVK_*) |
| **ApplicationServices** | TextInjector.swift, AccessibilityReader.swift | Accessibility APIs (AXIsProcessTrusted, AXUIElement for text selection reading) |
| **CoreGraphics** | TextInjector.swift | CGEvent for keyboard simulation |
| **Observation** | TranscriptHistoryManager.swift | Swift's @Observable macro |
| **os** | Logging.swift, TranscriptionService.swift, AudioRecorder.swift | Unified logging system (os.Logger) |

### Framework Purpose Matrix

| Category | Frameworks | Primary Use Case |
|----------|-----------|------------------|
| **UI** | SwiftUI, AppKit | Views, windows, menu bar |
| **Audio** | AVFoundation, CoreAudio | Microphone capture, audio file processing, device enumeration/selection |
| **ML** | WhisperKit (CoreML) | On-device speech recognition |
| **Rendering** | MarkdownUI (cmark-gfm) | Markdown formatting in AI response overlay |
| **Input** | HotKey, Carbon.HIToolbox | Global keyboard shortcuts |
| **Accessibility** | ApplicationServices, CoreGraphics | Text injection via keyboard simulation, selected text reading via AXUIElement |
| **System** | Foundation, Observation | Core utilities, reactive state |

---

## Internal Module Dependencies

### Import Map by File

```
Yapper/App/
├── YapperApp.swift
│   └── imports: SwiftUI
│   └── depends on: AppDelegate, AppState, SettingsView
│
├── AppDelegate.swift
│   └── imports: AppKit, SwiftUI, Carbon.HIToolbox
│   └── depends on: AppState, AudioRecorder, TranscriptionService, TextInjector,
│                   LLMService, HotkeyManager, LicenseService, APIKeyStorage,
│                   TranscriptHistoryManager, TranscriptRecord, KeyboardShortcut,
│                   OverlayWindowController, LanguageSwitchWindowController,
│                   SettingsView, HistoryWindowController,
│                   FileTranscriptionWindowController, LicenseWindowController,
│                   Notification.Name extensions
│
├── Notifications.swift
│   └── imports: Foundation
│   └── depends on: (none - pure definitions)
│
└── Bundle+Extensions.swift
    └── imports: Foundation
    └── depends on: (none - extensions)

Yapper/Models/
├── AppState.swift
│   └── imports: AppKit, Foundation, SwiftUI
│   └── depends on: LLMService.Provider, LLMModel, KeyboardShortcut, ShortcutType,
│                   Notification.Name extensions
│
├── KeyboardShortcut.swift
│   └── imports: AppKit, Foundation, HotKey, Carbon.HIToolbox
│   └── depends on: (none - model definition)
│
└── TranscriptRecord.swift
    └── imports: Foundation
    └── depends on: DurationFormatter, FileSizeFormatter

Yapper/Services/
├── AudioRecorder.swift
│   └── imports: AVFoundation, Foundation, os
│   └── depends on: AppLogger
│
├── TranscriptionService.swift
│   └── imports: Foundation, os
│   └── depends on: AppLogger, TranscriptionBackend, WhisperKitBackend, FluidAudioBackend,
│                   ModelIdentifier, TranscriptionEngine
│
├── TranscriptionBackend.swift
│   └── imports: Foundation
│   └── depends on: TranscriptionEngine, ModelLoadPhase
│
├── WhisperKitBackend.swift
│   └── imports: Foundation, os, WhisperKit
│   └── depends on: AppLogger, TranscriptionEngine, ModelIdentifier
│
├── FluidAudioBackend.swift
│   └── imports: Foundation, os, FluidAudio
│   └── depends on: AppLogger, TranscriptionEngine
│
├── AccessibilityReader.swift
│   └── imports: ApplicationServices
│   └── depends on: (none - uses AXUIElement system APIs only)
│
├── AudioDeviceManager.swift
│   └── imports: CoreAudio, AVFoundation
│   └── depends on: AudioInputDevice, AppLogger
│
├── AudioInputDevice.swift
│   └── imports: Foundation, CoreAudio
│   └── depends on: (none - model definition)
│
├── LLMService.swift
│   └── imports: Foundation
│   └── depends on: APIKeyStorage
│
├── TextInjector.swift
│   └── imports: Foundation, AppKit, ApplicationServices
│   └── depends on: (none - uses system APIs only)
│
├── HotkeyManager.swift
│   └── imports: AppKit, Foundation, HotKey, Carbon.HIToolbox
│   └── depends on: KeyboardShortcut
│
├── LicenseService.swift
│   └── imports: Foundation
│   └── depends on: Notification.Name extensions
│
├── APIKeyStorage.swift
│   └── imports: Foundation
│   └── depends on: (none - standalone storage)
│
├── TranscriptHistoryManager.swift
│   └── imports: Foundation, Observation
│   └── depends on: TranscriptRecord, TranscriptHistory, DurationFormatter
│
├── AudioFileReader.swift
│   └── imports: Foundation, AVFoundation
│   └── depends on: AppLogger (likely)
│
├── SoundFeedbackService.swift
│   └── imports: AppKit
│   └── depends on: AppState (soundFeedbackEnabled)
│
└── TrialService.swift
    └── imports: Foundation, Security
    └── depends on: (none - standalone Keychain-based trial service)

Yapper/Views/
├── OverlayWindow.swift
│   └── imports: SwiftUI, AppKit
│   └── depends on: AppState, DurationFormatter
│
├── LanguageSwitchWindow.swift
│   └── imports: SwiftUI, AppKit
│   └── depends on: AppState
│
├── SettingsView.swift
│   └── imports: SwiftUI
│   └── depends on: AppState, AIEnhancementSettingsView, ShortcutRecorderView,
│                   PermissionStatusView, Notification.Name extensions, LicenseService
│
├── AIEnhancementSettingsView.swift
│   └── imports: SwiftUI
│   └── depends on: AppState, LLMService, LLMModel, APIKeyStorage,
│                   Notification.Name extensions
│
├── HistoryView.swift
│   └── imports: SwiftUI
│   └── depends on: TranscriptHistoryManager, TranscriptRecord, AppState
│
├── FileTranscriptionView.swift
│   └── imports: SwiftUI
│   └── depends on: AppState, TranscriptionService, AudioFileReader,
│                   TranscriptHistoryManager, TranscriptRecord
│
├── LicenseActivationView.swift
│   └── imports: SwiftUI
│   └── depends on: LicenseService, LicenseState
│
├── MicrophoneLevelView.swift
│   └── imports: SwiftUI
│   └── depends on: AudioDeviceManager
│
├── MarkdownTheme+Yapper.swift
│   └── imports: SwiftUI, MarkdownUI
│   └── depends on: (none - Theme extension)
│
├── PermissionStatusView.swift
│   └── imports: SwiftUI
│   └── depends on: (none - uses bindings)
│
├── ShortcutRecorderView.swift
│   └── imports: SwiftUI
│   └── depends on: KeyboardShortcut, ShortcutType
│
└── *WindowController.swift
    └── imports: AppKit, SwiftUI
    └── depends on: Corresponding views, AppState

Yapper/Utilities/
├── DesignTokens.swift
│   └── imports: SwiftUI
│   └── depends on: (none - pure design constants)
│
├── Logging.swift
│   └── imports: os
│   └── depends on: (none - pure definitions)
│
└── Formatters.swift
    └── imports: Foundation
    └── depends on: (none - pure utilities)
```

### Dependency Summary Table

| Module | Depends On (Count) | Depended By (Count) |
|--------|-------------------|---------------------|
| **AppDelegate** | 15+ modules | 1 (YapperApp) |
| **AppState** | 4 modules | 10+ views/services |
| **TranscriptionService** | 5 (AppLogger, Backends, ModelIdentifier, Engine) | 3 (AppDelegate, FileTranscriptionView) |
| **TranscriptionBackend** | 2 (Engine, ModelLoadPhase) | 3 (TranscriptionService, WhisperKitBackend, FluidAudioBackend) |
| **LLMService** | 1 (APIKeyStorage) | 3 (AppDelegate, AppState, AIEnhancementSettingsView) |
| **KeyboardShortcut** | 0 | 4 (AppState, HotkeyManager, ShortcutRecorderView) |
| **TranscriptRecord** | 2 (Formatters) | 4 (AppDelegate, HistoryManager, views) |
| **APIKeyStorage** | 0 | 2 (LLMService, AIEnhancementSettingsView) |
| **Formatters** | 0 | 4 (TranscriptRecord, HistoryManager, OverlayView) |
| **AppLogger** | 0 | 4+ services |

---

## Coupling Analysis

### High Coupling (5+ Dependents)

| Module | Dependent Count | Dependents |
|--------|----------------|------------|
| **AppState** | 12+ | All views, AppDelegate, some services |
| **AppDelegate** | N/A | Central coordinator (expected) |
| **Notification.Name** | 8+ | AppDelegate, AppState, SettingsView, services |
| **LLMService types** | 5+ | AppState, AIEnhancementSettingsView, LLMProviders |

**Assessment**: 
- `AppState` as a central observable state container is expected to have high coupling
- `Notification.Name` extensions provide loose coupling (good pattern)
- `AppDelegate` acting as a coordinator naturally depends on many modules

### Medium Coupling (3-4 Dependents)

| Module | Dependent Count | Notes |
|--------|----------------|-------|
| **KeyboardShortcut** | 4 | Model used by state, manager, and views |
| **TranscriptRecord** | 4 | Data model shared across history features |
| **TranscriptionService** | 3 | Core service, appropriately limited exposure |
| **LLMService** | 3 | Core service for AI enhancement |
| **Formatters** | 4 | Utility used by data display components |

### Low Coupling / Isolated (0-2 Dependents)

| Module | Dependent Count | Notes |
|--------|----------------|-------|
| **TextInjector** | 1 | Only AppDelegate uses it |
| **AudioRecorder** | 1 | Only AppDelegate uses it |
| **LicenseService** | 2 | AppDelegate + LicenseActivationView |
| **APIKeyStorage** | 2 | LLMService + AIEnhancementSettingsView |
| **AppLogger** | 4 | Utility, appropriate usage |

**Assessment**: Services are appropriately isolated with minimal dependencies. The pattern of AppDelegate being the sole consumer of core services (AudioRecorder, TextInjector) is good for maintainability.

### Coupling Patterns

```
┌──────────────────────────────────────────────────────────────────┐
│                     HIGH COUPLING ZONE                            │
│  ┌──────────────┐                                                │
│  │   AppState   │◄──── All Views ────────────────────────────────│
│  │  (Observable)│◄──── AppDelegate                               │
│  └──────────────┘                                                │
│         │                                                         │
│         │ reads/writes                                            │
│         ▼                                                         │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │              NotificationCenter (Loose Coupling)              ││
│  │  .shortcutsChanged, .apiKeyChanged, .modelSelectionChanged   ││
│  └──────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    ISOLATED SERVICE ZONE                          │
│                                                                   │
│  ┌────────────────┐  ┌──────────────────┐  ┌─────────────────┐   │
│  │ AudioRecorder  │  │TranscriptionSvc  │  │  TextInjector   │   │
│  └───────┬────────┘  └────────┬─────────┘  └────────┬────────┘   │
│          │                    │                      │            │
│          └────────────────────┼──────────────────────┘            │
│                               │                                   │
│                               ▼                                   │
│                        ┌──────────────┐                           │
│                        │  AppDelegate │ (sole consumer)           │
│                        └──────────────┘                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## Dependency Direction & Cycles

### Dependency Flow (Top-Down)

```
                        ┌─────────────┐
                        │  YapperApp  │
                        │   (@main)   │
                        └──────┬──────┘
                               │
                               ▼
                        ┌─────────────┐
                        │ AppDelegate │ ◄───── Central Coordinator
                        └──────┬──────┘
                               │
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │   Services  │     │   AppState  │     │    Views    │
    │             │     │ (Observable)│     │  (SwiftUI)  │
    └─────────────┘     └─────────────┘     └─────────────┘
           │                   │                   │
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │   Models    │     │  Utilities  │     │  Utilities  │
    └─────────────┘     └─────────────┘     └─────────────┘
```

### Identified Dependency Directions

| From | To | Direction | Notes |
|------|----|-----------|-------|
| Views | AppState | Down | Views read/write state (correct) |
| Views | Services | Down | Some views use services directly (FileTranscriptionView) |
| AppDelegate | Services | Down | Coordinator uses services (correct) |
| AppDelegate | Views | Down | Creates/shows windows (correct) |
| Services | Models | Down | Services use data models (correct) |
| Models | Utilities | Down | Models use formatters (correct) |
| AppState | Service Types | Across | AppState references LLMService.Provider enum |

### Cycle Analysis

**No circular dependencies detected.**

The codebase maintains a clean unidirectional dependency flow:

1. **Entry Point** (YapperApp) → **Coordinator** (AppDelegate)
2. **Coordinator** → **Services**, **State**, **Views**
3. **Views** → **State** (read/write via @Environment)
4. **Services** → **Models** (data structures)
5. **Models** → **Utilities** (formatting)

**Potential Concern - Type References**:
- `AppState` imports `LLMService.Provider` and `LLMModel` types for settings storage
- This creates a coupling from state to service types (but not service instances)
- **Mitigation**: These are just enums/value types, not the service itself

---

## Dependency Graph Visualization

### Complete Internal Dependency Graph

```
                                    ┌─────────────────┐
                                    │    YapperApp    │
                                    │    (@main)      │
                                    └────────┬────────┘
                                             │
                                             ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                               AppDelegate                                       │
│                          (Central Coordinator)                                  │
│                                                                                 │
│  Dependencies:                                                                  │
│  - AppState           - TranscriptionService    - LLMService                    │
│  - AudioRecorder      - TextInjector            - HotkeyManager                 │
│  - LicenseService     - APIKeyStorage           - TranscriptHistoryManager      │
│  - OverlayWindowController                      - SettingsView                  │
│  - LanguageSwitchWindowController               - HistoryWindowController       │
│  - FileTranscriptionWindowController            - LicenseWindowController       │
└───┬────────────────────────────────┬─────────────────────────────────┬──────────┘
    │                                │                                 │
    ▼                                ▼                                 ▼
┌──────────────┐              ┌──────────────┐              ┌──────────────────────┐
│  SERVICES    │              │   APPSTATE   │              │       VIEWS          │
├──────────────┤              ├──────────────┤              ├──────────────────────┤
│AudioRecorder │              │@Observable   │              │OverlayWindow         │
│  └─AVAudio   │              │              │              │  └─AppState          │
│              │              │Depends on:   │              │  └─Formatters        │
│Transcription │              │-LLMService   │              │                      │
│  └─WhisperKit│              │ types only   │              │LanguageSwitchWindow  │
│  └─AppLogger │              │-KeyboardShort│              │  └─AppState          │
│              │              │-ShortcutType │              │                      │
│LLMService    │              │              │              │SettingsView          │
│  └─APIKey    │              │Depended by:  │              │  └─AppState          │
│  └─Providers │              │-All Views    │              │  └─AIEnhancement     │
│              │              │-AppDelegate  │              │  └─ShortcutRecorder  │
│TextInjector  │              │              │              │  └─PermissionStatus  │
│  └─CG APIs   │              │              │              │                      │
│              │              │              │              │HistoryView           │
│HotkeyManager │              │              │              │  └─HistoryManager    │
│  └─HotKey lib│              │              │              │  └─TranscriptRecord  │
│  └─Keyboard  │              │              │              │                      │
│   Shortcut   │              │              │              │FileTranscription     │
│              │              │              │              │  └─Transcription     │
│              │              │              │              │  └─AudioFileReader   │
│LicenseService│              │              │              │                      │
│  └─Polar API │              │              │              │LicenseActivation     │
│              │              │              │              │  └─LicenseService    │
│              │              │              │              │                      │
│              │              │              │              │AIEnhancementSettings │
│HistoryMgr   │              │              │              │  └─AppState          │
│  └─Transcript│              │              │              │  └─LLMService        │
│    Record    │              │              │              │  └─APIKeyStorage     │
│  └─Formatters│              │              │              │                      │
│              │              │              │              │ShortcutRecorderView  │
│APIKeyStorage │              │              │              │  └─KeyboardShortcut  │
│  └─UserDef   │              │              │              │                      │
│              │              │              │              │WindowControllers     │
│AudioFileRead │              │              │              │  └─Views + AppState  │
│  └─AVAudio   │              │              │              │                      │
│              │              │              │              │                      │
│SoundFeedback │              │              │              │                      │
│  └─AppState  │              │              │              │                      │
└──────────────┘              └──────────────┘              └──────────────────────┘
        │                            │                              │
        └────────────────────────────┼──────────────────────────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                                 MODELS                                          │
├─────────────────────┬─────────────────────┬────────────────────────────────────┤
│  KeyboardShortcut   │  TranscriptRecord   │  ShortcutType                      │
│   └─HotKey.Key      │   └─DurationFmt     │                                    │
│   └─Carbon keys     │   └─FileSizeFmt     │  TranscriptHistory                 │
│                     │                     │   └─TranscriptRecord               │
│  LLMModel           │  LicenseInfo        │                                    │
│  LLMProvider        │  LicenseState       │  RecordingState                    │
└─────────────────────┴─────────────────────┴────────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                               UTILITIES                                         │
├────────────────────────────────────────────────────────────────────────────────┤
│  AppLogger (os.Logger)    │    DurationFormatter    │    FileSizeFormatter     │
│  Notifications.swift      │    Formatters.swift     │    Logging.swift         │
└────────────────────────────────────────────────────────────────────────────────┘
```

### External Dependencies Graph

```
┌──────────────────────────────────────────────────────────────────────┐
│                    YAPPER APPLICATION                                 │
└───────────────────────────┬──────────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┬───────────┬───────────────┐
            │               │               │           │               │
            ▼               ▼               ▼           ▼               ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────┐ ┌──────────┐ ┌───────────────┐
    │   WhisperKit  │ │    HotKey     │ │  Sparkle  │ │MarkdownUI│ │ System APIs   │
    │   (ML/Audio)  │ │  (Shortcuts)  │ │ (Updates) │ │(Markdown)│ │  (macOS)      │
    └───────┬───────┘ └───────┬───────┘ └───────────┘ └────┬─────┘ └───────┬───────┘
            │                 │                 │            │
            ▼                 ▼                 ▼            ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────┐ ┌───────────────────────────┐
    │   CoreML      │ │    Carbon     │ │ cmark-gfm │ │ AVFoundation              │
    │   Accelerate  │ │   HIToolbox   │ │ (C parser)│ │ CoreAudio (HAL)           │
    │   NeuralEng   │ │               │ └───────────┘ │ CoreGraphics              │
    └───────────────┘ └───────────────┘               │ ApplicationServices       │
                                                      │ AppKit / SwiftUI          │
                                        │ Foundation                │
                                        │ Observation               │
                                        └───────────────────────────┘

External Services (Network):
┌───────────────────────────────────────────────────────────────────────┐
│  HuggingFace    │  Polar API    │  LLM Providers (Gemini, OpenAI,    │
│  (Model DL)     │  (Licensing)  │   Anthropic, xAI)                   │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Recommendations

### Strengths

1. **Clean Service Isolation**: Core services (AudioRecorder, TranscriptionService, TextInjector) are only accessed through AppDelegate, preventing scattered dependencies.

2. **NotificationCenter for Loose Coupling**: Settings changes propagate via notifications rather than direct references, enabling decoupled communication.

3. **No Circular Dependencies**: The dependency graph flows cleanly from top to bottom without cycles.

4. **Actor Isolation**: TranscriptionService uses Swift actors for thread-safe model access.

5. **Singleton Services Where Appropriate**: Shared services (APIKeyStorage, LicenseService, TranscriptHistoryManager) use singletons appropriately.

### Areas for Improvement

1. **AppDelegate Size**: At ~1,450 lines, AppDelegate handles too many responsibilities. Consider extracting:
   - `RecordingCoordinator` - Recording flow orchestration
   - `WindowManager` - Window creation and management
   - `MenuBarController` - Menu bar setup and updates

2. **AppState Type Dependencies**: AppState imports `LLMService.Provider` and `LLMModel` types. Consider moving these enums to a shared types file to reduce coupling.

3. **View-Service Direct Dependencies**: `FileTranscriptionView` directly uses `TranscriptionService`. Consider routing through AppDelegate or a dedicated coordinator for consistency.

4. **Testing Boundary**: The lack of protocols for services makes unit testing harder. Consider protocol abstractions for:
   - `AudioRecording` protocol for `AudioRecorder`
   - `Transcribing` protocol for `TranscriptionService`
   - `TextInjecting` protocol for `TextInjector`

### Dependency Health Summary

| Metric | Status | Notes |
|--------|--------|-------|
| Circular Dependencies | None | Clean graph |
| High Fan-Out | AppDelegate | Expected for coordinator |
| High Fan-In | AppState | Expected for shared state |
| Service Isolation | Good | Most services accessed only by AppDelegate |
| Layer Separation | Good | Clear App/Model/Service/View/Utility layers |
| External Dependencies | Moderate | 5 packages (WhisperKit, FluidAudio, HotKey, Sparkle, MarkdownUI) |

---

*This document provides a comprehensive analysis of dependencies in the Yapper codebase. It should be updated as the codebase evolves.*
