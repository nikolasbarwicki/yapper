# Yapper User Guide

Welcome to Yapper, a voice-to-text dictation app for macOS. Yapper lets you speak naturally and have your words automatically typed into any application. This guide will help you get started and make the most of Yapper's features.

---

## Table of Contents

1. [Getting Started](#getting-started)
   - [System Requirements](#system-requirements)
   - [Installation](#installation)
   - [First Launch and Permissions](#first-launch-and-permissions)
   - [Open Source Availability](#open-source-availability)
2. [Using Voice Dictation](#using-voice-dictation)
   - [Starting a Recording](#starting-a-recording)
   - [Recording Modes: Toggle vs Hold](#recording-modes-toggle-vs-hold)
   - [Understanding the Recording Overlay](#understanding-the-recording-overlay)
   - [Canceling a Recording](#canceling-a-recording)
3. [AI Transform Mode](#ai-transform-mode)
   - [How AI Transform Works](#how-ai-transform-works)
   - [Requirements](#ai-transform-requirements)
   - [Limitations](#ai-transform-limitations)
4. [AI Q&A Voice Assistant ("Hey Yapper")](#ai-qa-voice-assistant-hey-yapper)
   - [How to Use Hey Yapper](#how-to-use-hey-yapper)
   - [Recognized Wake Phrases](#recognized-wake-phrases)
   - [Q&A UI Flow](#qa-ui-flow)
5. [Microphone Selection](#microphone-selection)
6. [Transcribing Audio Files](#transcribing-audio-files)
   - [Supported Formats](#supported-formats)
   - [How to Transcribe a File](#how-to-transcribe-a-file)
7. [Keyboard Shortcuts](#keyboard-shortcuts)
   - [Default Shortcuts](#default-shortcuts)
   - [Customizing Shortcuts](#customizing-shortcuts)
8. [Language Switching](#language-switching)
   - [Setting Up Languages](#setting-up-languages)
   - [Switching Between Languages](#switching-between-languages)
9. [Auto-Type Toggle](#auto-type-toggle)
   - [What Auto-Type Does](#what-auto-type-does)
   - [Toggling Auto-Type](#toggling-auto-type)
10. [AI Provider Setup](#ai-provider-setup)
    - [Choosing a Provider and Model](#choosing-a-provider-and-model)
    - [Markdown Rendering](#markdown-rendering)
11. [Settings and Preferences](#settings-and-preferences)
    - [Transcription Settings](#transcription-settings)
    - [AI Settings](#ai-settings)
    - [Preferences](#preferences-settings)
12. [Transcript History](#transcript-history)
    - [Viewing Your History](#viewing-your-history)
    - [Copy Last Transcript](#copy-last-transcript)
    - [Searching and Copying](#searching-and-copying)
13. [Troubleshooting](#troubleshooting)
    - [Common Issues](#common-issues)
    - [Error Messages](#error-messages)
14. [Privacy and Security](#privacy-and-security)
    - [How Your Data Is Handled](#how-your-data-is-handled)
    - [Permissions Explained](#permissions-explained)
15. [Quick Reference](#quick-reference)

---

## Getting Started

### System Requirements

- **macOS 14 (Sonoma) or later**
- Apple Silicon Mac (M1, M2, M3, or newer) recommended for best performance
- At least 2 GB of free disk space for speech recognition models
- Internet connection for initial model download and AI features (optional)

### Installation

1. Download a release from the repository's GitHub Releases page, or build Yapper from source with Xcode.
2. Open the downloaded file and drag Yapper to your Applications folder.
3. Right-click Yapper and choose **Open** if macOS shows an unidentified developer warning.
4. Launch the app.

Yapper runs as a menu bar app, so you will see a small icon appear in your menu bar at the top of the screen rather than in the Dock.

### First Launch and Permissions

When you first open Yapper, you will need to grant two important permissions. An orange gradient permissions banner appears at the top of the Settings window when either permission is missing, with a "Grant Access" button that opens the relevant System Settings page.

#### Accessibility Permission

Accessibility is required for Yapper to function. It is used for text injection (typing transcriptions into apps), reading selected text (for AI Transform mode), and detecting secure text fields.

1. On first launch, Yapper prompts you to grant Accessibility access. This prompt persists until you grant permission.
2. Click **Open System Settings** (or go to System Settings > Privacy & Security > Accessibility)
3. Find Yapper in the list and turn on the toggle next to it
4. You may need to unlock the settings by clicking the lock icon and entering your password

#### Microphone Permission

Yapper needs access to your microphone to hear your voice.

1. When you first try to record, macOS will show a dialog asking for microphone access
2. Click **Allow** to grant permission
3. If you accidentally clicked "Don't Allow," the permissions banner in Settings will help you open System Settings to enable it manually

### Open Source Availability

Yapper is open source and no longer requires a license key, trial, purchase, or activation. Settings > Preferences shows the app as available with no license key required.

---

## Using Voice Dictation

### Starting a Recording

To dictate text with Yapper:

1. Click in any text field where you want to type (email, document, chat, etc.)
2. Press the recording shortcut: **Option + Space** (default)
3. Start speaking when you see the recording overlay appear
4. Press the shortcut again (or release if holding) to stop recording
5. Your speech will be transcribed and automatically typed into the text field

### Recording Modes: Toggle vs Hold

Yapper intelligently detects how you use the keyboard shortcut:

**Toggle Mode** (Quick Press)
- Press and quickly release the shortcut (less than 0.3 seconds)
- Recording starts and continues until you press the shortcut again
- Best for longer dictations

**Hold-to-Record Mode** (Press and Hold)
- Press and hold the shortcut for more than 0.3 seconds
- Recording continues while you hold the keys
- Release any key to stop recording
- Best for quick phrases or sentences

### Understanding the Recording Overlay

When recording, a small floating indicator (the "status pill") appears showing the current status. The overlay uses a frosted-glass (glassmorphism) design that automatically adapts to your macOS light or dark appearance. By default it follows your cursor; you can pin it to the top-center of the screen in Settings > Preferences.

| Overlay Color | Status | Meaning |
|---------------|--------|---------|
| Red | Listening | Yapper is recording your voice |
| Blue | Processing | Your speech is being transcribed |
| Purple | AI Active | AI Transform is processing, or Q&A is "Thinking..." |
| Green | Success | Text has been typed successfully, or "Answer Ready" |
| Red with message | Error | Something went wrong (message shown for 3 seconds) |

The overlay also shows a waveform animation while recording, so you can confirm Yapper is hearing your voice.

If you have a secondary language configured and are currently using it, a language flag emoji (e.g., a country flag) appears in the overlay alongside the recording duration to indicate which language is active.

### Canceling a Recording

If you start recording by mistake or change your mind:

1. Press **Escape** (default cancel shortcut) while recording
2. The recording will be discarded and no text will be typed

---

## Transcribing Audio Files

In addition to live dictation, Yapper can transcribe existing audio files.

### Supported Formats

Yapper supports the following audio formats:
- **MP3** (.mp3)
- **WAV** (.wav)
- **M4A** (.m4a)

### How to Transcribe a File

1. Click the Yapper icon in the menu bar
2. Select **Transcribe Audio File...**
3. Click **Choose File...** in the window that appears
4. Select your audio file
5. Review the file information (name, duration, size)
6. Click **Start Transcription**
7. Wait for the transcription to complete (a progress bar shows loading status)
8. Copy the result using the **Copy** button

> **Note**: File transcription uses the same speech model and language settings as live dictation. Make sure the correct language is selected in Settings before transcribing.

---

## Keyboard Shortcuts

### Default Shortcuts

| Action | Default Shortcut |
|--------|------------------|
| Start/Stop Recording | Option + Space |
| Cancel Recording | Escape |
| Cancel AI Transform / Dismiss result | Escape (while Transform is active) |
| Dismiss AI Q&A panel | Escape (while Q&A panel is open) |
| Toggle Language | Shift + Option + L |
| Toggle Auto-Type | Shift + Option + T |

> **Note**: The recording hotkey is blocked while an AI Transform is actively streaming. Escape serves as the universal cancel/dismiss key for Transform results and Q&A panels.

### Customizing Shortcuts

You can change the keyboard shortcuts to whatever works best for you:

1. Open Yapper Settings (click menu bar icon > Settings, or use Command + Comma)
2. Go to the **Preferences** pane
3. Find the **Keyboard Shortcuts** section
4. Click on the shortcut you want to change
5. Press your new key combination
6. The new shortcut will be saved automatically

**Requirements for valid shortcuts:**
- Regular keys (letters, numbers) must include at least one modifier key (Command, Shift, Option, or Control)
- Special keys like Escape and function keys (F1-F12) can work without modifiers

To reset shortcuts to defaults, click **Reset to Defaults** at the bottom of the Keyboard Shortcuts section.

---

## Language Switching

Yapper supports quick switching between two languages, so you can dictate in different languages without opening Settings each time.

### Setting Up Languages

1. Open Yapper Settings (click menu bar icon > Settings)
2. Go to the **Transcription** tab
3. Set your **Primary Language** (your main dictation language)
4. Set a **Secondary Language** (optional) from the dropdown below
5. The secondary language list excludes your primary language to avoid duplicates

### Switching Between Languages

Once a secondary language is configured:

1. Press **Shift + Option + L** (default) to toggle between your primary and secondary language
2. A floating pill briefly appears confirming the switch (e.g., "Switched to Spanish") with the language's flag emoji
3. The pill auto-dismisses after 1.5 seconds
4. During recording, the active language flag appears in the recording overlay when the secondary language is selected

> **Note**: The language toggle is ignored while actively recording. Switch languages before starting a recording. The active language resets to your primary language each time Yapper launches.

---

## Auto-Type Toggle

### What Auto-Type Does

Auto-type controls whether transcribed text is automatically typed into the focused application via the Accessibility API. When enabled (the default), Yapper works as usual — your speech is transcribed and immediately typed into the active text field. When disabled, transcriptions are still processed and saved to your transcript history, but no text is injected into any application.

This is useful when you want to:
- Dictate notes to history without inserting text anywhere
- Temporarily pause text injection without stopping Yapper
- Review transcriptions in history before manually pasting them

### Toggling Auto-Type

You can toggle auto-type in three ways:

1. **Keyboard shortcut**: Press **Shift + Option + T** (default) to toggle auto-type on or off. A floating toast pill briefly appears confirming the new state (e.g., "Auto-type On" or "Auto-type Off").
2. **Menu bar**: Click the Yapper menu bar icon — the "Auto-type" menu item shows a checkmark when enabled. Click it to toggle.
3. **Settings**: Open Settings > Preferences and find the "Output" section to toggle auto-type.

> **Note**: Transcriptions are always saved to history regardless of the auto-type setting. Only the automatic text injection is affected.

---

## AI Transform Mode

AI Transform lets you rewrite any selected text using a voice instruction. Instead of automatic post-processing, AI in Yapper 2.0 is strictly user-initiated.

### How AI Transform Works

1. **Select text** in any application (email, document, chat, etc.)
2. **Press your recording hotkey** (default: Option + Space)
3. **Speak your instruction** -- for example, "make this more formal," "translate to Spanish," or "summarize this"
4. Yapper reads the selected text, sends it along with your voice instruction to your configured AI provider, and streams the result token-by-token into an expanded overlay card
5. Once streaming completes, the original selection is deleted and replaced with the transformed text
6. Press **Escape** at any time to cancel the transform and dismiss the result card without replacing any text

### AI Transform Requirements

- A configured AI provider (Gemini, OpenAI, Anthropic, or xAI) with a valid API key (see [AI Provider Setup](#ai-provider-setup))
- Accessibility permission granted (required for reading selected text and injecting the replacement)

### AI Transform Limitations

- Selected text is capped at **10,000 characters**. Selections beyond this limit are ignored.
- **Secure text fields** (such as password fields) are automatically detected and skipped -- Yapper falls back to normal dictation mode instead.
- The recording hotkey is blocked while a transform is actively streaming.

---

## AI Q&A Voice Assistant ("Hey Yapper")

Ask Yapper a question during any recording and get an AI-generated answer in a floating panel.

### How to Use Hey Yapper

1. Start a recording as usual (press your recording hotkey)
2. Say **"Hey Yapper"** followed by your question -- for example, "Hey Yapper, what's the capital of Japan?"
3. Stop recording (press the hotkey again or release if holding)
4. Yapper detects the wake phrase, extracts your question, and sends it to your configured AI provider

If no AI provider is configured, the wake phrase is ignored and the full transcription is treated as normal dictation.

### Recognized Wake Phrases

Yapper recognizes **35+ pronunciation variants** to handle common speech-to-text misrecognitions, including:

- **Standard:** "Hey Yapper"
- **Vowel/consonant variations:** "hey yaper," "hey yappar," "hey yepper," "hey yupper"
- **Missing leading Y:** "hey apper," "hey upper"
- **Consonant swaps:** "hey rapper," "hey japper," "hey napper," "hey dapper," "hey tapper," "hey zapper"
- **Similar sounds:** "hey jabber," "hey yabber"
- **Plural/suffix drift:** "hey yappers," "hey yap per," "hey yap her"
- **"Hey" variants:** "hay yapper," "hei yapper," "hey a yapper," "a yapper"
- **Merged tokens:** "heyyapper"

> **Tip**: If "Hey Yapper" is not being recognized, try speaking clearly with a brief pause after "Hey Yapper" before asking your question.

### Q&A UI Flow

1. After you stop recording, the status pill transitions to a **purple "Thinking..."** state
2. The pill expands into a larger card showing the streaming AI answer, with your question displayed in a dimmed header above the answer
3. When the answer is complete, the card turns **green** and shows **"Answer Ready"**
4. A **Copy** button lets you copy the raw answer text (including Markdown formatting) to your clipboard
5. Press **Escape** to dismiss the Q&A panel at any time (also cancels an in-progress AI request)

---

## Microphone Selection

Yapper lets you choose which microphone to use for recording.

1. Open Settings > **Transcription**
2. Find the **Input Device** dropdown
3. Select your preferred microphone from the list, or choose **"System Default"** to use whatever macOS has set as the default input device

A **live audio level meter** appears below the device picker, showing real-time input levels with green, yellow, and red color coding so you can verify your microphone is working before you start recording.

**Hot-plug support:** New audio devices are detected instantly when plugged in and appear in the dropdown. If your selected microphone is disconnected, Yapper automatically falls back to the system default device and displays a warning banner in Settings.

---

## AI Provider Setup

AI features (Transform and Q&A) require an API key from one of the supported providers. To configure a provider:

1. Open Yapper Settings
2. Go to the **AI** pane in the sidebar
3. Choose a provider (Gemini, OpenAI, Anthropic, or xAI)
4. Enter your API key for that provider
5. Click **Save**

### Choosing a Provider and Model

Yapper supports four AI providers:

| Provider | Models Available | Notes |
|----------|------------------|-------|
| **Gemini** (Google) | Gemini 3 Flash Preview, Gemini 3 Pro Preview | Good balance of speed and quality |
| **OpenAI** | GPT-5 Mini, GPT-5 Nano | Well-established, reliable |
| **Anthropic** | Claude Sonnet 4.5, Claude Haiku 4.5 | Strong language understanding |
| **xAI** | Grok 4, Grok 4.1 Fast | Alternative option |

To get an API key:
1. Select your preferred provider in Yapper
2. Click the **Get API Key** link shown below the API key field
3. Sign up or log in to the provider's website
4. Create an API key and copy it
5. Paste the key in Yapper and save

> **Note**: API keys are stored locally on your Mac. AI providers charge for API usage, so check their pricing before use.

### Markdown Rendering

AI responses from both Transform and Q&A modes display with full Markdown formatting -- headings, bold, italic, code blocks, lists, tables, and blockquotes. The **Copy** button copies the raw Markdown text, so you can paste it into any Markdown-compatible editor.

---

## Settings and Preferences

Access settings by clicking the Yapper menu bar icon and selecting **Settings**, or by pressing **Command + Comma**.

The Settings window uses a **sidebar navigation** layout in the style of macOS System Settings. The sidebar lists the available panes: **Transcription**, **AI**, and **Preferences**.

If Microphone or Accessibility permissions are missing, an **orange gradient permissions banner** appears at the top of the window with a contextual message and a "Grant Access" button.

### Transcription Settings

Found in the **Transcription** pane:

**Speech Model**
Choose the AI model used for speech recognition. Models are grouped by engine:

*Parakeet (NVIDIA) — Recommended*

| Model | Speed | Accuracy | Memory | Languages |
|-------|-------|----------|--------|-----------|
| Parakeet TDT v3 (Default) | Very Fast | Excellent | ~800 MB | 25 EU languages |
| Parakeet TDT v2 | Very Fast | Excellent | ~800 MB | English only |

*Whisper (OpenAI)*

| Model | Speed | Accuracy | Memory | Languages |
|-------|-------|----------|--------|-----------|
| Large v3 Turbo | Fast | Excellent | ~1.5 GB | ~100 languages |
| Large v3 | Slower | Excellent | ~3 GB | ~100 languages |
| Small | Faster | Good | ~500 MB | ~100 languages |
| Base | Very Fast | Moderate | ~250 MB | ~100 languages |
| Tiny | Fastest | Basic | ~150 MB | ~100 languages |

The first time you select a model, it will be downloaded automatically. A progress bar shows the download status. You can cancel an in-progress download by clicking the cancel button next to the progress bar.

**Model Storage**
The Transcription settings tab shows how much disk space your downloaded models are using. Use "Clear Downloaded Models" to free disk space — the currently selected model will be re-downloaded automatically.

**Primary Language**
Select the main language you will be speaking. Available languages depend on the selected model:
- **Parakeet v3**: 25 EU languages — English, Bulgarian, Croatian, Czech, Danish, Dutch, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish, Ukrainian
- **Parakeet v2**: English only
- **Whisper models**: ~100 languages including Arabic, Chinese, Hindi, Japanese, Korean, Thai, Vietnamese, and many more

The language picker automatically filters to show only languages supported by the currently selected model. If you switch to a model that doesn't support your previously selected language, it will reset to English.

**Secondary Language (Optional)**
Set an optional secondary language for quick switching. When configured, you can toggle between primary and secondary languages using the language toggle shortcut (default: Shift + Option + L) without opening Settings.

**Input Device**
Choose which microphone Yapper uses for recording. A live audio level meter shows real-time input levels. See [Microphone Selection](#microphone-selection) for details.

**Custom Vocabulary**
Add specialized words, names, or acronyms that Yapper should recognize:

1. Type a word in the "Add word or phrase..." field
2. Press Enter or click **Add**
3. Words appear as tags that you can remove by clicking the X

Examples of useful vocabulary entries:
- Personal names: "Yapper", "McKenzie"
- Company names: "ACME Corp", "OpenAI"
- Technical terms: "OAuth", "Kubernetes"
- Acronyms: "API", "CEO", "ASAP"

### AI Settings

Found in the **AI** pane:

- **Provider**: Select which AI service to use (Gemini, OpenAI, Anthropic, or xAI)
- **Model**: Choose a specific model from your selected provider
- **API Key**: Enter and manage your API key

The AI pane also explains the two user-initiated AI modes with icons and descriptions:
- **Transform:** Select text, press your hotkey, speak an instruction to rewrite the selection
- **Q&A:** Say "Hey Yapper" followed by a question during recording to get an AI answer

> **Note**: There is no automatic AI enhancement toggle. AI features in Yapper 2.0 are strictly user-initiated via Transform or Q&A.

### Preferences

Found in the **Preferences** pane:

**Output**
This section combines sound feedback, overlay position, and text output settings:
- **Sound Feedback**: Enable audio feedback to hear system sounds when recording starts, transcription completes, or an error occurs. Disabled by default.
- **Overlay Position**: Choose between cursor-following (default) and fixed top-center positioning for the recording status pill.
- **Auto-Type**: Toggle whether transcribed text is automatically typed into the focused application. Enabled by default.

**Keyboard Shortcuts**
Customize your recording, cancel, language toggle, and auto-type toggle shortcuts.

**Availability**
Yapper is open source and shows that no license key is required.

---

## Transcript History

Yapper keeps a history of your transcriptions so you can review or reuse them later.

### Viewing Your History

1. Click the Yapper menu bar icon
2. Select **History**
3. Browse your past transcriptions

Each entry shows:
- The transcribed text
- When it was created
- Whether it was from live dictation or a file

### Copy Last Transcript

For quick access to your most recent transcription without opening the History window:

1. Click the Yapper menu bar icon
2. Select **Copy Last Transcript**
3. The text is now on your clipboard, ready to paste

This is useful when a transcription gets pasted into the wrong place (e.g., you switched apps during dictation) and you need to quickly recover it.

> **Note**: This menu item is disabled when no transcriptions exist.

### Searching and Copying

- Use the search bar to find specific transcriptions
- Click on any entry to select it
- Click **Copy** to copy the text to your clipboard
- Delete entries you no longer need

> **Note**: History is stored locally on your Mac and is automatically cleaned up based on your retention settings (default: 90 days).

---

## Troubleshooting

### Common Issues

**Yapper is not responding to the keyboard shortcut**

1. Check that Yapper is running (look for the icon in the menu bar)
2. Verify the model is loaded (check Settings > Transcription for loading status)
3. Ensure both Microphone and Accessibility permissions are granted
4. Try restarting Yapper

**The speech model is not loading**

1. Check your internet connection (models are downloaded from online)
2. Try selecting a smaller model (like "Small" or "Base") if downloads are slow
3. Ensure you have enough free disk space (check model storage usage in Settings > Transcription)
4. Wait for the download to complete (larger models can take several minutes)
5. If a download gets stuck, cancel it with the cancel button and try again
6. Try "Clear Downloaded Models" in Settings > Transcription if models seem corrupted

**Transcription quality is poor**

1. Try a different model -- Parakeet TDT v3 is recommended for EU languages, Large v3 Turbo for other languages
2. Make sure the correct language is selected
3. Add frequently misheard words to Custom Vocabulary
4. Speak clearly and reduce background noise
5. Use AI Transform to rewrite or clean up individual transcriptions on demand

**Text is not being typed into applications**

1. Grant Accessibility permission in System Settings (required for Yapper to function)
2. Make sure you click in a text field before recording
3. Try a different application to see if the issue is app-specific
4. Restart Yapper

**AI Transform or Q&A is not working**

1. Check that an AI provider and API key are configured in Settings > AI
2. Ensure you have an active internet connection
3. Check that your API key has sufficient credits/quota
4. For Transform: make sure text is selected before pressing the recording hotkey
5. For Q&A: make sure you say "Hey Yapper" clearly at the beginning of your recording

### Error Messages

| Error Message | Meaning | Solution |
|---------------|---------|----------|
| "Microphone permission required" | Yapper cannot access your microphone | Grant Microphone permission in System Settings |
| "Accessibility permission required" | Yapper cannot type into applications | Grant Accessibility permission in System Settings |
| "Model not loaded" | Speech recognition model is not ready | Wait for model to load or select a different model |
| "No speech detected" | Recording did not capture any voice | Speak louder or check your microphone |
| "Transcription failed" | An error occurred during processing | Try again; if persistent, try a different model |

---

## Privacy and Security

### How Your Data Is Handled

**Speech Recognition**
- All speech-to-text processing happens locally on your Mac using Apple's Neural Engine (WhisperKit) or CPU/GPU (FluidAudio)
- Your voice recordings are never sent to external servers for transcription
- Audio data is not stored after transcription completes

**AI Features (Optional, User-Initiated)**
- When you use AI Transform or Q&A, your text or question (not audio) is sent to your chosen AI provider
- This is the only time your data leaves your Mac
- AI is never invoked automatically -- it only runs when you explicitly trigger Transform or Q&A

**Transcript History**
- History is stored locally in your Mac's Application Support folder
- Transcripts are automatically deleted after the retention period (default: 90 days)
- You can manually delete any transcript at any time

**API Keys**
- Your API keys are stored locally on your Mac
- Keys are never shared with Yapper or any third party

### Permissions Explained

**Microphone**
- Used only when you actively record
- Required for live dictation
- Audio is processed locally and immediately discarded

**Accessibility**
- Required for Yapper to function (prompted on first launch, persists until granted)
- Used to simulate keyboard input for typing transcriptions into applications
- Used to read selected text for AI Transform mode
- Used to detect secure text fields (passwords) to avoid accidental exposure
- Never used to monitor your screen or read content you have not explicitly selected for transformation

---

## Quick Reference

### Keyboard Shortcuts

| Action | Default Shortcut |
|--------|------------------|
| Start/Stop Recording | Option + Space |
| Cancel Recording | Escape |
| Cancel AI Transform / Dismiss result | Escape |
| Dismiss AI Q&A panel | Escape |
| Toggle Language | Shift + Option + L |
| Toggle Auto-Type | Shift + Option + T |
| Open Settings | Command + Comma (when Yapper window is focused) |

### Recording States

| Overlay Color | State | What's Happening |
|---------------|-------|------------------|
| Red (animated) | Recording | Listening to your voice |
| Blue | Processing | Converting speech to text |
| Purple | AI Active | AI Transform streaming or Q&A "Thinking..." |
| Green | Success | Text typed, Transform complete, or Q&A "Answer Ready" |
| Red (static) | Error | Something went wrong |

### Speech Models

| Model | Best For |
|-------|----------|
| Parakeet TDT v3 | Daily use — fast, accurate, 25 languages (default) |
| Parakeet TDT v2 | English-only with highest English accuracy |
| Large v3 Turbo | 100+ languages with excellent accuracy |
| Large v3 | Maximum accuracy across all languages |
| Small | Faster results, good accuracy |
| Base | Quick transcriptions |
| Tiny | Minimal resource usage |

### AI Providers

| Provider | Get API Key |
|----------|-------------|
| Gemini | [ai.google.dev](https://ai.google.dev) |
| OpenAI | [platform.openai.com](https://platform.openai.com) |
| Anthropic | [console.anthropic.com](https://console.anthropic.com) |
| xAI | [x.ai](https://x.ai) |

### Supported Languages

Available languages depend on the model. Parakeet v3 supports 25 EU languages; Whisper models support ~100 languages. The full curated language list in the UI includes: Arabic, Bulgarian, Chinese, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hebrew, Hindi, Hungarian, Indonesian, Italian, Japanese, Korean, Latvian, Lithuanian, Malay, Maltese, Norwegian, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish, Thai, Turkish, Ukrainian, Vietnamese

### Supported Audio Formats (File Transcription)

MP3, WAV, M4A

---

## Getting Help

If you need additional assistance:

- **Email**: hello@yapper.to
- **Website**: [yapper.to](https://yapper.to)
- **Changelog**: [yapper.to/changelog](https://yapper.to/changelog)

---

*Yapper - Voice to text, faster than typing.*
