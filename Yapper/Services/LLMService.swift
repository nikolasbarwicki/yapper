import Foundation

// MARK: - LLM Provider Protocol

/// Protocol for LLM providers that can enhance text
protocol LLMProvider: Sendable {
    func enhance(text: String, prompt: String) async throws -> String
    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error>
}

extension LLMProvider {
    /// Default streaming implementation: falls back to non-streaming `enhance()` and yields the full result at once
    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.enhance(text: text, prompt: prompt)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Model Definitions

/// Available models for each provider
enum LLMModel: String, CaseIterable, Codable {
    // Gemini models
    case gemini31ProPreview = "gemini-3.1-pro-preview"
    case gemini3FlashPreview = "gemini-3-flash-preview"
    case gemini31FlashLitePreview = "gemini-3.1-flash-lite-preview"

    // OpenAI models
    case gpt54 = "gpt-5.4"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54Nano = "gpt-5.4-nano"

    // Anthropic models
    case claudeOpus46 = "claude-opus-4-6"
    case claudeSonnet46 = "claude-sonnet-4-6"
    case claudeHaiku45 = "claude-haiku-4-5"

    // xAI models
    case grok420NonReasoning = "grok-4.20-0309-non-reasoning"
    case grok41FastReasoning = "grok-4-1-fast-reasoning"
    case grok41FastNonReasoning = "grok-4-1-fast-non-reasoning"

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .gemini31ProPreview: return "Gemini 3.1 Pro Preview"
        case .gemini3FlashPreview: return "Gemini 3 Flash Preview"
        case .gemini31FlashLitePreview: return "Gemini 3.1 Flash Lite Preview"
        case .gpt54: return "GPT-5.4"
        case .gpt54Mini: return "GPT-5.4 Mini"
        case .gpt54Nano: return "GPT-5.4 Nano"
        case .claudeOpus46: return "Claude Opus 4.6"
        case .claudeSonnet46: return "Claude Sonnet 4.6"
        case .claudeHaiku45: return "Claude Haiku 4.5"
        case .grok420NonReasoning: return "Grok 4.20 Non-Reasoning"
        case .grok41FastReasoning: return "Grok 4.1 Fast Reasoning"
        case .grok41FastNonReasoning: return "Grok 4.1 Fast Non-Reasoning"
        }
    }

    /// Which provider this model belongs to
    var provider: LLMService.Provider {
        switch self {
        case .gemini31ProPreview, .gemini3FlashPreview, .gemini31FlashLitePreview: return .gemini
        case .gpt54, .gpt54Mini, .gpt54Nano: return .openai
        case .claudeOpus46, .claudeSonnet46, .claudeHaiku45: return .anthropic
        case .grok420NonReasoning, .grok41FastReasoning, .grok41FastNonReasoning: return .xai
        }
    }

    /// Models available for a specific provider
    static func models(for provider: LLMService.Provider) -> [LLMModel] {
        allCases.filter { $0.provider == provider }
    }

    /// Default model for a provider
    static func defaultModel(for provider: LLMService.Provider) -> LLMModel {
        switch provider {
        case .gemini: return .gemini3FlashPreview
        case .openai: return .gpt54Mini
        case .anthropic: return .claudeSonnet46
        case .xai: return .grok41FastNonReasoning
        }
    }
}

// MARK: - Gemini Provider

/// Gemini API implementation for text enhancement
final class GeminiProvider: LLMProvider, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(apiKey: String, model: LLMModel = .gemini3FlashPreview) {
        self.apiKey = apiKey
        self.model = model.rawValue
    }

    func enhance(text: String, prompt: String) async throws -> String {
        let endpoint = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL
        }

        // Build the full prompt with the text to enhance
        let fullPrompt = """
        \(prompt)

        Text to enhance:
        \"\"\"
        \(text)
        \"\"\"
        """

        // Create request body
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 8192
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 400:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 500...599:
            throw LLMError.serverError("Server error: \(httpResponse.statusCode)")
        default:
            throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"

                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: LLMError.invalidURL)
                        return
                    }

                    let fullPrompt = """
                        \(prompt)

                        Text to enhance:
                        \"\"\"
                        \(text)
                        \"\"\"
                        """

                    let requestBody: [String: Any] = [
                        "contents": [["parts": [["text": fullPrompt]]]],
                        "generationConfig": ["temperature": 0.1, "maxOutputTokens": 8192]
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = jsonData
                    request.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        switch httpResponse.statusCode {
                        case 400: continuation.finish(throwing: LLMError.invalidAPIKey)
                        case 429: continuation.finish(throwing: LLMError.rateLimited)
                        case 500...599: continuation.finish(throwing: LLMError.serverError("Server error: \(httpResponse.statusCode)"))
                        default: continuation.finish(throwing: LLMError.networkError("HTTP \(httpResponse.statusCode)"))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]],
                              let text = parts.first?["text"] as? String else { continue }
                        continuation.yield(text)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw LLMError.invalidResponse
        }

        // Clean up the response - remove any markdown code blocks if present
        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedText.isEmpty else {
            throw LLMError.emptyResponse
        }

        return cleanedText
    }
}

// MARK: - OpenAI Provider

/// OpenAI API implementation for text enhancement
final class OpenAIProvider: LLMProvider, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.openai.com/v1"

    init(apiKey: String, model: LLMModel = .gpt54Mini) {
        self.apiKey = apiKey
        self.model = model.rawValue
    }

    func enhance(text: String, prompt: String) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL
        }

        let fullPrompt = """
        \(prompt)

        Text to enhance:
        \"\"\"
        \(text)
        \"\"\"
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ],
            "temperature": 0.1,
            "max_tokens": 8192
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 500...599:
            throw LLMError.serverError("Server error: \(httpResponse.statusCode)")
        default:
            throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "\(baseURL)/chat/completions"

                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: LLMError.invalidURL)
                        return
                    }

                    let fullPrompt = """
                        \(prompt)

                        Text to enhance:
                        \"\"\"
                        \(text)
                        \"\"\"
                        """

                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": fullPrompt]],
                        "temperature": 0.1,
                        "max_tokens": 8192,
                        "stream": true
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = jsonData
                    request.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        switch httpResponse.statusCode {
                        case 401: continuation.finish(throwing: LLMError.invalidAPIKey)
                        case 429: continuation.finish(throwing: LLMError.rateLimited)
                        case 500...599: continuation.finish(throwing: LLMError.serverError("Server error: \(httpResponse.statusCode)"))
                        default: continuation.finish(throwing: LLMError.networkError("HTTP \(httpResponse.statusCode)"))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedText.isEmpty else {
            throw LLMError.emptyResponse
        }

        return cleanedText
    }
}

// MARK: - Anthropic Provider

/// Anthropic API implementation for text enhancement
final class AnthropicProvider: LLMProvider, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.anthropic.com/v1"

    init(apiKey: String, model: LLMModel = .claudeSonnet46) {
        self.apiKey = apiKey
        self.model = model.rawValue
    }

    func enhance(text: String, prompt: String) async throws -> String {
        let endpoint = "\(baseURL)/messages"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL
        }

        let fullPrompt = """
        \(prompt)

        Text to enhance:
        \"\"\"
        \(text)
        \"\"\"
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 500...599:
            throw LLMError.serverError("Server error: \(httpResponse.statusCode)")
        default:
            throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "\(baseURL)/messages"

                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: LLMError.invalidURL)
                        return
                    }

                    let fullPrompt = """
                        \(prompt)

                        Text to enhance:
                        \"\"\"
                        \(text)
                        \"\"\"
                        """

                    let requestBody: [String: Any] = [
                        "model": model,
                        "max_tokens": 8192,
                        "stream": true,
                        "messages": [["role": "user", "content": fullPrompt]]
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.httpBody = jsonData
                    request.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        switch httpResponse.statusCode {
                        case 401: continuation.finish(throwing: LLMError.invalidAPIKey)
                        case 429: continuation.finish(throwing: LLMError.rateLimited)
                        case 500...599: continuation.finish(throwing: LLMError.serverError("Server error: \(httpResponse.statusCode)"))
                        default: continuation.finish(throwing: LLMError.networkError("HTTP \(httpResponse.statusCode)"))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        // Anthropic SSE: lines prefixed with "event: " and "data: "
                        if line == "event: message_stop" { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              json["type"] as? String == "content_block_delta",
                              let delta = json["delta"] as? [String: Any],
                              let text = delta["text"] as? String else { continue }
                        continuation.yield(text)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw LLMError.invalidResponse
        }

        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedText.isEmpty else {
            throw LLMError.emptyResponse
        }

        return cleanedText
    }
}

// MARK: - xAI Provider

/// xAI (Grok) API implementation for text enhancement (OpenAI-compatible API)
final class XAIProvider: LLMProvider, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.x.ai/v1"

    init(apiKey: String, model: LLMModel = .grok41FastNonReasoning) {
        self.apiKey = apiKey
        self.model = model.rawValue
    }

    func enhance(text: String, prompt: String) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL
        }

        let fullPrompt = """
        \(prompt)

        Text to enhance:
        \"\"\"
        \(text)
        \"\"\"
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": fullPrompt]
            ],
            "temperature": 0.1,
            "max_tokens": 8192
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 500...599:
            throw LLMError.serverError("Server error: \(httpResponse.statusCode)")
        default:
            throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    func enhanceStream(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        // xAI uses OpenAI-compatible streaming API
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "\(baseURL)/chat/completions"

                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: LLMError.invalidURL)
                        return
                    }

                    let fullPrompt = """
                        \(prompt)

                        Text to enhance:
                        \"\"\"
                        \(text)
                        \"\"\"
                        """

                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": fullPrompt]],
                        "temperature": 0.1,
                        "max_tokens": 8192,
                        "stream": true
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = jsonData
                    request.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        switch httpResponse.statusCode {
                        case 401: continuation.finish(throwing: LLMError.invalidAPIKey)
                        case 429: continuation.finish(throwing: LLMError.rateLimited)
                        case 500...599: continuation.finish(throwing: LLMError.serverError("Server error: \(httpResponse.statusCode)"))
                        default: continuation.finish(throwing: LLMError.networkError("HTTP \(httpResponse.statusCode)"))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        // xAI uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedText.isEmpty else {
            throw LLMError.emptyResponse
        }

        return cleanedText
    }
}

// MARK: - LLM Service

/// Main service that coordinates LLM providers for text enhancement
@MainActor
final class LLMService {
    /// Available LLM providers
    enum Provider: String, CaseIterable, Codable {
        case gemini
        case openai
        case anthropic
        case xai

        /// Human-readable display name
        var displayName: String {
            switch self {
            case .gemini: return "Gemini"
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .xai: return "xAI (Grok)"
            }
        }

        /// URL to get an API key
        var apiKeyURL: URL {
            switch self {
            case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")!
            case .openai: return URL(string: "https://platform.openai.com/api-keys")!
            case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
            case .xai: return URL(string: "https://console.x.ai/")!
            }
        }
    }

    // Provider instances
    private var geminiProvider: GeminiProvider?
    private var openaiProvider: OpenAIProvider?
    private var anthropicProvider: AnthropicProvider?
    private var xaiProvider: XAIProvider?

    // Current active provider and model
    private var activeProvider: Provider?
    private var activeModel: LLMModel?

    /// Configure a provider with an API key and model
    /// - Parameters:
    ///   - provider: The provider to configure
    ///   - apiKey: The API key for the provider
    ///   - model: The model to use (defaults to provider's default model)
    func configure(provider: Provider, apiKey: String, model: LLMModel? = nil) {
        let selectedModel = model ?? LLMModel.defaultModel(for: provider)

        switch provider {
        case .gemini:
            geminiProvider = GeminiProvider(apiKey: apiKey, model: selectedModel)
        case .openai:
            openaiProvider = OpenAIProvider(apiKey: apiKey, model: selectedModel)
        case .anthropic:
            anthropicProvider = AnthropicProvider(apiKey: apiKey, model: selectedModel)
        case .xai:
            xaiProvider = XAIProvider(apiKey: apiKey, model: selectedModel)
        }
    }

    /// Set the active provider and model for enhancement
    /// - Parameters:
    ///   - provider: The provider to use
    ///   - model: The model to use
    func setActiveProvider(_ provider: Provider, model: LLMModel) {
        activeProvider = provider
        activeModel = model

        // Reconfigure the provider with the new model if API key exists
        if let apiKey = APIKeyStorage.shared.retrieve(forAccount: provider.storageAccount) {
            configure(provider: provider, apiKey: apiKey, model: model)
        }
    }

    /// Unconfigure a provider (remove its API key)
    /// - Parameter provider: The provider to unconfigure
    func unconfigure(provider: Provider) {
        switch provider {
        case .gemini:
            geminiProvider = nil
        case .openai:
            openaiProvider = nil
        case .anthropic:
            anthropicProvider = nil
        case .xai:
            xaiProvider = nil
        }

        // If this was the active provider, clear it
        if activeProvider == provider {
            activeProvider = nil
            activeModel = nil
        }
    }

    /// Check if any provider is configured
    /// - Returns: True if at least one provider is configured
    func isConfigured() -> Bool {
        geminiProvider != nil || openaiProvider != nil || anthropicProvider != nil || xaiProvider != nil
    }

    /// Check if a specific provider is configured
    /// - Parameter provider: The provider to check
    /// - Returns: True if the provider is configured
    func isConfigured(provider: Provider) -> Bool {
        switch provider {
        case .gemini:
            return geminiProvider != nil
        case .openai:
            return openaiProvider != nil
        case .anthropic:
            return anthropicProvider != nil
        case .xai:
            return xaiProvider != nil
        }
    }

    /// Get the active provider
    var currentProvider: Provider? {
        activeProvider
    }

    /// Get the active model
    var currentModel: LLMModel? {
        activeModel
    }

    /// Resolve the currently active provider instance.
    /// - Returns: The configured LLMProvider
    /// - Throws: `LLMError.notConfigured` if no provider is set or its API key is missing
    private func resolveProvider() throws -> LLMProvider {
        guard let provider = activeProvider else {
            throw LLMError.notConfigured
        }

        switch provider {
        case .gemini:
            guard let p = geminiProvider else { throw LLMError.notConfigured }
            return p
        case .openai:
            guard let p = openaiProvider else { throw LLMError.notConfigured }
            return p
        case .anthropic:
            guard let p = anthropicProvider else { throw LLMError.notConfigured }
            return p
        case .xai:
            guard let p = xaiProvider else { throw LLMError.notConfigured }
            return p
        }
    }

    /// Transform text using a voice instruction.
    /// Used by AI Transform mode — the user selects text, records a voice instruction,
    /// and the LLM rewrites the text according to the instruction.
    ///
    /// - Parameters:
    ///   - text: The selected text to transform
    ///   - instruction: The transcribed voice instruction describing how to transform it
    /// - Returns: The transformed text
    func transform(text: String, instruction: String) async throws -> String {
        let provider = try resolveProvider()

        let prompt = """
            You are a text transformation assistant. The user has selected text and given a voice instruction \
            for how to modify it. Apply the instruction to the text and return ONLY the transformed result. \
            Do not include any explanation, commentary, or additional text beyond the transformed result itself.

            Voice instruction: \(instruction)
            """

        let result = try await provider.enhance(text: text, prompt: prompt)
        // Only trim whitespace — do NOT strip ``` (the provider's parseResponse does that,
        // but the result here is already cleaned by the provider). In practice this is
        // acceptable since providers strip bare ``` delimiters but preserve inline formatting.
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streaming version of `transform()` — returns an AsyncThrowingStream of token chunks.
    /// The caller accumulates tokens and displays them in real-time in the overlay.
    func transformStream(text: String, instruction: String) -> AsyncThrowingStream<String, Error> {
        guard let provider = try? resolveProvider() else {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.notConfigured) }
        }

        let prompt = """
            You are a text transformation assistant. The user has selected text and given a voice instruction \
            for how to modify it. Apply the instruction to the text and return ONLY the transformed result. \
            Do not include any explanation, commentary, or additional text beyond the transformed result itself.

            Voice instruction: \(instruction)
            """

        return provider.enhanceStream(text: text, prompt: prompt)
    }

    /// Streaming Q&A — sends the user's question to the LLM with a voice-assistant prompt
    /// and returns an AsyncThrowingStream of answer token chunks.
    /// Used by AI Q&A mode ("Hey Yapper, [question]").
    func qaStream(question: String) -> AsyncThrowingStream<String, Error> {
        guard let provider = try? resolveProvider() else {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.notConfigured) }
        }

        let prompt = """
            You are a helpful voice assistant called Yapper. The user asked a question by voice. \
            Provide a clear, concise, and accurate answer. Be direct — do not restate the question. \
            If the question is ambiguous, give the most likely interpretation. \
            Keep answers under 200 words unless the question requires more detail.
            """

        return provider.enhanceStream(text: question, prompt: prompt)
    }

    /// Update the enhancement prompt
    /// - Parameter prompt: The new prompt to use
    /// Validate an API key by making a test request
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - provider: The provider to validate against
    /// - Returns: Result indicating success, invalid key, or network error
    func validateAPIKey(_ apiKey: String, for provider: Provider) async -> APIKeyValidationResult {
        let testProvider: LLMProvider

        switch provider {
        case .gemini:
            testProvider = GeminiProvider(apiKey: apiKey)
        case .openai:
            testProvider = OpenAIProvider(apiKey: apiKey)
        case .anthropic:
            testProvider = AnthropicProvider(apiKey: apiKey)
        case .xai:
            testProvider = XAIProvider(apiKey: apiKey)
        }

        do {
            _ = try await testProvider.enhance(text: "test", prompt: "Reply with 'ok'")
            return .valid
        } catch LLMError.invalidAPIKey {
            return .invalid
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}

// MARK: - Provider Storage Account

extension LLMService.Provider {
    /// Storage account identifier for API key storage
    var storageAccount: String {
        switch self {
        case .gemini: return APIKeyStorage.geminiAccount
        case .openai: return APIKeyStorage.openaiAccount
        case .anthropic: return APIKeyStorage.anthropicAccount
        case .xai: return APIKeyStorage.xaiAccount
        }
    }
}

// MARK: - API Key Validation Result

enum APIKeyValidationResult {
    case valid
    case invalid
    case networkError(String)
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case notConfigured
    case invalidAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case networkError(String)
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LLM service is not configured"
        case .invalidAPIKey:
            return "Invalid API key"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .emptyResponse:
            return "Empty response from API"
        case .networkError(let message):
            return "Network error: \(message)"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
