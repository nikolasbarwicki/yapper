# AI Transform Mode - Deep Dive

## Purpose

AI Transform is a new interaction mode that lets users select text in any application, record a voice instruction describing how to modify it, and receive a streaming AI-rewritten result in an overlay card. Unlike dictation (which transcribes and types), Transform reads the selection, transcribes a voice command, and sends both to the configured LLM for rewriting.

---

## User-Facing Behavior

- **Trigger**: Select text in any app, then press the recording hotkey
- **Detection**: App reads selected text via Accessibility API; if non-empty, enters AI Transform mode
- **Recording**: Overlay shows purple "AI Listening" pill with sparkle icon + waveform
- **Streaming Result**: LLM response streams token-by-token into an expanded 480x360 result card with Markdown rendering
- **Copy**: "Copy" button in card header copies result to clipboard with confirmation
- **Dismiss**: Press Escape to dismiss the result card and return to idle
- **Fallback**: If no text is selected, normal dictation mode proceeds as usual
- **Requires LLM**: If AI is not configured, shows error "AI Transform requires an API key"
- **Selection Limit**: Max ~10,000 characters to prevent oversized LLM payloads

---

## Public Interface

### AccessibilityReader

**Location**: `Yapper/Services/AccessibilityReader.swift` (NEW)

| Method/Property | Purpose |
|-----------------|---------|
| `readSelectedText() -> String?` | Read selected text from frontmost app via AX API |
| `maxSelectionLength: Int` | Static limit (10,000 chars) |

### LLMService (additions)

**Location**: `Yapper/Services/LLMService.swift`

| Method | Purpose |
|--------|---------|
| `transform(text:instruction:) async throws -> String` | Batch transform (non-streaming) |
| `transformStream(text:instruction:) -> AsyncThrowingStream<String, Error>` | Streaming transform |
| `resolveProvider() throws -> LLMProvider` | Internal: resolve active provider (refactored from `enhance()`) |

### LLMProvider Protocol (additions)

| Method | Purpose |
|--------|---------|
| `enhanceStream(text:prompt:) -> AsyncThrowingStream<String, Error>` | SSE streaming for all providers |

All four providers (Gemini, OpenAI, Anthropic, xAI) now implement native SSE streaming.

### TextInjector (additions)

**Location**: `Yapper/Services/TextInjector.swift`

| Method | Purpose |
|--------|---------|
| `deleteSelection() async throws` | Simulate Delete key to clear selected text |

---

## State & Data

### InteractionMode Enum (NEW)

**Location**: `Yapper/Models/AppState.swift`

```swift
enum InteractionMode: Equatable {
    case dictation
    case aiTransform(selectedText: String)
}
```

### New RecordingState Cases

| State | Status Text | Icon | Color |
|-------|-------------|------|-------|
| `.aiTransforming` | "Transforming..." | sparkles | Purple |
| `.aiTransformResult` | "Transform Complete" | sparkles | Green |

### AppState Properties (shared AI response infrastructure)

In v2.0, transform-specific state properties were renamed to shared names used by both Transform and Q&A modes:

| Property | Type | Persistence | Old Name (v1) |
|----------|------|-------------|---------------|
| `interactionMode` | `InteractionMode?` | Runtime only | N/A |
| `aiResponseText` | `String` | Runtime only | `transformResult` |
| `aiResponseError` | `String?` | Runtime only | `transformStreamError` |
| `isAIResponseStreaming` | `Bool` | Runtime only | `isTransformStreaming` |
| `canStartRecording` | `Bool` (computed) | N/A | N/A |

### AppState Methods (shared AI response infrastructure)

| Method | Purpose | Old Name (v1) |
|--------|---------|---------------|
| `startAITransforming()` | Enter `.aiTransforming` state | Same |
| `startAIResponseStreaming(recordingState:)` | Clear result, set streaming flag | `startAITransformStreaming()` |
| `appendAIResponseToken(_:)` | Append streamed token to result | `appendTransformToken(_:)` |
| `completeAIResponseStream(recordingState:)` | Finalize streaming | `completeAITransformStream()` |
| `failAIResponseStream(_:resultState:errorPrefix:)` | Handle stream error with partial result | `failAITransformStream(_:)` |
| `dismissAIResponse()` | Reset all AI state, return to idle | `dismissTransformResult()` |

---

## Flow

```
User selects text → presses hotkey
  → AccessibilityReader.readSelectedText()
  → if non-empty:
      → appState.interactionMode = .aiTransform(selectedText)
      → start recording (purple "AI Listening" pill)
  → release hotkey → stop recording
  → transcribe voice instruction (batch mode, no AI enhancement)
  → appState.startAITransformStreaming()
  → llmService.transformStream(text: selectedText, instruction: transcription)
  → stream tokens → appState.appendTransformToken()
  → appState.completeAITransformStream()
  → overlay shows result card (copy/dismiss)
  → Escape → appState.dismissTransformResult()
```

---

## Overlay UI Changes

### OverlayDisplayState (additions)

| State | Dot Color | Label | Old Name (v1) |
|-------|-----------|-------|---------------|
| `.aiRecording` | Purple | "AI Listening" | Same |
| `.aiTransforming` | Purple | "Transforming..." | Same |
| `.aiTransformResult(hasError:)` | Green / Orange | "Transform Complete" / "Partial Result" | Same |

Note: `OverlayDisplayState.transformResultCard` was renamed to `.aiResponseCard` and `isTransformCard` to `.isAIResponseCard` to support shared usage with Q&A mode.

### Transform Result Card

- **480x360px** (enlarged from 400x300 in v2.0) glassmorphism card with `ultraThinMaterial` background
- Corner radius: 18pt (DesignTokens.Radius.card)
- Header: status dot + sparkle icon + label + Copy button
- Error banner (orange, shown on partial failure)
- Scrollable text body with **Markdown rendering** (MarkdownUI) and auto-scroll during streaming
- Footer hint: "Press Esc to cancel" / "Press Esc to dismiss"
- Text is selectable
- Spring-based animation for pill-to-card expansion (response 0.35, damping 0.8)
- Dark/light mode support via DesignTokens color system

### Cursor-Anchored Positioning

New `positionAtCursorAnchored()` method stores the initial cursor position when the overlay first appears, then anchors the expanded card to that position when transitioning from pill to card (prevents the card from jumping when it grows).

---

## Streaming Implementation

### SSE Format by Provider

| Provider | Stream Endpoint | Event Format |
|----------|----------------|--------------|
| Gemini | `streamGenerateContent?alt=sse` | `data: {candidates[0].content.parts[0].text}` |
| OpenAI | `/chat/completions` + `stream: true` | `data: {choices[0].delta.content}` / `[DONE]` |
| Anthropic | `/messages` + `stream: true` | `event: content_block_delta` / `event: message_stop` |
| xAI | `/chat/completions` + `stream: true` | OpenAI-compatible format |

All use `URLSession.bytes(for:)` with SSE line parsing. Default protocol extension provides non-streaming fallback.

### Transform Prompt

```
You are a text transformation assistant. The user has selected text and given a voice instruction
for how to modify it. Apply the instruction to the text and return ONLY the transformed result.
Do not include any explanation, commentary, or additional text beyond the transformed result itself.

Voice instruction: {transcribed instruction}
```

---

## Edge Cases & Gotchas

| Scenario | Behavior |
|----------|----------|
| No text selected | Falls through to normal dictation |
| Password field focused | AccessibilityReader returns nil (skips AXSecureTextField) |
| AX call hangs | 200ms timeout, falls back to dictation |
| Selection > 10K chars | Error: "Selected text too long" |
| No LLM configured | Error: "AI Transform requires an API key" |
| Stream fails mid-way | Partial result shown with orange error banner |
| Empty LLM response | Error pill: "Transform failed: Empty response from API" |
| Hotkey during transform | Blocked — user must dismiss card first (Escape) |
| Cancel during streaming | `CancellationError` propagated, overlay dismissed |
| Auto-enhancement | Removed in v2.0 (voice instruction is never auto-enhanced) |

---

## Files

| File | Change | Purpose |
|------|--------|---------|
| `Services/AccessibilityReader.swift` | NEW | Read selected text via Accessibility API |
| `Models/AppState.swift` | Modified | InteractionMode, transform states, streaming properties |
| `App/AppDelegate.swift` | Modified | Selection detection, transform flow branching |
| `Services/LLMService.swift` | Modified | Streaming protocol, transform methods, provider refactor |
| `Services/TextInjector.swift` | Modified | deleteSelection() utility |
| `Views/OverlayWindow.swift` | Modified | Result card UI, AI recording indicator, anchored positioning |
| `Yapper.xcodeproj/project.pbxproj` | Modified | Added AccessibilityReader.swift to build |
