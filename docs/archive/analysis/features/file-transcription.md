# File Transcription - Deep Dive

## Purpose

The File Transcription feature allows users to transcribe existing audio files (MP3, WAV, M4A) to text using on-device speech recognition (WhisperKit or FluidAudio, depending on selected model). Unlike live recording which captures from the microphone, this feature processes pre-recorded audio files.

---

## User-Facing Behavior

- **Open file picker**: Menu bar > "Transcribe Audio File..." opens dedicated window
- **Select audio file**: Click "Choose File..." opens NSOpenPanel for MP3/WAV/M4A
- **View file info**: Displays file name, duration (e.g., "1:23"), file size (e.g., "1.2 MB")
- **Start transcription**: Click "Start Transcription" (disabled if model not loaded)
- **Loading phase**: Linear progress bar with percentage
- **Transcribing phase**: Indeterminate spinner
- **Completed**: Scrollable text view with "Copy" button
- **Cancel during processing**: Confirmation alert before cancelling
- **Error states**: Error message with "Try Again" button
- **Cancelled state**: Message with "Select New File" button

---

## Public Interface

### AudioFileReader

**Location**: `Yapper/Services/AudioFileReader.swift`

```swift
final class AudioFileReader {
    static let supportedTypes: [UTType] = [.mp3, .wav, .mpeg4Audio]

    func getFileInfo(url: URL) async throws -> AudioFileInfo
    func loadAudio(url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> Data
    func cancel()
}
```

### AudioFileInfo

```swift
struct AudioFileInfo: Equatable {
    let url: URL
    let fileName: String
    let fileSize: Int64
    let duration: TimeInterval
}
```

### AudioFileError

```swift
enum AudioFileError: LocalizedError {
    case unsupportedFormat    // "Use MP3, WAV, or M4A"
    case fileNotFound         // "File could not be found"
    case invalidAudioFile     // "No valid audio data"
    case conversionFailed(String)
    case cancelled
}
```

### FileTranscriptionWindowController

**Location**: `Yapper/Views/FileTranscriptionWindowController.swift`

```swift
class FileTranscriptionWindowController {
    func showWindow()
    func closeWindow()
    var cancelHandler: (() -> Void)?
}
```

---

## Implementation Notes

### Format Conversion Pipeline

1. Open file with `AVAudioFile(forReading:)` to get source format
2. Create target format: 16kHz, mono, Float32, non-interleaved
3. `AVAudioConverter` handles resampling and format conversion
4. Process in 16,384-frame chunks for progress reporting
5. Read chunks into `AVAudioPCMBuffer`, convert, extract samples
6. Accumulate Float samples, convert to `Data` for WhisperKit

### Progress Reporting

- `ProgressCoordinator` bridges actor isolation between reader and MainActor
- Progress handler is `@Sendable`, dispatches via `Task`
- Loading: Determinate progress (0-100%)
- Transcription: Indeterminate (WhisperKit doesn't expose progress)

### Cancellation Handling

- `AudioFileReader` uses `NSLock` for thread-safe `isCancelled` flag
- Checked between each chunk read
- `Task.yield()` after each chunk for cancellation checks
- Window close during processing triggers confirmation
- Cancellation sets `isTranscribingFile = false`, clears reader

### Window Management

- `NSWindowDelegate` intercepts window close
- `windowShouldClose` returns false during processing
- Window is floating level (`.floating`)
- Reuses existing window if already open

---

## State Machine

```swift
enum FileTranscriptionState: Equatable {
    case idle                              // Show file picker
    case fileSelected(AudioFileInfo)       // Ready to transcribe
    case loading(progress: Double)         // Converting (0.0-1.0)
    case transcribing(progress: Double)    // WhisperKit processing
    case completed(text: String)           // Done, showing result
    case error(message: String)            // Error occurred
    case cancelled                         // User cancelled
}
```

---

## State & Data

### AppState Integration

- `appState.isTranscribingFile: Bool` - Prevents multiple simultaneous transcriptions
- `appState.isModelLoaded: Bool` - Required for "Start Transcription"
- `appState.selectedLanguage: String` - Passed to TranscriptionService
- `appState.customVocabulary: [String]` - Passed to TranscriptionService

### History Integration

On success, creates `TranscriptRecord` with `.file` source type:
- `sourceFileName`
- `sourceFilePath`
- `sourceFileSize`

Saved via `TranscriptHistoryManager.shared.addRecord(record)`.

---

## Edge Cases & Gotchas

1. **File permission prompt**: NSOpenPanel starts in home directory to avoid permission prompts

2. **No progress during transcription**: WhisperKit doesn't expose progress; uses indeterminate spinner

3. **Model not loaded**: "Start Transcription" disabled if model not ready

4. **Fresh reader per transcription**: New instance avoids stale cancellation state

5. **Sample rate conversion ratio**: `Double(sourceFrameCount) * (16000 / sourceFormat.sampleRate)` may have rounding

6. **Converter callback**: `AVAudioConverter.convert(to:error:)` uses callback returning `.haveData`

7. **Large file memory**: All samples accumulated in memory before conversion

8. **Copy feedback**: "Copied!" reverts after 1.5 seconds

9. **Cancel handler**: Passed via `onCancelHandlerReady` closure during `onAppear`

---

## Technical Debt

1. **Memory inefficiency**: Large files fully loaded before transcription; could stream chunks

2. **No transcription progress**: Indeterminate spinner for potentially long operations

3. **Single file at a time**: `isTranscribingFile` prevents concurrent; could support batch

4. **No drag-and-drop**: Must use file picker

5. **Progress coordinator complexity**: `@unchecked Sendable` workaround

6. **Hardcoded chunk size**: 16,384 frames; could tune

7. **Limited format support**: Could support FLAC, OGG, AAC

8. **Technical error messages**: "Failed to create audio converter" not user-friendly

---

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `Yapper/Services/AudioFileReader.swift` | 237 | Audio loading/conversion |
| `Yapper/Views/FileTranscriptionView.swift` | 578 | UI and state machine |
| `Yapper/Views/FileTranscriptionWindowController.swift` | 108 | Window management |
| `Yapper/Models/TranscriptRecord.swift` | 154 | Record model |
| `Yapper/Services/TranscriptHistoryManager.swift` | 227 | Persistence |

---

## Key Code Snippets

### Audio Conversion Loop

```swift
while framesRead < sourceFrameCount {
    if isCancelled {
        throw AudioFileError.cancelled
    }

    let framesToRead = min(chunkSize, sourceFrameCount - framesRead)
    // ... create buffer, read, convert ...

    let progress = Double(framesRead) / Double(sourceFrameCount)
    await MainActor.run {
        progressHandler(progress)
    }
    await Task.yield()
}
```

### State-Driven UI

```swift
@ViewBuilder
private var contentView: some View {
    switch state {
    case .idle:
        filePickerView
    case .fileSelected(let fileInfo):
        fileInfoView(fileInfo)
    case .loading(let progress):
        progressView(title: "Loading Audio", progress: progress, indeterminate: false)
    case .transcribing:
        progressView(title: "Transcribing", progress: 0, indeterminate: true)
    case .completed(let text):
        completedView(text: text)
    case .error(let message):
        errorView(message: message)
    case .cancelled:
        cancelledView
    }
}
```

### Window Close Interception

```swift
func windowShouldClose(_ sender: NSWindow) -> Bool {
    if appState.isTranscribingFile {
        showCancelConfirmation(window: sender)
        return false
    }
    return true
}
```
