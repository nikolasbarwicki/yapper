import Foundation

// MARK: - Notification Names

/// Centralized notification names for inter-component communication.
/// All notifications used by the app are defined here for easy discovery.
extension Notification.Name {
    /// Toggle recording on/off (triggered from menu bar)
    static let toggleRecording = Notification.Name("com.yapper.toggleRecording")

    /// Menu bar icon/items need visual update
    static let menuBarNeedsUpdate = Notification.Name("com.yapper.menuBarNeedsUpdate")

    /// Keyboard shortcuts were changed in settings
    static let shortcutsChanged = Notification.Name("com.yapper.shortcutsChanged")

    /// API key was added/changed/removed
    static let apiKeyChanged = Notification.Name("com.yapper.apiKeyChanged")

    /// LLM provider or model was changed
    static let llmProviderChanged = Notification.Name("com.yapper.llmProviderChanged")

    /// Permissions should be refreshed (e.g., when Settings window becomes active)
    static let permissionsNeedRefresh = Notification.Name("com.yapper.permissionsNeedRefresh")

    /// Speech model selection changed (triggers model reload)
    static let modelSelectionChanged = Notification.Name("com.yapper.modelSelectionChanged")

    /// Model download was cancelled by the user
    static let modelDownloadCancelled = Notification.Name("com.yapper.modelDownloadCancelled")

    /// All downloaded models were cleared from disk
    static let modelsCleared = Notification.Name("com.yapper.modelsCleared")

    /// Language toggle shortcut was changed in settings
    static let languageToggleShortcutChanged = Notification.Name("com.yapper.languageToggleShortcutChanged")
}
