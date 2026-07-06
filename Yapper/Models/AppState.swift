import AppKit
import Foundation
import SwiftUI

// MARK: - Interaction Mode

/// Determines how the current recording session will be used.
/// - `.dictation`: Normal mode — voice is transcribed and typed into the focused field.
/// - `.aiTransform(selectedText:)`: Transform mode — voice becomes an AI instruction
///   to modify the selected text, and the result replaces the selection.
/// - `.aiQA(question:)`: Q&A mode — "Hey Yapper" detected, question sent to LLM,
///   answer displayed in floating panel.
enum InteractionMode: Equatable {
    case dictation
    case aiTransform(selectedText: String)
    case aiQA(question: String)

    var isAITransform: Bool {
        if case .aiTransform = self { return true }
        return false
    }

    var isAIQA: Bool {
        if case .aiQA = self { return true }
        return false
    }
}

// MARK: - Recording State Enum
// In Swift, enums are much more powerful than TypeScript enums.
// They can have associated values (like discriminated unions in TS).

/// Represents the current state of the recording/transcription pipeline.
/// Think of this like a TypeScript discriminated union:
/// type RecordingState = { type: 'idle' } | { type: 'recording' } | { type: 'processing' } | ...
enum RecordingState: Equatable {
    case idle                           // Ready to record
    case recording                      // Actively recording audio
    case processing                     // Transcribing audio
    case aiTransforming                 // AI transform in progress (LLM rewriting selected text)
    case aiTransformResult              // Transform result displayed in overlay for user to copy/dismiss
    case aiQA                           // AI Q&A in progress (LLM answering question)
    case aiQAResult                     // Q&A answer displayed in overlay for user to copy/dismiss
    case error(message: String)         // Something went wrong

    // SWIFT TIP: Computed property - like a getter in TypeScript
    // This runs every time you access `isRecording`
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .aiTransforming:
            return "Transforming..."
        case .aiTransformResult:
            return "Transform Complete"
        case .aiQA:
            return "Answering..."
        case .aiQAResult:
            return "Answer Ready"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var statusIcon: String {
        switch self {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .processing:
            return "brain.head.profile"
        case .aiTransforming, .aiTransformResult, .aiQA, .aiQAResult:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - App State (Observable)

/// The central state object for the entire app.
///
/// SWIFT/SWIFTUI CONCEPT: @Observable (new in macOS 14)
/// This is similar to MobX or Zustand in the React world.
/// Any SwiftUI view that reads a property will automatically re-render when it changes.
///
/// OLD WAY (pre-macOS 14): Used `ObservableObject` + `@Published` properties
/// NEW WAY (macOS 14+): Just use `@Observable` macro - cleaner!
@Observable
@MainActor
final class AppState {

    // MARK: - Recording State
    var recordingState: RecordingState = .idle {
        didSet { notifyMenuBarUpdate() }
    }

    // Audio level for visualization (0.0 to 1.0)
    var audioLevel: Float = 0.0

    // MARK: - Transcription
    var lastTranscription: String = ""

    // MARK: - Settings (persisted)
    // @AppStorage is like localStorage in the browser - persists across app launches
    // We can't use @AppStorage directly in @Observable, so we'll handle this differently
    var selectedModel: String = "parakeet:tdt-0.6b-v3"
    var selectedLanguage: String = "en"  // Language code for transcription (e.g., "en", "es", "fr")
    var customVocabulary: [String] = []  // Custom words/phrases to help Whisper recognize

    // MARK: - Language Settings (persisted)
    var primaryLanguage: String = "en"
    var secondaryLanguage: String? = nil

    // MARK: - Language Toggle (runtime-only, resets on launch)
    var isUsingSecondaryLanguage: Bool = false

    /// The language currently in use — secondary if toggled and available, otherwise primary
    var activeLanguage: String {
        if isUsingSecondaryLanguage, let secondary = secondaryLanguage {
            return secondary
        }
        return primaryLanguage
    }

    // MARK: - Language Switch Display State
    var languageSwitchDisplayText: String = ""

    // MARK: - Keyboard Shortcuts (persisted)
    var recordingToggleShortcut: KeyboardShortcut = .defaultRecordingToggle
    var cancelRecordingShortcut: KeyboardShortcut = .defaultCancelRecording
    var languageToggleShortcut: KeyboardShortcut = .defaultLanguageToggle
    var autoTypeToggleShortcut: KeyboardShortcut = .defaultAutoTypeToggle

    // MARK: - Sound Feedback (persisted)
    var soundFeedbackEnabled: Bool = false

    // MARK: - Overlay Position (persisted)
    var overlayPositionFixed: Bool = false  // false = cursor-following (default), true = fixed top-center

    // MARK: - Auto-type (persisted)
    var autoTypeEnabled: Bool = true  // true = type transcription into focused app (default)

    // MARK: - History Settings (persisted)
    var historyRetentionDays: Int = 90  // Default: 90 days

    // MARK: - Microphone Selection (persisted)
    var selectedMicrophoneUID: String? = nil  // nil = system default input device
    var availableInputDevices: [AudioInputDevice] = []
    /// Runtime reference to the device manager (set by AppDelegate, used by SettingsView for level metering)
    var audioDeviceManager: AudioDeviceManager?
    /// Set to true when the selected microphone was unavailable and recording fell back to system default
    var microphoneFellBack: Bool = false

    // MARK: - AI Settings (persisted)
    var selectedLLMProvider: LLMService.Provider = .gemini
    var selectedLLMModel: LLMModel = .gemini3FlashPreview

    // MARK: - Interaction Mode (runtime-only)
    var interactionMode: InteractionMode? = nil

    // MARK: - AI Response Streaming State (runtime-only)
    // Shared by AI Transform and AI Q&A — both stream LLM responses into the overlay card
    var aiResponseText: String = ""
    var aiResponseError: String? = nil
    var isAIResponseStreaming: Bool = false

    // MARK: - Model Loading State
    var isModelLoaded: Bool = false {
        didSet { notifyMenuBarUpdate() }
    }
    var isLoadingModel: Bool = true  // True while any model loading is in progress
    var modelLoadingProgress: Double = 0.0
    var isModelDownloading: Bool = true  // True during download, false during load/prewarm phase
    var loadedModel: String? = nil  // The model that is actually loaded (nil if none)

    // MARK: - Permissions
    var hasMicrophonePermission: Bool = false
    var hasAccessibilityPermission: Bool = false

    /// Returns true only when all required permissions are granted
    var allPermissionsGranted: Bool {
        hasMicrophonePermission && hasAccessibilityPermission
    }

    // MARK: - UI State
    var showOverlay: Bool = false
    var showCompletedIndicator: Bool = false {  // Brief green indicator after successful transcription
        didSet { notifyMenuBarUpdate() }
    }

    // MARK: - File Transcription State
    var isTranscribingFile: Bool = false {  // Disables menu item during file transcription
        didSet { notifyMenuBarUpdate() }
    }

    // SWIFT TIP: `init()` is the constructor, like `constructor()` in TypeScript
    init() {
        // Load persisted settings from UserDefaults (macOS's localStorage equivalent)
        let rawModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "parakeet:tdt-0.6b-v3"
        self.selectedModel = ModelIdentifier.migrateLegacy(rawModel)
        // Write back migrated value so future launches don't re-migrate
        if rawModel != self.selectedModel {
            UserDefaults.standard.set(self.selectedModel, forKey: "selectedModel")
        }

        // Migrate existing selectedLanguage → primaryLanguage if needed
        if UserDefaults.standard.object(forKey: "primaryLanguage") == nil {
            // First launch with new language system — migrate from selectedLanguage
            let storedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
            let migrated = storedLanguage == "auto" ? "en" : storedLanguage
            self.primaryLanguage = migrated
            UserDefaults.standard.set(migrated, forKey: "primaryLanguage")
        } else {
            self.primaryLanguage = UserDefaults.standard.string(forKey: "primaryLanguage") ?? "en"
        }

        self.secondaryLanguage = UserDefaults.standard.string(forKey: "secondaryLanguage")

        // Validate saved languages against the selected model's supported languages.
        // Handles cases like a user who had Chinese saved when Parakeet v3's incorrect
        // language list included it — now that the list is corrected, reset to English.
        if let modelInfo = AvailableModels.find(self.selectedModel),
           let supported = modelInfo.supportedLanguages {
            if !supported.contains(self.primaryLanguage) {
                self.primaryLanguage = "en"
                UserDefaults.standard.set("en", forKey: "primaryLanguage")
            }
            if let secondary = self.secondaryLanguage, !supported.contains(secondary) {
                self.secondaryLanguage = nil
                UserDefaults.standard.removeObject(forKey: "secondaryLanguage")
            }
        }

        // Active language starts as primary (reset on every launch)
        self.isUsingSecondaryLanguage = false
        self.selectedLanguage = self.primaryLanguage

        // Keep legacy selectedLanguage in sync
        let storedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        if storedLanguage == "auto" {
            self.selectedLanguage = self.primaryLanguage
        }

        self.customVocabulary = UserDefaults.standard.stringArray(forKey: "customVocabulary") ?? []

        // Load keyboard shortcuts
        self.recordingToggleShortcut = Self.loadShortcut(for: .recordingToggle)
        self.cancelRecordingShortcut = Self.loadShortcut(for: .cancelRecording)
        self.languageToggleShortcut = Self.loadShortcut(for: .languageToggle)

        // Load history settings
        let savedRetention = UserDefaults.standard.integer(forKey: "historyRetentionDays")
        self.historyRetentionDays = savedRetention > 0 ? savedRetention : 90

        // Load sound feedback setting
        self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")

        // Load overlay position setting
        self.overlayPositionFixed = UserDefaults.standard.bool(forKey: "overlayPositionFixed")

        // Load auto-type setting (default: true — use object(forKey:) so missing key defaults to true)
        self.autoTypeEnabled = UserDefaults.standard.object(forKey: "autoTypeEnabled") as? Bool ?? true

        // Load auto-type toggle shortcut
        self.autoTypeToggleShortcut = Self.loadShortcut(for: .autoTypeToggle)

        // Load selected microphone
        self.selectedMicrophoneUID = UserDefaults.standard.string(forKey: "selectedMicrophoneUID")

        // Load selected LLM provider and model
        if let providerRaw = UserDefaults.standard.string(forKey: "selectedLLMProvider"),
           let provider = LLMService.Provider(rawValue: providerRaw) {
            self.selectedLLMProvider = provider
        }

        if let modelRaw = UserDefaults.standard.string(forKey: "selectedLLMModel"),
           let model = LLMModel(rawValue: modelRaw) {
            self.selectedLLMModel = model
        }

    }

    // MARK: - Shortcut Persistence

    /// Load a shortcut from UserDefaults, returning the default if not found
    private static func loadShortcut(for type: ShortcutType) -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: type.storageKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
            return type.defaultShortcut
        }
        return shortcut
    }

    /// Save a shortcut to UserDefaults
    private func saveShortcut(_ shortcut: KeyboardShortcut, for type: ShortcutType) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: type.storageKey)
        }
    }

    // MARK: - State Transitions

    /// Start a new recording session
    func startRecording() {
        recordingState = .recording
        showOverlay = true
        audioLevel = 0.0
        microphoneFellBack = false
    }

    /// Stop recording and begin processing
    func stopRecording() {
        recordingState = .processing
    }

    /// Recording was cancelled (ESC pressed)
    func cancelRecording() {
        recordingState = .idle
        showOverlay = false
        audioLevel = 0.0
        interactionMode = nil
        aiResponseText = ""
        aiResponseError = nil
        isAIResponseStreaming = false
    }

    /// Transcription completed successfully
    func completeTranscription(_ text: String) {
        lastTranscription = text
        recordingState = .idle

        // Show green completion indicator briefly, then hide overlay
        showCompletedIndicator = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { [weak self] in
                self?.showCompletedIndicator = false
                self?.showOverlay = false
            }
        }
    }

    /// An error occurred
    func setError(_ message: String) {
        recordingState = .error(message: message)
        showOverlay = true
        // Auto-dismiss error after 3 seconds
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { [weak self] in
                if case .error = self?.recordingState {
                    self?.recordingState = .idle
                    self?.showOverlay = false
                }
            }
        }
    }

    // MARK: - Settings Persistence

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedModel")
    }

    func setSelectedLanguage(_ language: String) {
        selectedLanguage = language
        UserDefaults.standard.set(language, forKey: "selectedLanguage")
    }

    func addVocabularyWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customVocabulary.contains(trimmed) else { return }
        customVocabulary.append(trimmed)
        UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary")
    }

    func removeVocabularyWord(_ word: String) {
        customVocabulary.removeAll { $0 == word }
        UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary")
    }

    func clearVocabulary() {
        customVocabulary.removeAll()
        UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary")
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        soundFeedbackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "soundFeedbackEnabled")
    }

    func setOverlayPositionFixed(_ fixed: Bool) {
        overlayPositionFixed = fixed
        UserDefaults.standard.set(fixed, forKey: "overlayPositionFixed")
    }

    func setAutoTypeEnabled(_ enabled: Bool) {
        autoTypeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoTypeEnabled")
        notifyMenuBarUpdate()
    }

    func setHistoryRetentionDays(_ days: Int) {
        historyRetentionDays = days
        UserDefaults.standard.set(days, forKey: "historyRetentionDays")
    }

    func setSelectedMicrophoneUID(_ uid: String?) {
        selectedMicrophoneUID = uid
        if let uid {
            UserDefaults.standard.set(uid, forKey: "selectedMicrophoneUID")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedMicrophoneUID")
        }
    }

    func updateAvailableInputDevices(_ devices: [AudioInputDevice]) {
        availableInputDevices = devices
    }

    func setSelectedLLMProvider(_ provider: LLMService.Provider) {
        selectedLLMProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedLLMProvider")

        // Update model to the default for this provider if current model doesn't belong to it
        if selectedLLMModel.provider != provider {
            let defaultModel = LLMModel.defaultModel(for: provider)
            setSelectedLLMModel(defaultModel)
        }

        NotificationCenter.default.post(name: .llmProviderChanged, object: nil)
    }

    func setSelectedLLMModel(_ model: LLMModel) {
        selectedLLMModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "selectedLLMModel")
        NotificationCenter.default.post(name: .llmProviderChanged, object: nil)
    }

    /// Begin streaming AI response — clears previous result and sets streaming flag.
    /// Used by both AI Transform and AI Q&A.
    /// - Parameter newState: The recording state to transition to (`.aiTransforming` or `.aiQA`)
    func startAIResponseStreaming(recordingState newState: RecordingState) {
        recordingState = newState
        aiResponseText = ""
        aiResponseError = nil
        isAIResponseStreaming = true
    }

    /// Append a token chunk to the streaming AI response
    func appendAIResponseToken(_ token: String) {
        aiResponseText += token
    }

    /// Streaming completed successfully — transition to result display state.
    /// - Parameter newState: The result state to transition to (`.aiTransformResult` or `.aiQAResult`)
    func completeAIResponseStream(recordingState newState: RecordingState) {
        isAIResponseStreaming = false
        recordingState = newState
    }

    /// Streaming failed — show error, keep partial result if available.
    /// - Parameters:
    ///   - message: The error description
    ///   - resultState: The result state to use if partial text exists (`.aiTransformResult` or `.aiQAResult`)
    ///   - errorPrefix: Label for error pill if no partial result (e.g. "Transform" or "Q&A")
    func failAIResponseStream(_ message: String, resultState: RecordingState, errorPrefix: String) {
        isAIResponseStreaming = false
        aiResponseError = message
        if !aiResponseText.isEmpty {
            // Partial result available — show it with error banner
            recordingState = resultState
        } else {
            // No result at all — show error pill
            setError("\(errorPrefix) failed: \(message)")
        }
    }

    /// Dismiss the AI response card and return to idle
    func dismissAIResponse() {
        recordingState = .idle
        showOverlay = false
        interactionMode = nil
        aiResponseText = ""
        aiResponseError = nil
        isAIResponseStreaming = false
    }

    func setRecordingToggleShortcut(_ shortcut: KeyboardShortcut) {
        recordingToggleShortcut = shortcut
        saveShortcut(shortcut, for: .recordingToggle)
    }

    func setCancelRecordingShortcut(_ shortcut: KeyboardShortcut) {
        cancelRecordingShortcut = shortcut
        saveShortcut(shortcut, for: .cancelRecording)
    }

    func setLanguageToggleShortcut(_ shortcut: KeyboardShortcut) {
        languageToggleShortcut = shortcut
        saveShortcut(shortcut, for: .languageToggle)
    }

    func setAutoTypeToggleShortcut(_ shortcut: KeyboardShortcut) {
        autoTypeToggleShortcut = shortcut
        saveShortcut(shortcut, for: .autoTypeToggle)
    }

    // MARK: - Language Settings Persistence

    func setPrimaryLanguage(_ language: String) {
        primaryLanguage = language
        UserDefaults.standard.set(language, forKey: "primaryLanguage")
        // If secondary matches new primary, clear secondary
        if secondaryLanguage == language {
            secondaryLanguage = nil
            UserDefaults.standard.removeObject(forKey: "secondaryLanguage")
        }
        // Keep selectedLanguage in sync
        selectedLanguage = activeLanguage
        UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
    }

    func setSecondaryLanguage(_ language: String?) {
        secondaryLanguage = language
        if let language = language {
            UserDefaults.standard.set(language, forKey: "secondaryLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "secondaryLanguage")
            // If secondary cleared while using it, reset to primary
            if isUsingSecondaryLanguage {
                isUsingSecondaryLanguage = false
                selectedLanguage = primaryLanguage
                UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
            }
        }
    }

    /// Toggle between primary and secondary language
    func toggleLanguage() {
        guard secondaryLanguage != nil else { return }
        isUsingSecondaryLanguage.toggle()
        selectedLanguage = activeLanguage
        UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
        languageSwitchDisplayText = "Switched to \(Self.languageDisplayName(for: activeLanguage))"
    }

    // MARK: - Language Display Names (delegated to SupportedLanguages)

    static let languageCodeToName: [String: String] = SupportedLanguages.codeToName

    static func languageDisplayName(for code: String) -> String {
        SupportedLanguages.displayName(for: code)
    }

    static let languageCodeToFlag: [String: String] = SupportedLanguages.codeToFlag

    static func languageFlag(for code: String) -> String {
        SupportedLanguages.flag(for: code)
    }

    /// Reset a shortcut to its default value
    func resetShortcut(_ type: ShortcutType) {
        switch type {
        case .recordingToggle:
            setRecordingToggleShortcut(.defaultRecordingToggle)
        case .cancelRecording:
            setCancelRecordingShortcut(.defaultCancelRecording)
        case .languageToggle:
            setLanguageToggleShortcut(.defaultLanguageToggle)
        case .autoTypeToggle:
            setAutoTypeToggleShortcut(.defaultAutoTypeToggle)
        }
    }

    // MARK: - Menu Bar Updates

    private func notifyMenuBarUpdate() {
        NotificationCenter.default.post(name: .menuBarNeedsUpdate, object: nil)
    }

    // MARK: - Permission Updates

    func updateMicrophonePermission(_ granted: Bool) {
        if hasMicrophonePermission != granted {
            hasMicrophonePermission = granted
            notifyMenuBarUpdate()
        }
    }

    func updateAccessibilityPermission(_ granted: Bool) {
        if hasAccessibilityPermission != granted {
            hasAccessibilityPermission = granted
            notifyMenuBarUpdate()
        }
    }

}

// MARK: - Menu Bar Status

extension AppState {
    /// NSColor for the menu bar status dot
    /// - Yellow: Model loading in progress
    /// - Red: Active recording
    /// - Blue: Processing dictation
    /// - Purple: AI enhancement in progress
    /// - Green: Processing completed
    var statusDotNSColor: NSColor {
        if showCompletedIndicator {
            return .systemGreen
        }
        if !isModelLoaded {
            return .systemYellow
        }
        switch recordingState {
        case .idle:
            return .clear
        case .recording:
            return .systemRed
        case .processing:
            return .systemBlue
        case .aiTransforming, .aiQA:
            return .systemPurple
        case .aiTransformResult, .aiQAResult:
            return .systemGreen
        case .error:
            return .systemRed
        }
    }

    /// Whether to show the status dot
    var showStatusDot: Bool {
        showCompletedIndicator || !isModelLoaded || recordingState != .idle
    }

    /// Whether the recording state allows starting a new recording
    var canStartRecording: Bool {
        switch recordingState {
        case .idle, .error:
            return true
        case .recording, .processing, .aiTransforming, .aiTransformResult, .aiQA, .aiQAResult:
            return false
        }
    }
}
