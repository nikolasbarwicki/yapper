import Foundation

/// Storage for API keys using UserDefaults
/// Note: For a local-only app, UserDefaults is sufficient and avoids Keychain permission prompts
final class APIKeyStorage: @unchecked Sendable {
    static let shared = APIKeyStorage()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "com.yapper.apikey."

    private init() {}

    /// Saves a key to UserDefaults
    /// - Parameters:
    ///   - key: The secret key to store
    ///   - account: The account identifier (e.g., "gemini")
    func save(key: String, forAccount account: String) {
        defaults.set(key, forKey: keyPrefix + account)
    }

    /// Retrieves a key from UserDefaults
    /// - Parameter account: The account identifier
    /// - Returns: The stored key, or nil if not found
    func retrieve(forAccount account: String) -> String? {
        defaults.string(forKey: keyPrefix + account)
    }

    /// Deletes a key from UserDefaults
    /// - Parameter account: The account identifier
    func delete(forAccount account: String) {
        defaults.removeObject(forKey: keyPrefix + account)
    }

    /// Checks if a key exists
    /// - Parameter account: The account identifier
    /// - Returns: True if a key exists for the account
    func exists(forAccount account: String) -> Bool {
        retrieve(forAccount: account) != nil
    }
}

// MARK: - Account Constants

extension APIKeyStorage {
    /// Account identifier for Gemini API key
    static let geminiAccount = "gemini"

    /// Account identifier for OpenAI API key
    static let openaiAccount = "openai"

    /// Account identifier for Anthropic API key
    static let anthropicAccount = "anthropic"

    /// Account identifier for xAI API key
    static let xaiAccount = "xai"
}
