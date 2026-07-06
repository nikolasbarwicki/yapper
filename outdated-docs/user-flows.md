# User Flows

## Primary Flow: Live Recording

The main user journey - recording speech and getting text in any app.

### Smart Detection (Two Recording Modes)

The recording shortcut (`Option+Space`) supports two modes based on timing:

**Toggle Mode (Quick Press < 0.3s)**
1. Press and quickly release `Option+Space`
2. Recording starts
3. Press `Option+Space` again to stop

**Hold-to-Record Mode (Hold >= 0.3s)**
1. Press and hold `Option+Space`
2. Recording starts immediately
3. Release any key (Option or Space) to stop recording

### Steps

1. **User focuses a text field** in any application (email, Slack, browser, etc.)
2. **User presses `Option+Space`** (toggle mode) or **holds `Option+Space`** (hold mode)
3. **Overlay appears** showing "Listening 0:00" with red pulsing indicator
4. **User speaks** - waveform animation shows audio level, timer counts up
5. **User presses shortcut again** (toggle mode) or **releases any key** (hold mode)
6. **Overlay shows "Transcribing"** with blue spinner
7. **[If AI enabled]** Overlay shows "Enhancing" with purple sparkles
8. **Text appears** in the focused field, typed character-by-character
9. **Overlay shows "Success"** with green checkmark (scale pop animation), auto-hides after 1 second
10. **Transcript saved** to history

### Cancel Recording

- Press `Escape` during recording to cancel
- Audio is discarded, nothing is transcribed or saved

### Timing

| Phase | Duration |
|-------|----------|
| Recording | User-controlled |
| Transcription | 1-2 seconds typical |
| AI Enhancement | 0.5-1 second |
| Text injection | ~10ms per character |

---

## File Transcription Flow

Transcribing an existing audio file.

1. **Click menu bar icon** → Select "Transcribe File..."
2. **Window opens** with drag-and-drop zone
3. **Drop file or click to browse** (MP3, WAV, M4A)
4. **File info displayed** (name, size, duration)
5. **Click "Transcribe"**
6. **Progress bar** shows transcription progress
7. **Transcript appears** in text area
8. **Options**: Copy to clipboard, Save to history, or Close

---

## First-Time Setup

What happens on first launch:

1. **App appears in menu bar** (waveform icon)
2. **Model download starts** (yellow indicator, ~1.5GB)
3. **First recording attempt** triggers microphone permission dialog
4. **First text injection** may fail until Accessibility permission granted

### Granting Accessibility Permission

The app cannot prompt for this - user must do it manually:

1. Open **System Settings**
2. Go to **Privacy & Security → Accessibility**
3. Click the **lock icon** to make changes
4. Find **Yapper** in the list
5. **Toggle ON**
6. Return to Yapper and try recording again

---

## Settings Navigation

Settings uses a horizontal segmented control with three tabs:

```
Settings Window (3-tab segmented control)
├── Transcription
│   ├── Model selector (tiny → large-v3-turbo)
│   ├── Language selector
│   └── Custom vocabulary
├── AI Enhancement
│   ├── Enable/disable toggle
│   ├── Provider selector (Gemini, OpenAI, Anthropic, xAI)
│   ├── Model selector (per provider)
│   ├── Selected provider API key (inline editing)
│   ├── Customize Prompt (collapsible)
│   └── Manage All API Keys (collapsible)
└── General
    ├── Keyboard Shortcuts
    │   ├── Recording toggle shortcut recorder
    │   └── Cancel shortcut recorder
    └── Launch at login toggle
```

### History Window (Standalone)

History is now a separate window accessible via:
- Menu bar: "History..." (⌘Y)

```
History Window
├── Retention picker (30-365 days)
├── Search bar
├── Transcript list
│   └── Each entry: text preview, timestamp, duration
├── Statistics (count, total duration, time saved)
└── Clear all button
```

---

## Menu Bar Interactions

| Menu Item | Shortcut | Action |
|-----------|----------|--------|
| Start/Stop Recording | | Toggle recording (same as hotkey) |
| Transcribe File... | | Open file transcription window |
| History... | ⌘Y | Open standalone history window |
| Settings... | ⌘, | Open settings window |
| Quit Yapper | ⌘Q | Exit application |

The menu bar icon shows status with colored dots:
- No dot = idle and ready
- Yellow dot = model loading
- Red dot = recording
- Blue dot = processing
- Purple dot = enhancing
- Green dot = success (1 second)
