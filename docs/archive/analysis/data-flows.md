# Yapper Data Flows Analysis

**Generated**: 2026-01-31
**Last Updated**: 2026-03-28
**Scope**: Complete data flow tracing from input to storage to output

---

## Table of Contents

1. [Data Models Overview](#data-models-overview)
2. [Primary Data Flows](#primary-data-flows)
   - [Voice Recording Flow](#voice-recording-flow)
   - [AI Transform Flow](#ai-transform-flow)
   - [AI Q&A Flow](#ai-qa-flow)
   - [Free Trial Flow](#free-trial-flow)
   - [Microphone Selection Flow](#microphone-selection-flow)
   - [File Transcription Flow](#file-transcription-flow)
   - [Settings/State Flow](#settingsstate-flow)
3. [State Management](#state-management)
4. [Data Persistence](#data-persistence)
5. [External Communication](#external-communication)
6. [Data Transformation Details](#data-transformation-details)
7. [Validation Rules](#validation-rules)
8. [Data Integrity Notes](#data-integrity-notes)

---

## Data Models Overview

### RecordingState
- **Type**: Enum with associated values
- **Fields**: `idle`, `recording`, `processing`, `aiTransforming`, `aiTransformResult`, `aiQA`, `aiQAResult`, `error(message: String)`
- **Location**: `Yapper/Models/AppState.swift`
- **Purpose**: State machine governing the recording/transcription pipeline

### OverlayDisplayState
- **Type**: Enum with associated values
- **Fields**: `hidden`, `recording`, `processing`, `aiRecording`, `aiTransforming`, `aiTransformResult(hasError:)`, `aiQA`, `aiQAResult(hasError:)`, `error`
- **Location**: `Yapper/Models/AppState.swift`
- **Purpose**: Drives overlay UI appearance and color coding (purple for AI states, green for success, orange for errors)

### InteractionMode
- **Type**: Enum with associated values
- **Fields**: `dictation`, `aiTransform(selectedText:)`, `aiQA(question:)`
- **Location**: `Yapper/Models/AppState.swift`
- **Purpose**: Determines post-transcription routing — AI Transform, AI Q&A, or normal dictation

### LicenseState
- **Type**: Enum with associated values
- **Fields**: `unknown`, `valid`, `invalid`, `trialActive(daysRemaining:)`, `trialExpired`
- **Location**: `Yapper/Services/LicenseService.swift`
- **Purpose**: Tracks license and trial state; `canUseApp` returns true for both `.valid` and `.trialActive`

### AppState
- **Type**: Observable class (`@Observable @MainActor`)
- **Key Fields**:
  - `recordingState: RecordingState` - Current pipeline state
  - `audioLevel: Float` - Real-time audio level (0.0-1.0)
  - `selectedModel: String` - Model in colon format (e.g. `"parakeet:tdt-0.6b-v3"`)
  - `selectedLanguage: String` - Language code for transcription
  - `customVocabulary: [String]` - Custom words for recognition
  - `selectedLLMProvider: LLMService.Provider` - Active LLM provider
  - `selectedLLMModel: LLMModel` - Active LLM model
  - `aiResponseText: String` - Shared streaming text for AI Transform and Q&A responses
  - `aiResponseError: String?` - Shared error state for AI streaming
  - `isAIResponseStreaming: Bool` - Whether an AI response is currently streaming
  - `primaryLanguage: String` - Primary transcription language code
  - `secondaryLanguage: String?` - Optional secondary language code
  - `isUsingSecondaryLanguage: Bool` - Toggle state (resets on launch)
  - `activeLanguage: String` - Computed: returns current language code
  - `languageToggleShortcut: KeyboardShortcut` - Language toggle shortcut
  - `autoTypeEnabled: Bool` - Auto-type text injection toggle (default: true)
  - `autoTypeToggleShortcut: KeyboardShortcut` - Auto-type toggle shortcut
  - `soundFeedbackEnabled: Bool` - Audio feedback toggle
  - `overlayPositionFixed: Bool` - Fixed vs cursor-following overlay
  - `selectedMicrophoneUID: String?` - Persisted microphone selection (nil = system default)
  - `availableInputDevices: [AudioInputDevice]` - Enumerated audio input devices
  - `audioDeviceManager: AudioDeviceManager` - CoreAudio device enumeration and hot-plug
  - `microphoneFellBack: Bool` - Whether a fallback to system default occurred
  - `isInTrial: Bool` - Whether the app is in free trial mode
  - `trialDaysRemaining: Int?` - Days remaining in trial
- **Location**: `Yapper/Models/AppState.swift`
- **Persisted**: Yes (UserDefaults, except `isUsingSecondaryLanguage` which resets on launch)

### TranscriptRecord
- **Type**: Codable struct
- **Fields**:
  - `id: UUID` - Unique identifier
  - `text: String` - Transcribed/enhanced text
  - `timestamp: Date` - When recorded
  - `duration: TimeInterval` - Recording duration in seconds
  - `language: String` - Language code used
  - `sourceType: TranscriptSourceType` - `.live` or `.file`
  - `sourceFileName: String?` - For file transcriptions
  - `sourceFilePath: String?` - Original file path
  - `sourceFileSize: Int64?` - File size in bytes
- **Location**: `Yapper/Models/TranscriptRecord.swift`
- **Persisted**: Yes (JSON file)

### KeyboardShortcut
- **Type**: Codable struct
- **Fields**:
  - `keyCode: UInt32` - Carbon key code
  - `modifiers: ShortcutModifiers` - OptionSet of modifiers
- **Location**: `Yapper/Models/KeyboardShortcut.swift`
- **Persisted**: Yes (UserDefaults as JSON Data)

### LicenseInfo
- **Type**: Codable struct
- **Fields**:
  - `licenseKey: String` - The license key
  - `activationId: String` - Device activation ID
  - `expiresAt: Date?` - Expiration date
  - `status: String` - License status
  - `validatedAt: Date` - Last validation timestamp
  - `customerEmail: String?` - Customer email
- **Location**: `Yapper/Services/LicenseService.swift`
- **Persisted**: Yes (UserDefaults)

### LLMModel
- **Type**: Enum (String, CaseIterable, Codable)
- **Values**: Gemini, OpenAI, Anthropic, xAI models
- **Location**: `Yapper/Services/LLMService.swift`
- **Persisted**: Yes (UserDefaults as rawValue)

---

## Primary Data Flows

### Voice Recording Flow (Normal Dictation)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    VOICE RECORDING FLOW (NORMAL DICTATION)                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  Microphone   │────▶│ AVAudioEngine │────▶│ Audio Buffer  │────▶│  PCM Data     │
│   (Input)     │     │  (Capture)    │     │  (Resample)   │     │ (16kHz/mono)  │
└───────────────┘     └───────────────┘     └───────────────┘     └───────┬───────┘
                                                                          │
                                                                          ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ Text Output   │◀────│ Text Injector │◀────│  Final Text   │◀────│ Transcription │
│(Target App)   │     │  (CGEvent)    │     │               │     │   Backend     │
└───────────────┘     └───────────────┘     └───────┬───────┘     └───────────────┘
                                                    │
                                                    ▼
                                            ┌───────────────┐
                                            │   History     │
                                            │ (JSON File)   │
                                            └───────────────┘
```

#### Post-Transcription Routing

After transcription completes, the text is routed based on `InteractionMode`:

1. **AI Transform** (if text was selected before recording) — see [AI Transform Flow](#ai-transform-flow)
2. **AI Q&A** (if "Hey Yapper" wake phrase detected) — see [AI Q&A Flow](#ai-qa-flow)
3. **Normal Dictation** (default) — inject text into target app

#### Detailed Step-by-Step (Normal Dictation)

| Step | Component | Input | Transformation | Output |
|------|-----------|-------|----------------|--------|
| 1 | HotkeyManager | Option+Space | Keyboard event detection | Callback trigger |
| 2 | AppDelegate | Callback | Permission/state checks, AXUIElement text selection read | Start signal + InteractionMode |
| 3 | AppState | Start signal | `recordingState = .recording` | State update |
| 4 | AudioRecorder | Mic stream (selected device or system default) | AVAudioEngine capture | Native format PCM |
| 5 | AudioRecorder | Native PCM | Resample to 16kHz mono Float32 | [Float] array |
| 6 | AudioRecorder | [Float] array | Calculate RMS audio level | audioLevel callback |
| 7 | AppState | audioLevel | Update observable property | UI visualization |
| 8 | User | Recording | Key release/toggle | Stop signal |
| 9 | AudioRecorder | Stop signal | Accumulate buffer to Data | Raw PCM Data |
| 10 | TranscriptionService | PCM Data | Backend inference (WhisperKit or FluidAudio) | Raw text (batch) or token stream |
| 10a | TextInjector | Token stream | `typeStringAtomically()` (streaming path, if auto-type enabled) | Typed characters in real-time |
| 11 | TextInjector | Final text | CGEvent keyboard simulation (batch path, if auto-type enabled) | Typed characters |
| 12 | TranscriptHistoryManager | Record data | JSON encoding | Persisted file (regardless of auto-type) |

---

### AI Transform Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AI TRANSFORM FLOW                                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ Text Selected │────▶│ AXUIElement   │────▶│   Recording   │────▶│ Transcription │
│ in Target App │     │ (Read Select) │     │ (Voice Instr) │     │   Backend     │
└───────────────┘     └───────────────┘     └───────────────┘     └───────┬───────┘
                                                                          │
                                                                          ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ Text Output   │◀────│ TextInjector  │◀────│ Delete Select │◀────│ LLM Transform │
│(Target App)   │     │ (Inject Result│     │ (keyCode 0x33)│     │   Stream      │
└───────────────┘     │  after card   │     └───────────────┘     └───────┬───────┘
                      │  dismissed)   │                                   │
                      └───────────────┘                                   ▼
                                                                  ┌───────────────┐
                                                                  │ Overlay Card  │
                                                                  │ (Stream View) │
                                                                  │ Markdown + Copy│
                                                                  └───────────────┘
```

#### Detailed Step-by-Step

| Step | Component | Input | Transformation | Output |
|------|-----------|-------|----------------|--------|
| 1 | User | Selects text in any app | Text highlight | Selected text in target app |
| 2 | HotkeyManager | Option+Space | Keyboard event detection | Callback trigger |
| 3 | AccessibilityReader | AXUIElement query | Read selected text (200ms timeout); detect secure fields | `selectedText: String` (max 10,000 chars) or fallback to dictation |
| 4 | AppDelegate | Selected text present | Set `InteractionMode.aiTransform(selectedText:)` | Mode decision |
| 5 | AppState | Mode decision | `recordingState = .recording`, overlay shows purple `.aiRecording` | State update |
| 6 | AudioRecorder | Mic stream | Capture voice instruction | PCM Data |
| 7 | TranscriptionService | PCM Data | Backend inference | Voice instruction text |
| 8 | LLMService | `transformStream(instruction, selectedText)` | SSE stream to LLM provider | Token stream |
| 9 | AppState | Tokens | `appendAIResponseToken(_:)`, `recordingState = .aiTransforming` | `aiResponseText` accumulates, overlay card streams Markdown |
| 10 | AppState | Stream complete | `completeAIResponseStream(recordingState: .aiTransformResult)` | Overlay shows green result card |
| 11 | User | Dismisses card (or Escape to cancel) | Card dismissed | Trigger replacement or cancel |
| 12 | TextInjector | Dismiss trigger | `deleteSelection()` (simulates Delete key) then inject transformed text | Replaced text in target app |

#### Error Handling

- Secure text fields (passwords) detected by AXUIElement — falls back to normal dictation
- Selection exceeding 10,000 characters — falls back to normal dictation
- LLM stream failure — `failAIResponseStream(_:resultState:errorPrefix:)` shows error in orange card
- Escape key cancels streaming or dismisses result card without replacing text

---

### AI Q&A Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            AI Q&A FLOW                                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   Recording   │────▶│ Transcription │────▶│ "Hey Yapper"  │────▶│ Extract       │
│ (Voice Input) │     │   Backend     │     │  Detection    │     │  Question     │
└───────────────┘     └───────────────┘     └───────────────┘     └───────┬───────┘
                                                                          │
                                                                          ▼
                                                                  ┌───────────────┐
                                                                  │ LLM Q&A       │
                                                                  │ Stream        │
                                                                  └───────┬───────┘
                                                                          │
                                                                          ▼
                                                                  ┌───────────────┐
                                                                  │ Overlay Card  │
                                                                  │ (Q&A View)   │
                                                                  │ Question + Ans│
                                                                  │ Markdown + Copy│
                                                                  └───────────────┘
```

#### Detailed Step-by-Step

| Step | Component | Input | Transformation | Output |
|------|-----------|-------|----------------|--------|
| 1 | HotkeyManager | Option+Space | Keyboard event detection | Callback trigger |
| 2 | AppDelegate | Callback | Permission/state checks, no text selected | Start recording (dictation mode initially) |
| 3 | AudioRecorder | Mic stream | Capture voice | PCM Data |
| 4 | TranscriptionService | PCM Data | Backend inference | Transcribed text |
| 5 | `detectHeyYapper(in:)` | Transcribed text | Match against 35+ regex patterns (canonical, vowel swaps, consonant swaps, merged tokens, etc.) | Wake phrase detected + extracted question |
| 6 | AppDelegate | Question extracted | Set `InteractionMode.aiQA(question:)` | Mode decision |
| 7 | LLMService | `qaStream(question:)` | SSE stream to LLM provider (system prompt: "You are a helpful voice assistant called Yapper...") | Token stream |
| 8 | AppState | Tokens | `startAIResponseStreaming(recordingState: .aiQA)`, purple "Thinking..." pill | `aiResponseText` accumulates |
| 9 | AppState | Tokens | `appendAIResponseToken(_:)` | Overlay expands to card with streaming Markdown answer |
| 10 | AppState | Stream complete | `completeAIResponseStream(recordingState: .aiQAResult)` | Green "Answer Ready" card with question header and answer body |
| 11 | User | Copy button or Escape | Copy raw Markdown text / dismiss card | Text on clipboard / card dismissed |

#### Wake Phrase Detection Categories

| Category | Examples |
|----------|----------|
| Canonical | `hey yapper` |
| Vowel/consonant swaps | yaper, yappar, yappor, yappur, yepper, yipper, yopper, yupper |
| Missing leading Y | apper, upper |
| Y-to-other consonant | rapper, japper, napper, dapper, tapper, zapper, jabber, yabber |
| Plural/suffix drift | yappers, "yap per", "yap her", "yap" |
| "Hey" variants | hay, hei, "hey a yapper", "a yapper" |
| Merged tokens | heyyapper |

#### Shared Streaming Infrastructure (Transform + Q&A)

Both AI modes share the same AppState streaming methods:

- `startAIResponseStreaming(recordingState:)` — initializes streaming state
- `appendAIResponseToken(_:)` — appends token to `aiResponseText`
- `completeAIResponseStream(recordingState:)` — finalizes stream, updates overlay
- `failAIResponseStream(_:resultState:errorPrefix:)` — handles errors with orange card
- `dismissAIResponse()` — clears all AI response state

---

### Free Trial Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          FREE TRIAL FLOW                                     │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  App Launch   │────▶│ Polar License │────▶│ TrialService  │────▶│ Keychain      │
│               │     │ Check (fails) │     │ .checkOrStart │     │ Read/Write    │
└───────────────┘     └───────────────┘     │  Trial()      │     └───────┬───────┘
                                            └───────────────┘             │
                                                                          ▼
                                                                  ┌───────────────┐
                                                                  │ HMAC-SHA256   │
                                                                  │ Verify        │
                                                                  └───────┬───────┘
                                                                          │
                                            ┌─────────────────────────────┼──────────┐
                                            │                             │          │
                                            ▼                             ▼          ▼
                                    ┌───────────────┐         ┌──────────────┐  ┌─────────┐
                                    │ .trialActive  │         │.trialExpired │  │ .valid  │
                                    │(daysRemaining)│         │  Show modal  │  │ (skip)  │
                                    │ Show toast    │         └──────────────┘  └─────────┘
                                    └───────────────┘
```

#### TrialService Decision Table

| Condition | Result |
|-----------|--------|
| No payload + no tombstone | First launch — `.active(7)`, create Keychain payload |
| No payload + tombstone exists | Deletion attack — `.expired` |
| Payload present, bad HMAC | Tampered — `.expired` |
| `now < lastSeenAt` | Clock rollback — `.expired` |
| Elapsed >= 7 days | Natural expiry — `.expired` |
| Elapsed < 7 days | `.active(remaining)`, update `lastSeenAt` |
| Keychain unavailable (first launch) | Grant trial, retry on next launch |

#### Keychain Storage

| Item | Service | Account | Purpose |
|------|---------|---------|---------|
| Trial payload | `app.persistence.layer` | `session.token.v1` | JSON-encoded `TrialPayload` (startedAt, lastSeenAt, HMAC signature) |
| Tombstone | `app.persistence.layer` | `install.marker.v1` | Empty item; survives payload deletion to prevent fresh-start bypass |

#### Security

- HMAC-SHA256 signing over `"yapper.trial.v1:{startedAt}:{bundleId}"` with 32-byte embedded key
- Keychain accessibility: `kSecAttrAccessibleAfterFirstUnlock`
- Clock rollback detection via `lastSeenAt` comparison

---

### Microphone Selection Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MICROPHONE SELECTION FLOW                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ CoreAudio HAL │────▶│ AudioDevice   │────▶│ Settings UI   │────▶│ User Selects  │
│ Enumeration   │     │ Manager       │     │ Dropdown      │     │ Device        │
└───────────────┘     └───────────────┘     └───────────────┘     └───────┬───────┘
                            │                                             │
                            │ Property listeners                          ▼
                            │ (hot-plug)                          ┌───────────────┐
                            │                                     │ UserDefaults   │
                            ▼                                     │ selectedMic    │
                      ┌───────────────┐                           │ rophoneUID     │
                      │ Device added/ │                           └───────┬───────┘
                      │ removed event │                                   │
                      └───────┬───────┘                                   ▼
                              │                                   ┌───────────────┐
                              ▼                                   │ AudioUnit     │
                      ┌───────────────┐                           │ Config        │
                      │ Auto-fallback │                           │ (set device)  │
                      │ to system     │                           └───────────────┘
                      │ default       │
                      └───────────────┘
```

#### Detailed Step-by-Step

| Step | Component | Input | Transformation | Output |
|------|-----------|-------|----------------|--------|
| 1 | AudioDeviceManager | App launch / hot-plug event | CoreAudio HAL device enumeration | `[AudioInputDevice]` with stable `uid` + volatile `audioDeviceID` |
| 2 | SettingsView | Device list | Render dropdown picker + "System Default" option | User selection |
| 3 | AppState | User selection | Persist `selectedMicrophoneUID` to UserDefaults | Stored UID |
| 4 | AudioRecorder | `startRecording(deviceID:callback:)` | `setInputDevice(_:)` — uninitialize AudioUnit, set device via CoreAudio HAL, reinitialize | Configured AudioUnit |
| 5 | MicrophoneLevelView | Selected device | Temporary AVAudioEngine instance for level metering | Live 4px bar (green/yellow/red at 0.5/0.8 thresholds) |
| 6 | AudioDeviceManager | Device removed | Property listener callback | Auto-fallback to system default, `microphoneFellBack = true`, warning banner in Settings |

#### AudioInputDevice Model

- `audioDeviceID: UInt32` — volatile CoreAudio runtime ID (changes on replug)
- `uid: String` — stable persistent identifier for UserDefaults storage
- Conforms to: `Identifiable`, `Hashable`, `Sendable`

---

### File Transcription Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FILE TRANSCRIPTION FLOW                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  Audio File   │────▶│AudioFileReader│────▶│  PCM Data     │────▶│ WhisperKit    │
│ (MP3/WAV/M4A) │     │ (AVAudioFile) │     │ (16kHz/mono)  │     │ (Transcribe)  │
└───────────────┘     └───────────────┘     └───────────────┘     └───────┬───────┘
                                                                          │
                                                                          ▼
                                                                  ┌───────────────┐
                                                                  │  Transcript   │
                                                                  │  History      │
                                                                  └───────────────┘
```

#### Detailed Step-by-Step

| Step | Component | Input | Transformation | Output |
|------|-----------|-------|----------------|--------|
| 1 | FileTranscriptionView | User drops file | URL validation | File URL |
| 2 | AudioFileReader | File URL | getFileInfo() - read metadata | AudioFileInfo |
| 3 | AudioFileReader | File URL | loadAudio() - AVAudioFile read | Source PCM buffer |
| 4 | AudioFileReader | Source buffer | AVAudioConverter resample | 16kHz mono Float32 |
| 5 | AudioFileReader | Float array | withUnsafeBufferPointer | Data |
| 6 | TranscriptionService | PCM Data | WhisperKit inference | Transcript text |
| 7 | TranscriptRecord | All metadata | Create record (sourceType: .file) | Record struct |
| 8 | TranscriptHistoryManager | Record | JSON encode + write | Persisted file |

---

### Settings/State Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SETTINGS/STATE FLOW                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  SettingsView │────▶│   AppState    │────▶│ UserDefaults  │────▶│   Persisted   │
│   (SwiftUI)   │     │ (@Observable) │     │   .set()      │     │   Storage     │
└───────────────┘     └───────────────┘     └───────────────┘     └───────────────┘
        │                     │
        │                     │ NotificationCenter
        │                     ▼
        │             ┌───────────────┐
        │             │  AppDelegate  │
        │             │  (Observers)  │
        │             └───────┬───────┘
        │                     │
        │                     ▼
        │             ┌───────────────┐
        │             │   Services    │
        │             │ (Reconfigure) │
        │             └───────────────┘
        │
        └─────────────────────────────────────▶ Views auto-update via @Observable
```

#### Notification-Driven Updates

| Setting Change | Notification | Handler | Effect |
|----------------|--------------|---------|--------|
| Keyboard shortcut | `.shortcutsChanged` | `handleShortcutsChanged()` | Re-register hotkeys (recording, cancel, language toggle) |
| API key | `.apiKeyChanged` | `handleAPIKeyChanged()` | Reconfigure LLMService |
| LLM provider/model | `.llmProviderChanged` | `handleLLMProviderChanged()` | Switch active provider |
| Speech model | `.modelSelectionChanged` | `handleModelSelectionChanged()` | Reload TranscriptionService with new backend |
| Model download cancel | `.modelDownloadCancelled` | Cancel `modelLoadingTask` | Cancel in-progress download, clean up partial files |
| Models cleared | `.modelsCleared` | Re-download selected model | Clear all model files and re-download current |
| Permissions | `.permissionsNeedRefresh` | `handlePermissionsRefresh()` | Re-check permissions |
| License | `.licenseStateChanged` | `handleLicenseStateChanged()` | Update AppState license info |

---

## State Management

### AppState as Central Hub

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AppState                                        │
│                         (@Observable @MainActor)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │ Recording State │    │ Transcription   │    │ AI Response     │          │
│  │                 │    │   Settings      │    │   (Shared)      │          │
│  │ recordingState  │    │ selectedModel   │    │ aiResponseText  │          │
│  │ audioLevel      │    │ selectedLanguage│    │ aiResponseError │          │
│  │ showOverlay     │    │ customVocabulary│    │ isAIResponse    │          │
│  │ isModelLoaded   │    │                 │    │   Streaming     │          │
│  │ interactionMode │    │                 │    │ selectedProvider│          │
│  └─────────────────┘    └─────────────────┘    │ selectedModel   │          │
│                                                 └─────────────────┘          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │   Permissions   │    │    Shortcuts    │    │ License + Trial │          │
│  │                 │    │                 │    │                 │          │
│  │ hasMicPermission│    │ recordingToggle │    │ isLicenseValid  │          │
│  │ hasAccessibility│    │ cancelRecording │    │ expiresAt       │          │
│  │                 │    │ languageToggle  │    │ isInTrial       │          │
│  │                 │    │ autoTypeToggle  │    │ trialDaysRemain │          │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘          │
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │   Language      │    │  Text Output    │    │  Microphone     │          │
│  │                 │    │                 │    │                 │          │
│  │ primaryLanguage │    │ autoTypeEnabled │    │ selectedMicUID  │          │
│  │ secondaryLang   │    └─────────────────┘    │ availableDevices│          │
│  │ activeLanguage  │                           │ microphoneFell  │          │
│  └─────────────────┘                           │   Back          │          │
│                                                 └─────────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
          │                         │                         │
          ▼                         ▼                         ▼
    ┌───────────┐           ┌───────────────┐         ┌───────────────┐
    │   Views   │           │ UserDefaults  │         │NotificationCtr│
    │ (SwiftUI) │           │ (Persistence) │         │   (Events)    │
    └───────────┘           └───────────────┘         └───────────────┘
```

### State Transitions

```swift
// RecordingState transitions

idle ──────────────▶ recording       // startRecording()
      ◀────────────
         cancel                      // cancelRecording()

recording ─────────▶ processing      // stopRecording()

processing ────────▶ idle            // completeTranscription() (normal dictation)
           ────────▶ aiTransforming  // AI Transform mode (text was selected)
           ────────▶ aiQA            // AI Q&A mode ("Hey Yapper" detected)

aiTransforming ────▶ aiTransformResult  // completeAIResponseStream()
aiQA ──────────────▶ aiQAResult         // completeAIResponseStream()

aiTransformResult ─▶ idle           // dismissAIResponse() (injects text)
aiQAResult ────────▶ idle           // dismissAIResponse()

any ───────────────▶ error          // setError(message)
error ─────────────▶ idle           // Auto-dismiss after 3 seconds
```

---

## Data Persistence

### UserDefaults Keys

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `selectedModel` | String | `"parakeet:tdt-0.6b-v3"` | Model in colon format (e.g. `"whisper:large-v3-turbo"`) |
| `selectedLanguage` | String | `"en"` | Language code |
| `customVocabulary` | [String] | `[]` | Custom recognition words |
| `primaryLanguage` | String | `"en"` | Primary transcription language |
| `secondaryLanguage` | String? | nil | Optional secondary language |
| `shortcut_recordingToggle` | Data (JSON) | Option+Space | Recording shortcut |
| `shortcut_cancelRecording` | Data (JSON) | Escape | Cancel shortcut |
| `shortcut_languageToggle` | Data (JSON) | Shift+Option+L | Language toggle shortcut |
| `shortcut_autoTypeToggle` | Data (JSON) | Shift+Option+T | Auto-type toggle shortcut |
| `autoTypeEnabled` | Bool | `true` | Auto-type text injection toggle |
| `historyRetentionDays` | Int | `90` | Days to keep transcripts |
| `selectedLLMProvider` | String | `"gemini"` | Active LLM provider |
| `selectedLLMModel` | String | `"gemini-3-flash-preview"` | Active LLM model |
| `soundFeedbackEnabled` | Bool | `false` | Audio feedback toggle |
| `overlayPositionFixed` | Bool | `false` | Fixed overlay position |
| `com.yapper.apikey.gemini` | String | nil | Gemini API key |
| `com.yapper.apikey.openai` | String | nil | OpenAI API key |
| `com.yapper.apikey.anthropic` | String | nil | Anthropic API key |
| `com.yapper.apikey.xai` | String | nil | xAI API key |
| `com.yapper.license.key` | String | nil | License key |
| `com.yapper.license.activationId` | String | nil | Device activation ID |
| `com.yapper.license.expiresAt` | Double | nil | Expiration timestamp |
| `com.yapper.license.status` | String | nil | License status |
| `com.yapper.license.validatedAt` | Double | nil | Last validation timestamp |
| `com.yapper.license.customerEmail` | String | nil | Customer email |
| `selectedMicrophoneUID` | String? | nil | Persisted microphone selection (nil = system default) |
| `com.yapper.trial.welcomed` | Bool | `false` | Whether trial welcome toast was shown |

#### Removed UserDefaults Keys (v2.0.0)

| Key | Status | Reason |
|-----|--------|--------|
| `isAIEnhancementEnabled` | Orphaned (not read) | Auto-enhancement feature removed |
| `aiEnhancementPrompt` | Orphaned (not read) | Custom prompt editor removed |

### Keychain Storage

| Item | Service | Account | Format | Purpose |
|------|---------|---------|--------|---------|
| Trial payload | `app.persistence.layer` | `session.token.v1` | JSON (`TrialPayload`: startedAt, lastSeenAt, signature) | 7-day free trial state |
| Trial tombstone | `app.persistence.layer` | `install.marker.v1` | Empty data | Prevents fresh-start bypass after payload deletion |

### File-Based Storage

| Data | Location | Format |
|------|----------|--------|
| Transcript History | `~/Library/Application Support/Yapper/transcript_history.json` | JSON (ISO8601 dates) |
| Whisper Models | `~/Library/Application Support/Yapper/models/` | CoreML model bundles (HuggingFace Hub cache) |
| Parakeet Models | `~/Library/Application Support/Yapper/parakeet-models/` | FluidAudio model files |
| WhisperKit Tokenizer | `~/Library/Application Support/huggingface/` | Tokenizer files (redirected from ~/Documents) |

#### Transcript History JSON Structure

```json
{
  "records": [
    {
      "id": "550E8400-E29B-41D4-A716-446655440000",
      "text": "Hello, world!",
      "timestamp": "2026-01-13T10:30:00Z",
      "duration": 2.5,
      "language": "en",
      "sourceType": "live",
      "sourceFileName": null,
      "sourceFilePath": null,
      "sourceFileSize": null
    }
  ],
  "lastCleanup": "2026-01-13T00:00:00Z"
}
```

---

## External Communication

### LLM API Calls

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LLM API COMMUNICATION                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐                                         ┌───────────────────┐
│  LLMService   │──────── POST /v1/... ─────────────────▶│   LLM Provider    │
│               │         (SSE streaming)                 │                   │
│ Methods:      │         Headers:                        │ Gemini:           │
│ transformStr- │         Content-Type: application/json  │   generativelang. │
│   eam()       │         Authorization: Bearer <key>     │   googleapis.com  │
│ qaStream()    │         (or x-api-key for Anthropic)   │                   │
│               │                                         │ OpenAI:           │
│ All 4 provid- │◀──────── SSE token stream ─────────────│   api.openai.com  │
│ ers implement │                                         │                   │
│ enhanceStream │                                         │ Anthropic:        │
│ () protocol   │                                         │   api.anthropic.  │
└───────────────┘                                         │   com             │
                                                          │                   │
                                                          │ xAI:              │
                                                          │   api.x.ai        │
                                                          └───────────────────┘
```

#### LLM Methods

| Method | Purpose | System Prompt |
|--------|---------|---------------|
| `transformStream(instruction, selectedText)` | AI Transform — rewrite selected text per voice instruction | Hardcoded: return only transformed result, no commentary |
| `qaStream(question:)` | AI Q&A — answer a voice question | "You are a helpful voice assistant called Yapper..." |

All providers implement `LLMProvider.enhanceStream()` for native SSE streaming. Provider resolution is handled by the shared `resolveProvider()` internal method.

#### Request/Response Formats

| Provider | Endpoint | Request Format | Response Path (streaming) |
|----------|----------|----------------|---------------------------|
| Gemini | `/v1beta/models/{model}:streamGenerateContent?key=` | `{ contents: [{ parts: [{ text }] }] }` | SSE token stream |
| OpenAI | `/v1/chat/completions` | `{ model, messages, stream: true }` | SSE `data:` lines |
| Anthropic | `/v1/messages` | `{ model, messages, stream: true }` | SSE `data:` lines |
| xAI | `/v1/chat/completions` | Same as OpenAI | Same as OpenAI |

### License Server (Polar)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LICENSE API COMMUNICATION                            │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────┐                                         ┌───────────────────┐
│LicenseService │                                         │   Polar API       │
│               │                                         │                   │
│ Activate:     │──────── POST /activate ───────────────▶│ sandbox-api.polar │
│   key         │         { key, organization_id, label } │   .sh (DEBUG)     │
│   org_id      │◀──────── { id, license_key: {...} } ───│                   │
│   label       │                                         │ api.polar.sh      │
│               │                                         │   (RELEASE)       │
│ Validate:     │──────── POST /validate ───────────────▶│                   │
│   key         │         { key, org_id, activation_id }  │                   │
│   activation  │◀──────── { status, expires_at, ... } ──│                   │
│               │                                         │                   │
│ Deactivate:   │──────── POST /deactivate ─────────────▶│                   │
│   key         │         { key, org_id, activation_id }  │                   │
│   activation  │                                         │                   │
└───────────────┘                                         └───────────────────┘
```

#### License + Trial Flow

1. On launch, attempt Polar license validation
2. If Polar check fails, fall back to `TrialService.shared.checkOrStartTrial()`
3. Trial `.active` — set LicenseState, call `touchLastSeen()`, proceed with normal app setup
4. Trial `.expired` — set state, show license activation modal
5. Mid-trial license purchase — trial badge disappears, transitions to fully licensed state

#### Purchase URL

Purchase link points to `https://yapper.to/` (previously used Polar storefront with conditional sandbox/production branching).

### Model Downloads

```
┌───────────────┐                                         ┌───────────────────┐
│Transcription  │                                         │   HuggingFace     │
│  Service      │                                         │                   │
│               │──────── GET model files ──────────────▶│ huggingface.co/   │
│ WhisperKit    │         (Whisper models via WhisperKit)  │ argmaxinc/        │
│ Backend       │                                         │ whisperkit-coreml │
│               │◀──────── CoreML model bundle ──────────│                   │
│               │         Progress: 0% → 80%              │                   │
│               │         Load & prewarm: 80% → 100%      │                   │
└───────────────┘                                         └───────────────────┘

┌───────────────┐                                         ┌───────────────────┐
│ FluidAudio    │                                         │   FluidAudio CDN  │
│ Backend       │──────── GET model files ──────────────▶│                   │
│               │         (Parakeet models via FluidAudio) │                   │
│               │◀──────── Model files ─────────────────│                   │
│               │         Progress: indeterminate bar      │                   │
└───────────────┘                                         └───────────────────┘
```

**Cancellable Downloads**: Users can cancel in-progress model downloads via the Settings UI. On cancellation:
1. The `modelLoadingTask` is cancelled
2. `ModelStorageManager.removeModelFiles()` cleans up partial downloads
3. AppState shows "No model loaded" with a re-download button

---

## Data Transformation Details

### Audio Processing Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     AUDIO DATA TRANSFORMATIONS                               │
└─────────────────────────────────────────────────────────────────────────────┘

1. MICROPHONE INPUT
   Format: Device native (typically 44.1kHz or 48kHz, stereo, Float32)

2. RESAMPLE + DOWNMIX
   ┌────────────────────────────────────────────────────────────────────────┐
   │ AVAudioConverter(from: nativeFormat, to: targetFormat)                 │
   │                                                                        │
   │ nativeFormat: 44100Hz/48000Hz, stereo, Float32                        │
   │ targetFormat: 16000Hz, mono, Float32                                   │
   └────────────────────────────────────────────────────────────────────────┘

3. AUDIO LEVEL CALCULATION
   ┌────────────────────────────────────────────────────────────────────────┐
   │ RMS = sqrt(sum(sample^2) / frameCount)                                 │
   │ level = min(RMS * 10.0, 1.0)  // Amplified for visualization          │
   └────────────────────────────────────────────────────────────────────────┘

4. BUFFER ACCUMULATION
   ┌────────────────────────────────────────────────────────────────────────┐
   │ audioBuffer: [Float] = []                                              │
   │ audioBuffer.append(contentsOf: convertedSamples)                       │
   └────────────────────────────────────────────────────────────────────────┘

5. DATA CONVERSION
   ┌────────────────────────────────────────────────────────────────────────┐
   │ let data = audioBuffer.withUnsafeBufferPointer { Data(buffer: $0) }   │
   │ // [Float] → Data (raw bytes, 4 bytes per sample)                     │
   └────────────────────────────────────────────────────────────────────────┘

6. WHISPERKIT INPUT
   ┌────────────────────────────────────────────────────────────────────────┐
   │ let samples: [Float] = audioData.withUnsafeBytes { rawBuffer in       │
   │     let floatBuffer = rawBuffer.bindMemory(to: Float.self)            │
   │     return Array(floatBuffer)                                          │
   │ }                                                                       │
   │ // Data → [Float] (reverse of step 5)                                  │
   └────────────────────────────────────────────────────────────────────────┘
```

### Text Processing Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     TEXT PROCESSING PIPELINE                                  │
└─────────────────────────────────────────────────────────────────────────────┘

1. RAW TRANSCRIPTION
   Input:  "  hello world  \n"
   Output: "hello world"
   ┌────────────────────────────────────────────────────────────────────────┐
   │ transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)        │
   └────────────────────────────────────────────────────────────────────────┘

2. POST-TRANSCRIPTION ROUTING
   ┌────────────────────────────────────────────────────────────────────────┐
   │ Priority order:                                                        │
   │  a) AI Transform — if text was selected before recording              │
   │  b) AI Q&A — if "Hey Yapper" wake phrase detected in transcription    │
   │  c) Normal Dictation — default path, inject text into target app      │
   └────────────────────────────────────────────────────────────────────────┘

3. TEXT INJECTION (Normal Dictation)
   For each character:
   ┌────────────────────────────────────────────────────────────────────────┐
   │ let string = String(character)                                         │
   │ var unicodeChars = Array(string.utf16)                                 │
   │ keyDown.keyboardSetUnicodeString(stringLength:unicodeString:)          │
   │ keyDown.post(tap: .cghidEventTap)                                      │
   │ keyUp.post(tap: .cghidEventTap)                                        │
   │ Task.sleep(for: .milliseconds(10))                                     │
   └────────────────────────────────────────────────────────────────────────┘

4. AI RESPONSE STREAMING (Transform / Q&A)
   ┌────────────────────────────────────────────────────────────────────────┐
   │ SSE stream from LLM provider → token-by-token append to              │
   │ aiResponseText → Markdown rendering in overlay card                    │
   │ On completion: Transform replaces selected text; Q&A shows in card    │
   └────────────────────────────────────────────────────────────────────────┘
```

> **Note (v2.0.0):** The automatic AI enhancement pipeline (transcription -> LLM enhance -> inject)
> has been removed. AI is now strictly user-initiated via Transform (select text + speak instruction)
> and Q&A (say "Hey Yapper" + question). The `LLMService.enhance(text:)`, `setPrompt()`,
> `getPrompt()`, and `defaultPrompt` methods have been removed along with the
> `RecordingState.enhancing` and `OverlayDisplayState.enhancing` enum cases.

---

## Validation Rules

### AppState Validation

| Field | Constraints |
|-------|-------------|
| `selectedModel` | Colon format `"engine:variant"` (e.g. `"parakeet:tdt-0.6b-v3"`, `"whisper:large-v3-turbo"`). Legacy names auto-migrate to `"whisper:*"` |
| `selectedLanguage` | 2-letter ISO language code (migrates "auto" to "en") |
| `customVocabulary` | Non-empty strings, trimmed, no duplicates |
| `historyRetentionDays` | > 0, defaults to 90 |
| `audioLevel` | 0.0 to 1.0, clamped |

### KeyboardShortcut Validation

```swift
var isValid: Bool {
    // Special keys (Escape, F1-F12) can work without modifiers
    let specialKeys: Set<Int> = [kVK_Escape, kVK_F1, ...]
    if specialKeys.contains(Int(keyCode)) { return true }

    // Regular keys need at least one modifier
    return !modifiers.isEmpty
}
```

### API Key Validation

```swift
func validateAPIKey(_ apiKey: String, for provider: Provider) async -> APIKeyValidationResult {
    // Makes a test API call: enhance(text: "test", prompt: "Reply with 'ok'")
    // Returns: .valid, .invalid, or .networkError(message)
}
```

### License Validation

| Check | Location | Behavior |
|-------|----------|----------|
| Key format | Polar API | Returns 404 if invalid |
| Activation limit | Polar API | Returns 400 with "activation limit" message |
| Expiration | Local + API | Compares `expiresAt` with current date |
| Status | Polar API | Must be "granted" (not "revoked") |

---

## Data Integrity Notes

### Backward Compatibility

```swift
// Handles missing sourceType field in older JSON
sourceType = try container.decodeIfPresent(TranscriptSourceType.self, forKey: .sourceType) ?? .live

// Migrates deprecated "auto" language to "en"
let storedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
self.selectedLanguage = storedLanguage == "auto" ? "en" : storedLanguage

// Migrates legacy model names (e.g. "tiny") to colon format ("whisper:tiny")
let rawModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "parakeet:tdt-0.6b-v3"
self.selectedModel = ModelIdentifier.migrateLegacy(rawModel)

// Validates saved languages against model's supported language list on launch
// Resets to English if model no longer supports the saved language
```

### Thread Safety

| Component | Isolation Strategy |
|-----------|-------------------|
| AppState | `@MainActor` - all access on main thread |
| TranscriptionService | `actor` - isolated mutable state |
| AudioRecorder | `@MainActor` - audio callbacks dispatched to main |
| LLMService | `@MainActor` - configuration access |
| AudioFileReader | `NSLock` for cancellation flag |
| AudioDeviceManager | CoreAudio HAL property listeners, device enumeration |
| AccessibilityReader | AXUIElement queries with 200ms timeout |
| TrialService | Singleton `TrialService.shared`, Keychain access |

### Atomic Operations

```swift
// TranscriptHistoryManager.swift
try data.write(to: storageURL, options: .atomic)
// Uses atomic write to prevent partial file corruption
```

### Error Recovery

| Error State | Recovery |
|-------------|----------|
| Transcription failure | Error displayed for 3 seconds, auto-dismiss to idle |
| AI Transform stream failure | Orange error card via `failAIResponseStream()`, Escape to dismiss |
| AI Q&A stream failure | Orange error card via `failAIResponseStream()`, Escape to dismiss |
| Secure text field detected | Falls back to normal dictation (AXUIElement detection) |
| Selected microphone disconnected | Auto-fallback to system default, warning banner in Settings |
| Model load failure | Error displayed, user can retry via settings |
| Network error (license) | If cached license not expired, allow offline use |
| Trial tamper / clock rollback | Trial immediately expired |
| History file corruption | Start fresh with empty history |

---

*This document provides a comprehensive view of how data flows through the Yapper application, from user input through processing to storage and output. Updated for v2.0.0.*
