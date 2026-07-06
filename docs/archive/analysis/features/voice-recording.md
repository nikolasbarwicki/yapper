# Voice Recording & Transcription - Deep Dive

## Purpose

This feature captures live audio from a user-selectable microphone, converts it to 16kHz mono PCM format, and performs on-device speech-to-text transcription using either OpenAI Whisper (via WhisperKit) or NVIDIA Parakeet (via FluidAudio) through a pluggable backend architecture. It is the core functionality of Yapper, enabling hands-free dictation that outputs text directly into any focused application. Supports both batch and streaming transcription modes, microphone selection with hot-plug support, and live audio level metering.

---

## User-Facing Behavior

| Action | Result |
|--------|--------|
| Press recording hotkey (default: Option+Space) | Starts recording if permissions granted and model loaded; shows overlay with "Listening..." state |
| Quick press (<0.3s) recording hotkey | Toggle mode - press again to stop recording |
| Hold (>=0.3s) recording hotkey | Hold-to-record mode - release any key to stop recording |
| Press cancel hotkey (default: Esc) during recording | Cancels recording, discards audio, hides overlay |
| Recording stops | Audio transcribed via active backend (WhisperKit or FluidAudio), overlay shows "Processing..." state |
| Transcription completes (batch) | Text injected into focused app, overlay shows green success for 1 second, optional sound plays |
| Transcription completes (streaming) | Tokens typed in real-time as WhisperKit decodes, overlay shows green success on finish |
| Error occurs | Overlay shows error message for 3 seconds, then auto-dismisses |
| Press hotkey during error | Clears error and starts new recording immediately |
| File transcription | Drag/drop audio file, converts to 16kHz mono, transcribes using same WhisperKit pipeline |

---

## Public Interface

### AudioRecorder

**Location**: `Yapper/Services/AudioRecorder.swift`

```swift
@MainActor
final class AudioRecorder {
    func checkPermission() async -> Bool
    func requestPermission() async -> Bool
    func startRecording(deviceID: AudioDeviceID?, callback: @escaping @Sendable (Float) -> Void) -> Bool
    func stopRecording() -> Data?
    func setInputDevice(_ deviceID: AudioDeviceID?) throws
}
```

| Method | Purpose |
|--------|---------|
| `checkPermission()` | Returns current microphone permission status without prompting |
| `requestPermission()` | Triggers system permission dialog, returns grant result |
| `startRecording(deviceID:callback:)` | Starts audio capture on specified device (nil = system default), returns success Bool |
| `stopRecording()` | Stops capture, returns raw PCM Data (16kHz mono Float32) or nil if not recording |
| `setInputDevice(_:)` | Configures AudioUnit via CoreAudio HAL (uninitialize → set device → reinitialize) |

### AudioDeviceManager (NEW - v2.0)

**Location**: `Yapper/Services/AudioDeviceManager.swift`

| Method/Property | Purpose |
|-----------------|---------|
| `availableDevices: [AudioInputDevice]` | Currently connected audio input devices |
| `startMonitoring()` | Begin CoreAudio HAL property listeners for hot-plug |
| `stopMonitoring()` | Stop property listeners |
| `startLevelMetering(for:callback:)` | Start real-time level metering via temporary AVAudioEngine |
| `stopLevelMetering()` | Stop level metering |
| `resolveDeviceID(for:) -> AudioDeviceID?` | Resolve stable UID to volatile runtime device ID |

### AudioInputDevice (NEW - v2.0)

**Location**: `Yapper/Services/AudioInputDevice.swift`

```swift
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let audioDeviceID: AudioDeviceID  // Volatile runtime ID (UInt32)
    let uid: String                    // Stable persistent UID
    let name: String                   // Human-readable device name
}
```

### TranscriptionService

**Location**: `Yapper/Services/TranscriptionService.swift`

```swift
actor TranscriptionService {
    var isReady: Bool { get }
    var currentEngine: TranscriptionEngine? { get }
    func unloadModel()
    func loadModel(modelName: String, progressHandler: @escaping @Sendable (Double) -> Void, phaseHandler: @escaping @Sendable (ModelLoadPhase) -> Void) async throws
    func transcribe(audioData: Data, language: String, customVocabulary: [String]) async throws -> String?
    func transcribeStreaming(audioData: Data, language: String, customVocabulary: [String], onToken: @escaping @Sendable (String) -> Void) async throws -> String?
}

enum ModelLoadPhase: Sendable {
    case downloading  // 0-80% of progress
    case loading      // 80-100% of progress (includes prewarm)
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)
    case downloadTimedOut
}
```

| Method | Purpose |
|--------|---------|
| `isReady` | True when a backend model is loaded and ready for transcription |
| `currentEngine` | The engine of the currently loaded backend (.whisper or .parakeet) |
| `unloadModel()` | Releases current backend and model from memory |
| `loadModel(...)` | Parses colon-format model ID, creates backend, downloads if needed, loads model |
| `transcribe(...)` | Delegates to active backend for batch transcription |
| `transcribeStreaming(...)` | Delegates to active backend for streaming transcription (WhisperKit supports true streaming, Parakeet falls back to batch) |

### AppState Recording State

**Location**: `Yapper/Models/AppState.swift`

```swift
enum RecordingState: Equatable {
    case idle                    // Ready to record
    case recording               // Actively recording audio
    case processing              // WhisperKit transcribing
    case aiTransforming          // AI Transform streaming
    case aiTransformResult       // AI Transform result ready
    case aiQA                    // AI Q&A streaming
    case aiQAResult              // AI Q&A result ready
    case error(message: String)  // Error with message
}
```

Key properties:
- `recordingState: RecordingState` - Current pipeline state
- `audioLevel: Float` - 0.0-1.0 for visualization
- `isModelLoaded: Bool` - Whether model is ready
- `modelLoadingProgress: Double` - 0.0-1.0 during loading
- `selectedModel: String` - Colon format e.g. `"parakeet:tdt-0.6b-v3"`, `"whisper:large-v3-turbo"`
- `isLoadingModel: Bool` - True while model loading is in progress
- `loadedModel: String?` - The model that is actually loaded (nil if none)
- `primaryLanguage: String` - Primary language code ("en", "es", "fr", etc.)
- `secondaryLanguage: String?` - Optional secondary language
- `activeLanguage: String` - Computed: returns current language for transcription
- `customVocabulary: [String]` - Custom recognition terms
- `selectedMicrophoneUID: String?` - Persisted mic selection (nil = system default)
- `availableInputDevices: [AudioInputDevice]` - Connected devices
- `microphoneFellBack: Bool` - True when selected mic was disconnected, fell back to default

---

## Events/Notifications

| Notification | Trigger | Purpose |
|--------------|---------|---------|
| `.menuBarNeedsUpdate` | recordingState, isModelLoaded changes | Update menu bar icon/status dot |
| `.modelSelectionChanged` | User changes model in settings | Triggers model reload |

---

## Dependencies

| Dependency | Type | Purpose |
|------------|------|---------|
| AVFoundation/AVAudioEngine | Framework | Audio capture and format conversion |
| WhisperKit | Swift Package | On-device Whisper model inference (via WhisperKitBackend) |
| FluidAudio | Swift Package | On-device Parakeet model inference (via FluidAudioBackend) |
| HuggingFace | External Service | Whisper model download hosting |
| AppState | Internal | State management |
| TextInjector | Internal | Outputs final text |
| LLMService | Internal | Optional text enhancement |
| SoundFeedbackService | Internal | Audio feedback for state changes |
| TranscriptHistoryManager | Internal | Persists transcriptions |

---

## Implementation Notes

### Audio Capture Pipeline (AudioRecorder)

1. **AVAudioEngine Setup**:
   - Gets input node (microphone) with native format (typically 48kHz stereo)
   - Creates AVAudioConverter to resample to 16kHz mono Float32
   - Installs "tap" on input node with 1024 buffer size

2. **Real-time Resampling**:
   ```swift
   let ratio = targetFormat.sampleRate / buffer.format.sampleRate  // e.g., 16000/48000 = 0.333
   let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
   ```

3. **Audio Level Calculation (RMS)**:
   ```swift
   // Root Mean Square for volume visualization
   for i in 0..<frameCount {
       sum += sample * sample
   }
   let rms = sqrt(sum / Float(frameCount))
   return min(rms * 10.0, 1.0)  // Amplified 10x for visibility
   ```

4. **Data Export**:
   - Converts `[Float]` to `Data` using `withUnsafeBufferPointer`
   - Zero-copy memory access for efficiency

### Multi-Engine Architecture

**TranscriptionBackend Protocol** (`TranscriptionBackend.swift`):
- Defines `loadModel`, `transcribe`, `transcribeStreaming`, `unloadModel` interface
- Implemented by `WhisperKitBackend` and `FluidAudioBackend`

**Model Registry** (`TranscriptionEngine.swift`):
- `TranscriptionEngine` enum: `.whisper`, `.parakeet`
- `ModelIdentifier` struct: colon-format parsing (`"engine:variant"`)
- `AvailableModels`: static registry with metadata (languages, memory estimates)
- `SupportedLanguages`: centralized language code/name/flag (single source of truth)
- Legacy model names auto-migrate via `ModelIdentifier.migrateLegacy()`

### WhisperKit Backend (WhisperKitBackend.swift)

1. **Model Name Mapping** (via `ModelIdentifier.whisperKitModelName()`):
   ```swift
   "large-v3-turbo" → "openai_whisper-large-v3_turbo"
   "tiny" → "openai_whisper-tiny"
   ```

2. **Model Download Directory**:
   - Models: `~/Library/Application Support/Yapper/models/`
   - Skips download if model files already exist locally
   - Uses `HF_HOME` environment variable to avoid TCC permission prompts

3. **Model Loading (Two Phases)**:
   - **Download Phase (0-80%)**: Fetches model from HuggingFace
   - **Load Phase (80-100%)**: Loads into memory, prewarms Neural Engine

4. **Streaming Support**: Uses WhisperKit's `DecodingCallback` to emit tokens during decoding

### FluidAudio Backend (FluidAudioBackend.swift)

1. **Model Download Directory**: `~/Library/Application Support/Yapper/parakeet-models/`
2. **Models**: Parakeet TDT v2 (English-only) and v3 (25 EU languages)
3. **Speed**: 110-190x real-time on Apple Silicon
4. **Streaming**: Falls back to batch + single callback (speed makes true streaming unnecessary)

### Model Storage Management (ModelStorageManager.swift)

- Tracks total disk usage across all downloaded models
- Removes partial download files on cancellation
- Clears all models on user request, re-creates empty directories

### Recording Flow Orchestration (AppDelegate)

```
User presses hotkey
        │
        ▼
handleRecordingKeyDown()
        │
        ├── Check: recordingState == .idle?
        │   └── Yes → startRecording()
        │
        ├── Check: recordingState == .recording?
        │   └── Yes → stopRecording() (toggle mode)
        │
        └── Check: recordingState == .error?
            └── Yes → Clear error, startRecording()

startRecording():
        │
        ├── Guard: hasMicrophonePermission
        ├── Guard: hasAccessibilityPermission
        ├── Guard: isModelLoaded
        │
        ▼
audioRecorder.startRecording(deviceID: selectedDeviceID, callback: levelCallback)
appState.startRecording()  // → .recording state
overlayWindow.show()

stopRecording():
        │
        ▼
appState.stopRecording()  // → .processing state
audioData = audioRecorder.stopRecording()
        │
        ▼
transcribeAudio(audioData):
        │
        ├── If streaming (not transform mode + Whisper engine):
        │   ├── transcriptionService.transcribeStreaming(onToken:)
        │   ├── Each token typed atomically via textInjector.typeStringAtomically()
        │   ├── TranscriptHistoryManager.addRecord()
        │   └── appState.completeTranscription()
        │
        └── If batch (transform mode or Parakeet engine):
            ├── transcriptionService.transcribe() → text
            ├── Post-transcription routing:
            │   ├── AI Transform → llmService.transformStream() → overlay card
            │   ├── "Hey Yapper" → llmService.qaStream() → overlay card
            │   └── Normal → textInjector.typeText(finalText)
            ├── TranscriptHistoryManager.addRecord()
            └── appState.completeTranscription()  // → .idle + 1s green indicator
```

---

## State Machine

```
     ┌──────────────────────────────────────────────┐
     │                                              │
     ▼                                              │
  [idle] ──hotkey──▶ [recording] ──stop──▶ [processing]
     ▲                   │                    │
     │                   │                    ├── AI Transform? ──▶ [aiTransforming] ──▶ [aiTransformResult]
     │                cancel                  │                                              │
     │                   │                    ├── Hey Yapper? ──▶ [aiQA] ──▶ [aiQAResult]    │
     │                   ▼                    │                                   │           │
     └───────────────[idle]◀──complete────────┘                                  │           │
     │                                        ◀──────────Escape──────────────────┘───────────┘
     └──────────────[error]───3s timeout──▶[idle]
```

---

## Persistent Settings (UserDefaults)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `selectedModel` | String | `"parakeet:tdt-0.6b-v3"` | Model in colon format |
| `primaryLanguage` | String | "en" | Primary transcription language |
| `secondaryLanguage` | String? | nil | Optional secondary language |
| `customVocabulary` | [String] | [] | Custom recognition terms |
| `selectedMicrophoneUID` | String? | nil (system default) | Persisted microphone selection |

---

## Edge Cases & Gotchas

1. **Double Recording Prevention**: Guards with `!isRecording` and `isRecording` checks
2. **Model Not Loaded**: Recording blocked with error message
3. **Permission Missing**: Shows error, triggers permission request
4. **Empty Transcription**: Returns nil, shows "No speech detected" error
5. **Cancellable Downloads**: Users can cancel in-progress model downloads; partial files are cleaned up
6. **Memory Pressure**: Large-v3-turbo is ~1.5GB; no explicit memory warning handling
7. **Model Switch During Download**: Switching models auto-cancels the current download
7. **Actor Isolation**: TranscriptionService prevents concurrent transcriptions
8. **Cancel During File Loading**: Uses NSLock for thread-safe cancellation

---

## Technical Debt

1. No retry on model download failure
2. ~~Missing audio device change handling~~ (resolved in v2.0: AudioDeviceManager with hot-plug support)
3. Hardcoded audio level amplification (10x)
4. No audio recording timeout/max duration
5. Model download progress mapping (0-80% download, 80-100% load) is approximate
6. No offline model availability check
7. Verbose WhisperKit logging in production
8. File transcription shares service instance with live recording

---

## Performance Considerations

1. **Neural Engine Utilization**: ~3-10x faster than CPU-only on Apple Silicon
2. **Real-time Audio Level Updates**: ~60Hz via MainActor
3. **Chunk-based File Loading**: 16384 frame chunks with progress
4. **Memory Efficiency**: `reserveCapacity()` and `withUnsafeBufferPointer`
5. **Model Prewarm**: First inference is faster with `prewarm: true`

---

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `Yapper/Services/AudioRecorder.swift` | ~260 | Audio capture, resampling, device selection |
| `Yapper/Services/AudioDeviceManager.swift` | ~200 | CoreAudio HAL enumeration, hot-plug, level metering |
| `Yapper/Services/AudioInputDevice.swift` | ~50 | Audio device model struct |
| `Yapper/Views/MicrophoneLevelView.swift` | ~100 | Real-time level meter (green/yellow/red) |
| `Yapper/Services/TranscriptionService.swift` | 155 | Thin coordinator actor |
| `Yapper/Services/TranscriptionBackend.swift` | 53 | Backend protocol definition |
| `Yapper/Services/WhisperKitBackend.swift` | 253 | WhisperKit engine implementation |
| `Yapper/Services/FluidAudioBackend.swift` | 147 | FluidAudio (Parakeet) engine |
| `Yapper/Models/TranscriptionEngine.swift` | 298 | Engine enum, model registry, languages |
| `Yapper/Utilities/ModelStorageManager.swift` | 91 | Model disk usage and cleanup |
| `Yapper/Services/AudioFileReader.swift` | 236 | File loading/conversion |
| `Yapper/App/AppDelegate.swift` | ~1,449 | Recording orchestration (batch + streaming) |
| `Yapper/Models/AppState.swift` | ~552 | State management |
