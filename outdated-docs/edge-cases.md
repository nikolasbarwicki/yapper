# Edge Cases & Error Handling

## Permission Errors

### Microphone Permission Denied

**Behavior**: Recording cannot start. Error message shown.

**Recovery**:
- App shows error in overlay
- User must grant permission in System Settings > Privacy > Microphone

### Accessibility Permission Not Granted

**Behavior**: Text injection fails silently, falls back to clipboard paste.

**Fallback flow**:
1. Copy text to clipboard
2. Simulate Cmd+V
3. Restore original clipboard after 0.5s

**User impact**: Text appears via paste instead of typing. Clipboard temporarily modified.

---

## Recording Errors

### No Audio Detected

**Trigger**: Recording stopped but WhisperKit returns empty text.

**Behavior**:
- If duration < 1 second: Treated as accidental trigger, silent dismiss
- If duration >= 1 second: Shows "No speech detected" error for 3 seconds (auto-dismiss)

### Cancel During Recording

**Trigger**: User presses Escape while recording.

**Behavior**:
- Audio buffer discarded
- No transcription attempted
- Overlay dismissed immediately
- Nothing saved to history

### Cancel During Processing

**Current behavior**: Cancel only works during `.recording` state. Pressing Escape during transcription or enhancement has no effect.

---

## Model Errors

### Model Not Loaded

**Trigger**: User presses hotkey before model finishes loading.

**Behavior**:
- Error shown: "Model still loading..."
- Recording does not start
- Menu bar shows yellow dot during loading

### Model Download Failure

**Trigger**: Network error during first-time model download.

**Behavior**:
- Error shown with message
- User can retry by changing model in settings

---

## AI Enhancement Errors

Supported providers: Gemini, OpenAI, Anthropic, xAI (Grok)

### API Key Not Configured

**Trigger**: AI enhancement enabled but no API key saved for selected provider.

**Behavior**: Enhancement silently skipped, original text used. Warning shown in settings.

### Invalid API Key

**Trigger**: HTTP 400/401 from any provider.

**Behavior**: Enhancement skipped, original text used. Error logged but not shown to user.

### Network Error / Rate Limit

**Trigger**: Network failure or HTTP 429 from any provider.

**Behavior**: Enhancement skipped, original text used. No user-visible error.

### Enhancement Returns Empty

**Trigger**: API returns successfully but with empty text.

**Behavior**: Original transcription used instead.

### Provider-Specific Notes

- **Gemini**: Uses `generativelanguage.googleapis.com` API
- **OpenAI**: Uses `api.openai.com/v1/chat/completions`
- **Anthropic**: Uses `api.anthropic.com/v1/messages` with `anthropic-version` header
- **xAI**: Uses `api.x.ai/v1/chat/completions` (OpenAI-compatible)

**Design principle**: AI enhancement should never block the core flow. Any failure falls back silently.

---

## Text Injection Errors

### No Focused Text Field

**Current behavior**: Text is typed anyway. May go nowhere or to wrong place.

### Special Characters

Unicode and emojis are handled via `UniCharCount` when standard key codes don't work.

---

## File Transcription Errors

### Unsupported Format

**Supported**: MP3, WAV, M4A only.

**Behavior**: Error shown listing supported formats.

### Corrupted File

**Behavior**: "Unable to read file" error with suggestion to try different file.

### Very Long Files

**Current behavior**: Processes entire file. May take very long for multi-hour recordings.

---

## History Errors

### History File Corruption

**Behavior**:
- Corrupted file backed up
- History starts fresh (empty)
- Error logged

### Disk Full

**Behavior**:
- Warning shown
- Current transcript kept in memory
- Retry on next save attempt

---

## State Machine Edge Cases

### Rapid Hotkey Presses

**Behavior**: State machine prevents invalid transitions.
- During `.processing` or `.enhancing`: Hotkey ignored
- During `.error`: Hotkey clears error and returns to idle

### App Quit During Recording

**Behavior**:
- Recording stopped
- Partial audio discarded
- History saved before exit

---

## Error Auto-Dismiss

All errors auto-dismiss after **3 seconds** and return to idle state.

---

## Graceful Degradation Summary

| Failure | Fallback |
|---------|----------|
| Accessibility denied | Clipboard paste |
| AI API error | Original text |
| AI API not configured | Skip enhancement |
| Model still loading | Error message, wait |
| Empty transcription | Brief error, no save |
| History save fails | Keep in memory |
