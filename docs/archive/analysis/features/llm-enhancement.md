# LLM AI Services - Deep Dive

## Purpose

The LLM AI Services feature provides user-initiated AI capabilities via four LLM providers (Gemini, OpenAI, Anthropic, xAI). In v2.0, AI is strictly user-initiated through two modes:

1. **AI Transform** - Voice-driven text rewriting (select text + speak instruction)
2. **AI Q&A** - Voice assistant ("Hey Yapper" + question)

The v1.x auto-enhancement feature (automatic post-transcription processing via `enhance(text:)`) has been removed entirely.

---

## User-Facing Behavior

- **AI Transform**: Select text in any app, press recording hotkey, speak instruction. Result streams into overlay card.
- **AI Q&A**: Say "Hey Yapper" followed by a question during recording. Answer streams into overlay card.
- **Provider Selection**: Choose from Gemini, OpenAI, Anthropic, or xAI (Grok) in Settings > AI
- **Model Selection**: Select specific model variants per provider
- **API Key Management**: Enter, change, or remove API keys with inline validation feedback
- **No auto-enhancement**: Transcriptions are never automatically processed by AI. The "Enable AI Enhancement" toggle and custom prompt editor are gone.

---

## Public Interface

### LLMService

**Location**: `Yapper/Services/LLMService.swift`

| Method/Property | Purpose |
|-----------------|---------|
| `configure(provider:apiKey:model:)` | Configure a provider with credentials |
| `unconfigure(provider:)` | Remove a provider's configuration |
| `setActiveProvider(_:model:)` | Set which provider to use |
| `transform(text:instruction:) async throws -> String` | Batch transform (non-streaming) |
| `transformStream(text:instruction:) -> AsyncThrowingStream<String, Error>` | Streaming transform |
| `qaStream(question:) -> AsyncThrowingStream<String, Error>` | Streaming Q&A |
| `resolveProvider() throws -> LLMProvider` | Internal: resolve active provider |
| `isConfigured() -> Bool` | Check if any provider is configured |
| `isConfigured(provider:) -> Bool` | Check if specific provider is configured |
| `validateAPIKey(_:for:) async -> APIKeyValidationResult` | Validate API key |
| `currentProvider: Provider?` | Currently active provider |
| `currentModel: LLMModel?` | Currently active model |

### LLMProvider Protocol

```swift
protocol LLMProvider {
    func enhance(text: String, prompt: String) async throws -> String
    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error>
}
```

All four providers (Gemini, OpenAI, Anthropic, xAI) implement native SSE streaming via `enhanceStream()`.

### Removed API (v1.x)

The following have been removed in v2.0:
- `LLMService.enhance(text:)` - auto-enhancement entry point
- `LLMService.setPrompt(_:)` - custom prompt setter
- `LLMService.getPrompt()` - custom prompt getter
- `LLMService.defaultPrompt` - static default prompt text
- `Notifications.aiPromptChanged` - prompt change notification
- `RecordingState.enhancing` - enhancement state
- `OverlayDisplayState.enhancing` - enhancement overlay state

### LLMModel Enum

| Method | Purpose |
|--------|---------|
| `models(for:) -> [LLMModel]` | Get available models for a provider |
| `defaultModel(for:) -> LLMModel` | Get default model for a provider |
| `displayName: String` | Human-readable model name |
| `provider: LLMService.Provider` | Which provider owns this model |

### APIKeyStorage

**Location**: `Yapper/Services/APIKeyStorage.swift`

| Method | Purpose |
|--------|---------|
| `save(key:forAccount:)` | Store API key in UserDefaults |
| `retrieve(forAccount:) -> String?` | Retrieve stored API key |
| `delete(forAccount:)` | Remove stored API key |
| `exists(forAccount:) -> Bool` | Check if key exists |

---

## Notifications

| Notification | Trigger | Handler |
|--------------|---------|---------|
| `.apiKeyChanged` | API key saved/deleted | Reconfigures LLMService |
| `.llmProviderChanged` | Provider/model changes | Reconfigures LLMService |

Note: `.aiPromptChanged` has been removed.

---

## Implementation Notes

### Multi-Provider Architecture

Protocol-based provider pattern with streaming support:

```swift
protocol LLMProvider {
    func enhance(text: String, prompt: String) async throws -> String
    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error>
}
```

Four implementations:
1. `GeminiProvider` - Google Gemini API (SSE via `streamGenerateContent?alt=sse`)
2. `OpenAIProvider` - OpenAI Chat API (SSE via `stream: true`)
3. `AnthropicProvider` - Anthropic Messages API (SSE via `stream: true`, event-based)
4. `XAIProvider` - xAI Grok API (OpenAI-compatible SSE)

All use `URLSession.bytes(for:)` with SSE line parsing. Default protocol extension provides non-streaming fallback.

### API Request Format by Provider

| Provider | Endpoint | Auth Header | API Version |
|----------|----------|-------------|-------------|
| Gemini | `/models/{model}:generateContent?key=` | Query param | None |
| OpenAI | `/v1/chat/completions` | `Authorization: Bearer` | None |
| Anthropic | `/v1/messages` | `x-api-key` | `anthropic-version: 2023-06-01` |
| xAI | `/v1/chat/completions` | `Authorization: Bearer` | None |

### SSE Streaming Format by Provider

| Provider | Stream Endpoint | Event Format |
|----------|----------------|--------------|
| Gemini | `streamGenerateContent?alt=sse` | `data: {candidates[0].content.parts[0].text}` |
| OpenAI | `/chat/completions` + `stream: true` | `data: {choices[0].delta.content}` / `[DONE]` |
| Anthropic | `/messages` + `stream: true` | `event: content_block_delta` / `event: message_stop` |
| xAI | `/chat/completions` + `stream: true` | OpenAI-compatible format |

### Request Configuration

All providers:
- `temperature: 0.1` (low creativity)
- `maxOutputTokens: 8192`
- `timeoutInterval: 30` seconds

### Response Parsing (batch fallback)

| Provider | Response Path |
|----------|---------------|
| Gemini | `candidates[0].content.parts[0].text` |
| OpenAI | `choices[0].message.content` |
| Anthropic | `content[0].text` |
| xAI | `choices[0].message.content` |

Response cleanup:
1. Trim whitespace
2. Remove markdown code blocks
3. Check for empty response

### Transform Prompt

```
You are a text transformation assistant. The user has selected text and given a voice instruction
for how to modify it. Apply the instruction to the text and return ONLY the transformed result.
Do not include any explanation, commentary, or additional text beyond the transformed result itself.

Voice instruction: {transcribed instruction}
```

### Q&A Prompt

System prompt: "You are a helpful voice assistant called Yapper..."

### Post-Transcription Routing

Priority order:
1. **AI Transform** - if `interactionMode == .aiTransform(selectedText:)` → `transformStream()`
2. **AI Q&A** - if "Hey Yapper" detected in transcription → `qaStream(question:)`
3. **Normal Dictation** - text injected into focused app

### Shared Streaming Infrastructure

Both Transform and Q&A share:
- `AppState.aiResponseText` - accumulated response text
- `AppState.aiResponseError` - error state
- `AppState.isAIResponseStreaming` - streaming flag
- `startAIResponseStreaming(recordingState:)` - begin streaming
- `appendAIResponseToken(_:)` - append token
- `completeAIResponseStream(recordingState:)` - finalize
- `failAIResponseStream(_:resultState:errorPrefix:)` - handle errors
- `dismissAIResponse()` - reset all AI state

### API Key Storage

Keys stored in UserDefaults (not Keychain) with prefix `com.yapper.apikey.{provider}`:
- `com.yapper.apikey.gemini`
- `com.yapper.apikey.openai`
- `com.yapper.apikey.anthropic`
- `com.yapper.apikey.xai`

### Internal Refactoring

`resolveProvider()` extracts duplicated provider resolution logic previously in `enhance()`.

---

## State & Data

### AppState Properties

| Property | Type | Persistence |
|----------|------|-------------|
| `selectedLLMProvider` | `LLMService.Provider` | UserDefaults |
| `selectedLLMModel` | `LLMModel` | UserDefaults |
| `aiResponseText` | `String` | Runtime only |
| `aiResponseError` | `String?` | Runtime only |
| `isAIResponseStreaming` | `Bool` | Runtime only |

### Removed AppState Properties (v1.x)

| Property | Status |
|----------|--------|
| `isAIEnhancementEnabled` | Removed (orphaned UserDefaults key) |
| `isEnhancing` | Removed |
| `aiEnhancementPrompt` | Removed (orphaned UserDefaults key) |

---

## Edge Cases & Gotchas

### Error Handling

| Error | Condition |
|-------|-----------|
| `LLMError.notConfigured` | No provider configured |
| `LLMError.invalidAPIKey` | 400/401 response |
| `LLMError.rateLimited` | 429 response |
| `LLMError.serverError(String)` | 5xx response |
| `LLMError.emptyResponse` | Empty text returned |
| `LLMError.networkError(String)` | Network failure |

### Stream Failure

Partial results are preserved with an orange error banner. Users see whatever was streamed before the failure.

### Provider/Model Consistency

When changing providers, model auto-switches to provider's default if incompatible.

### Gemini 400 = Invalid Key

Gemini returns HTTP 400 for invalid API keys (not 401).

### Timeout

All providers have 30-second timeout.

### No Retry

Failed requests are not retried.

---

## Technical Debt

1. **API Keys in UserDefaults**: Less secure than Keychain
2. **`@unchecked Sendable` on APIKeyStorage**: Bypasses Swift concurrency checking
3. **Hardcoded anthropic-version Header**: May become stale
4. **No Cost Estimation**: No feedback about API costs
5. **Model List Hardcoded**: Requires code changes to add new models
6. **No Request Caching**: Identical requests make repeated API calls

---

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `Yapper/Services/LLMService.swift` | ~750 | Multi-provider abstraction (transform, Q&A, streaming) |
| `Yapper/Services/APIKeyStorage.swift` | 57 | API key persistence |
| `Yapper/Views/AIEnhancementSettingsView.swift` | ~386 | Settings UI (Transform + Q&A mode descriptions) |
