# Product Overview

## Vision

Yapper transforms how people create text. Instead of typing, users speak naturally and their words appear instantly in any application. The app combines offline speech recognition with optional AI enhancement for a private, fast voice-to-text experience.

**Core promise**: Speak naturally. Type less. Create more.

---

## Features

### Live Speech-to-Text
Press a global hotkey from any app, speak, and text is typed into your focused field.

- **Trigger**: `Option+Space` (customizable)
- **Feedback**: Floating overlay shows recording status
- **Output**: Text typed character-by-character (preserves undo)
- **Latency**: 1-3 seconds after speaking

### Offline Transcription
All speech recognition happens locally using WhisperKit - no audio leaves your device.

- **Engine**: OpenAI Whisper optimized for Apple Neural Engine
- **Models**: tiny, base, small, large-v3, large-v3-turbo
- **Languages**: 99+ with auto-detection

### AI Text Enhancement (Optional)
Optionally improve transcribed text using your choice of LLM provider.

- **Providers**: Gemini, OpenAI, Anthropic, xAI (Grok)
- **Models**:
  - Gemini: Gemini 3 Flash Preview, Gemini 3 Pro Preview
  - OpenAI: GPT-5 Mini, GPT-5 Nano
  - Anthropic: Claude Sonnet 4.5, Claude Haiku 4.5
  - xAI: Grok 4, Grok 4.1 Fast
- **Capabilities**: Grammar, spelling, formatting, translation
- **Custom prompts**: Configure how text is enhanced
- **Fallback**: Original text used if enhancement fails

### File Transcription
Transcribe existing audio files without recording.

- **Formats**: MP3, WAV, M4A
- **Interface**: Drag-and-drop or file picker
- **Output**: View, copy, or save to history

### Transcript History
Searchable archive of all transcriptions.

- **Storage**: Local JSON file
- **Retention**: Configurable (30-365 days)
- **Features**: Search, delete, statistics

### Customizable Shortcuts
Personalize keyboard shortcuts for all actions.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  User presses Option+Space                                   │
│              ↓                                               │
│  Microphone captures audio (16kHz mono)                      │
│              ↓                                               │
│  WhisperKit transcribes locally (1-2 seconds)                │
│              ↓                                               │
│  [Optional] LLM API enhances text (Gemini/OpenAI/Anthropic/xAI) │
│              ↓                                               │
│  Transcript saved to history                                 │
│              ↓                                               │
│  Text typed into focused application via Accessibility API   │
│              ↓                                               │
│  Success overlay shown (1 second, then auto-hides)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Design Principles

1. **Invisible Until Needed** - Menu bar only, no dock icon, hotkey activation
2. **Non-Intrusive Feedback** - Small overlay, doesn't steal focus, auto-dismisses
3. **Privacy First** - Offline transcription, AI enhancement is opt-in
4. **Graceful Degradation** - Works offline, fallbacks for errors

---

## Status Indicators

| Color | Meaning |
|-------|---------|
| Yellow | Model loading |
| Red | Recording (pulsing) |
| Blue | Transcribing |
| Purple | AI enhancing (pulsing) |
| Green | Success (1 second) |
