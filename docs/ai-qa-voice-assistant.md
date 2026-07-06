# AI Q&A — Voice Assistant Mode

## Overview

Yapper now includes a built-in voice assistant. Say **"Hey Yapper"** followed by any question, and get an AI-generated answer displayed in a floating panel — without leaving the app you're working in.

This feature turns Yapper from a pure speech-to-text tool into a contextual voice assistant for quick questions, eliminating the need to switch to a browser or open a separate AI chat.

## How It Works

### Activation

1. Press the **recording hotkey** (default: `Option+Space`) from any app
2. Say **"Hey Yapper,** followed by your question"
   _Example: "Hey Yapper, how do I center a div with flexbox?"_
3. Stop recording (release the key or press again)

### What Happens Next

1. Yapper transcribes your speech as usual
2. The transcription is checked for the **"Hey Yapper"** prefix (case-insensitive)
3. If detected, the prefix is stripped and the remainder becomes the question
4. The overlay pill transitions to **purple** ("Thinking...")
5. The pill expands into a **floating Q&A card** showing:
   - Your original question (dimmed, at the top)
   - The LLM answer streaming in real-time below
6. Once streaming completes, the card turns **green** ("Answer Ready")
7. Click **Copy** to copy the answer to clipboard, or press **Escape** to dismiss

### Detection Rules

The trigger phrase **"Hey Yapper"** is matched with these rules:

- **Case-insensitive**: "hey yapper", "Hey Yapper", "HEY YAPPER" all work
- **Punctuation-tolerant**: "Hey Yapper," / "Hey Yapper:" / "Hey Yapper." are all stripped
- **LLM required**: If no LLM provider is configured, the phrase is treated as normal dictation (no silent failure)
- **Non-empty question required**: Saying just "Hey Yapper" with nothing after falls through to normal dictation

### Fuzzy Wake-Phrase Matching (v2.0.0)

Speech-to-text engines frequently misrecognize "Hey Yapper." To handle this, `detectHeyYapper(in:)` iterates **35+ regex patterns** organized by category. All matching is case-insensitive.

| Category | Recognized variants |
|----------|-------------------|
| **Canonical** | `hey yapper` |
| **Vowel/consonant swaps** | yaper, yappar, yappor, yappur, yepper, yeper, yipper, yopper, yupper |
| **Missing leading Y** | apper, upper |
| **Y to other consonant swaps** | rapper, japper, napper, dapper, tapper, zapper, jabber, yabber |
| **Plural/suffix drift** | yappers, "yap per", "yap her", "yap" |
| **"Hey" variants** | hay, "hey a yapper", "a yapper", hei |
| **Merged tokens** | heyyapper |

If "Hey Yapper" is not being recognized, try speaking clearly with a brief pause after "Hey Yapper" before your question.

### Post-Transcription Routing Priority

After transcription completes, Yapper checks for special modes in this order:

1. **AI Transform** — if text was selected before recording, the spoken instruction triggers a text rewrite
2. **AI Q&A** — if the transcription matches a "Hey Yapper" wake phrase, the remainder is sent as a question
3. **Normal Dictation** — the transcribed text is typed into the active app

### Q&A Panel

The floating panel displays:

| Section | Description |
|---------|-------------|
| **Header** | Dynamic label: **"Thinking..."** (purple, while streaming) or **"Answer Ready"** (green, when done), with a speech-bubble icon and a Copy button |
| **Question bar** | Your original question displayed in a dimmed bar with a `?` icon, truncated to max 3 lines |
| **Error banner** | Shown only if the LLM stream encountered an error (partial results are still displayed) |
| **Answer body** | Scrollable area with the LLM response rendered as **Markdown** (headings, bold, italic, code blocks, lists, tables, blockquotes). Auto-scrolls during streaming. The copy button copies raw Markdown text. |
| **Footer** | "Press Esc to cancel" during streaming, "Press Esc to dismiss" when complete |

### Keyboard Shortcuts

| Key | During Streaming | After Complete |
|-----|-----------------|----------------|
| **Escape** | Cancel the LLM request | Dismiss the panel |
| **Recording hotkey** | Blocked (ignored) | Blocked until dismissed |

## Requirements

- An **LLM provider must be configured** in Settings → AI (Gemini, OpenAI, Anthropic, or xAI)
- If no provider is configured, "Hey Yapper" is treated as normal dictation text

## Technical Details

### Architecture

The feature reuses the shared AI response streaming infrastructure that was built for AI Transform mode. Both features share:

- **`AppState.aiResponseText`** — the streamed response text
- **`AppState.isAIResponseStreaming`** — streaming progress flag
- **`AppState.aiResponseError`** — error state
- **`AppState.dismissAIResponse()`** — resets all response state on dismiss

Shared streaming state machine methods (parameterized by recording state so both Transform and Q&A can use them):

- **`startAIResponseStreaming(recordingState:)`** — transitions to the streaming state
- **`appendAIResponseToken(_:)`** — appends a token to `aiResponseText`
- **`completeAIResponseStream(recordingState:)`** — marks streaming complete, transitions to result state
- **`failAIResponseStream(_:resultState:errorPrefix:)`** — sets `aiResponseError` and transitions to error result state

### Renamed State Properties (v2.0.0)

In v2.0.0, the previously AI-Transform-specific streaming state was generalized to support both Transform and Q&A modes:

| Old name (v1.x) | New name (v2.0.0) |
|------------------|-------------------|
| `AppState.transformResult` | `AppState.aiResponseText` |
| `AppState.transformStreamError` | `AppState.aiResponseError` |
| `AppState.isTransformStreaming` | `AppState.isAIResponseStreaming` |
| `AppState.dismissTransformResult()` | `AppState.dismissAIResponse()` |
| `OverlayDisplayState.transformResultCard` | `OverlayDisplayState.aiResponseCard` |
| `OverlayDisplayState.isTransformCard` | `OverlayDisplayState.isAIResponseCard` |

### OverlayDisplayState Cases

| Case | Color | When |
|------|-------|------|
| `.aiQA` | Purple | LLM is streaming the answer |
| `.aiQAResult(hasError: false)` | Green | Answer complete, ready to copy |
| `.aiQAResult(hasError: true)` | Orange | Stream failed (partial answer may be shown) |

### New Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `InteractionMode.aiQA(question:)` | `AppState.swift` | New interaction mode case carrying the extracted question |
| `RecordingState.aiQA` / `.aiQAResult` | `AppState.swift` | New states for the Q&A streaming and result phases |
| `detectHeyYapper(in:)` | `AppDelegate.swift` | Regex-based prefix detection, returns stripped question or nil |
| `handleAIQA(question:recordingDuration:language:)` | `AppDelegate.swift` | Orchestrates the Q&A streaming flow |
| `LLMService.qaStream(question:)` | `LLMService.swift` | Constructs the voice-assistant system prompt and returns a token stream |
| Q&A card UI | `OverlayWindow.swift` | Question display bar, Q&A-specific icon and labels |

### Markdown Rendering (v2.0.0)

AI responses are rendered with full Markdown formatting via the MarkdownUI library. Supported elements include headings, bold, italic, inline code, code blocks (with horizontal scroll), lists, tables, and blockquotes. The theme adapts to macOS light/dark appearance automatically via `Theme.yapperOverlay(for: ColorScheme)`. The copy button always copies the raw Markdown source text.

### Flow Diagram

```
Recording → Transcription → "Hey Yapper" detected?
                                  │
                            ┌─────┴─────┐
                            │ Yes        │ No
                            ▼            ▼
                     Strip prefix    Normal dictation
                            │        (type into app)
                            ▼
                  .aiQA state (purple pill)
                            │
                            ▼
                  LLM stream → tokens arrive
                            │
                            ▼
                  Expanded Q&A card (auto-scroll)
                            │
                            ▼
                  .aiQAResult (green, Copy button)
                            │
                      ┌─────┴─────┐
                      │ Copy      │ Escape
                      ▼           ▼
                  Clipboard    Dismiss → idle
```
