import AppKit
import CoreAudio
import SwiftUI
import Carbon.HIToolbox

// MARK: - AppDelegate
/// The application delegate handles app lifecycle events and coordinates services.
///
/// SWIFT CONCEPT: NSApplicationDelegate
/// This is the traditional macOS way to handle app events (launch, terminate, etc.)
/// Think of it like event listeners on `window` or `document` in web development.
///
/// WHY WE NEED THIS:
/// 1. Menu bar apps need AppKit's NSStatusBar (not available in pure SwiftUI)
/// 2. Global keyboard shortcuts need to be registered at app startup
/// 3. Some system APIs only work through AppDelegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Shared State

    /// Central app state - shared with all SwiftUI views
    /// SWIFT TIP: `let` makes this immutable (like `const` in TS)
    let appState = AppState()

    // MARK: - Services

    /// Handles global keyboard shortcuts (Option+Space, Esc)
    private var hotkeyManager: HotkeyManager?

    /// Records audio from the microphone
    private var audioRecorder: AudioRecorder?

    /// Manages audio input device enumeration and hot-plug monitoring
    private var audioDeviceManager: AudioDeviceManager?

    /// Transcribes audio via the active backend (shared instance for file transcription)
    private(set) var transcriptionService: TranscriptionService?

    /// Types text into the focused application
    private var textInjector: TextInjector?

    /// Handles AI-powered text enhancement
    private var llmService: LLMService?

    /// Reads selected text from the frontmost app via Accessibility API
    private var accessibilityReader: AccessibilityReader?

    /// Plays system sounds for key events
    private var soundFeedbackService: SoundFeedbackService?

    // MARK: - Overlay Window

    /// The floating overlay window shown during recording
    private var overlayWindow: OverlayWindowController?

    /// Single floating pill window for all transient notifications (language switch, auto-type, etc.)
    private var toastPillWindow: ToastPillWindowController?

    /// Task that observes showOverlay state changes to hide the overlay window
    private var overlayObserverTask: Task<Void, Never>?

    /// Task that observes recordingState changes to register/unregister cancel hotkey
    private var recordingStateObserverTask: Task<Void, Never>?

    /// Task running the current model download/load (cancellable)
    private var modelLoadingTask: Task<Void, Never>?

    /// Task running the current transcription/enhancement pipeline (cancellable)
    private var transcriptionTask: Task<Void, Never>?

    /// Task running the current streaming typing consumer (cancellable).
    /// Stored as a property so we can guarantee only one typing loop exists at a time.
    private var typingTask: Task<Void, Error>?

    // MARK: - Recording Tracking

    /// Timestamp when recording started (for duration calculation)
    private var recordingStartTime: Date?

    // MARK: - Menu Bar

    /// The status bar item in the menu bar
    private var statusItem: NSStatusItem?

    /// Settings window controller
    private var settingsWindowController: NSWindowController?

    /// File transcription window controller
    private var fileTranscriptionWindowController: FileTranscriptionWindowController?

    /// History window controller
    private var historyWindowController: HistoryWindowController?

    // MARK: - App Lifecycle

    /// Called when the app finishes launching.
    /// This is like `document.addEventListener('DOMContentLoaded', ...)` in web dev.
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("========================================")
        print("🎙️ YAPPER APP LAUNCHING")
        print("========================================")
        print("🎙️ Timestamp: \(Date())")
        print("🎙️ Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("🎙️ App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")

        Task {
            await proceedWithAppSetup()
        }
    }

    /// Proceed with normal app setup.
    private func proceedWithAppSetup() async {
        // Setup menu bar
        print("📱 Setting up menu bar...")
        setupMenuBar()
        print("📱 Menu bar setup complete")

        // Initialize services
        print("🔧 Setting up services...")
        setupServices()
        print("🔧 Services setup complete")

        // Check permissions
        print("🔐 Checking permissions...")
        checkPermissions()
        print("🔐 Permissions check complete")

        // Register global keyboard shortcuts
        print("⌨️ Setting up hotkeys...")
        setupHotkeys()
        print("⌨️ Hotkeys setup complete")

        // Listen for menu-triggered recording toggle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleRecordingNotification),
            name: .toggleRecording,
            object: nil
        )

        // Listen for permission refresh requests (from Settings window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePermissionsRefresh),
            name: .permissionsNeedRefresh,
            object: nil
        )

        // Clean up old transcripts based on retention policy
        print("🧹 Checking for old transcripts to clean up...")
        TranscriptHistoryManager.shared.cleanupOldRecords(retentionDays: appState.historyRetentionDays)

        print("========================================")
        print("✅ YAPPER APP READY (model loading in background)")
        print("========================================")
    }

    /// Called when the app is about to terminate.
    /// Clean up resources here.
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 Yapper shutting down...")
        hotkeyManager?.unregisterAll()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create the menu
        let menu = NSMenu()

        // Instructional text showing how to record (replaces the button which would steal focus)
        let shortcutDisplay = appState.recordingToggleShortcut.displayString
        let instructionItem = NSMenuItem(
            title: "Press \(shortcutDisplay) to record",
            action: nil,
            keyEquivalent: ""
        )
        instructionItem.isEnabled = false
        instructionItem.tag = 1 // Tag to identify for shortcut updates
        menu.addItem(instructionItem)

        // Auto-type toggle (checkmark indicates enabled)
        let autoTypeItem = NSMenuItem(
            title: "Auto-type to focused app",
            action: #selector(toggleAutoType),
            keyEquivalent: ""
        )
        autoTypeItem.target = self
        autoTypeItem.tag = 6
        autoTypeItem.state = appState.autoTypeEnabled ? .on : .off
        menu.addItem(autoTypeItem)

        // Permission warning item (hidden when all permissions granted)
        let permissionWarningItem = NSMenuItem(
            title: "Setup Required",
            action: #selector(openSettingsGeneral),
            keyEquivalent: ""
        )
        permissionWarningItem.tag = 3 // Tag to identify for permission updates
        permissionWarningItem.target = self
        permissionWarningItem.isHidden = true
        menu.addItem(permissionWarningItem)

        menu.addItem(.separator())

        // Transcribe File
        let transcribeFileItem = NSMenuItem(
            title: "Transcribe File",
            action: #selector(openFileTranscription),
            keyEquivalent: ""
        )
        transcribeFileItem.target = self
        transcribeFileItem.tag = 2 // Tag to identify for updates
        menu.addItem(transcribeFileItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // History
        let historyItem = NSMenuItem(
            title: "History",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History")
        menu.addItem(historyItem)

        // Copy Last Transcript
        let copyLastItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: #selector(copyLastTranscript),
            keyEquivalent: ""
        )
        copyLastItem.target = self
        copyLastItem.tag = 5  // Tag for dynamic updates
        menu.addItem(copyLastItem)

        menu.addItem(.separator())

        // Version info (disabled)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let versionItem = NSMenuItem(
            title: "Version \(version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Yapper",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Set initial icon
        updateMenuBarIcon()

        // Observe state changes using withObservationTracking
        observeStateChanges()
    }

    @objc private func menuToggleRecording() {
        handleRecordingToggle()
    }

    @objc private func toggleAutoType() {
        performAutoTypeToggle()
    }

    @objc private func openSettings() {
        openSettingsWindow()
    }

    @objc private func openSettingsGeneral() {
        openSettingsWindow(initialPane: .preferences)
    }

    @objc private func openHistory() {
        // Create controller if needed
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(appState: appState)
        }
        historyWindowController?.showWindow()
    }

    @objc private func copyLastTranscript() {
        guard let lastRecord = TranscriptHistoryManager.shared.allRecords.first else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastRecord.text, forType: .string)
    }

    private func openSettingsWindow(initialPane: SettingsPane = .transcription) {
        // If settings window already exists, close it first if we need a different pane
        // (SwiftUI @State doesn't update after initial creation)
        if settingsWindowController != nil {
            settingsWindowController?.close()
            settingsWindowController = nil
        }

        // Create settings window with SwiftUI content
        let settingsView = SettingsView(initialPane: initialPane)
            .environment(appState)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.setContentSize(NSSize(width: 750, height: 520))
        window.minSize = NSSize(width: 650, height: 400)
        window.level = .floating
        window.initialFirstResponder = nil
        window.center()

        // Larger corner radius to match macOS System Settings
        if let themeFrame = window.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.cornerRadius = 12
            themeFrame.layer?.cornerCurve = .continuous
        }

        let windowController = NSWindowController(window: window)
        self.settingsWindowController = windowController

        windowController.showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openFileTranscription() {
        // Create controller if needed (requires transcription service to be available)
        guard let service = transcriptionService else { return }

        if fileTranscriptionWindowController == nil {
            fileTranscriptionWindowController = FileTranscriptionWindowController(
                appState: appState,
                transcriptionService: service
            )
        }

        fileTranscriptionWindowController?.showWindow()
    }

    private func observeStateChanges() {
        // Listen for state changes that affect the menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarUpdate),
            name: .menuBarNeedsUpdate,
            object: nil
        )
    }

    @objc private func handleMenuBarUpdate() {
        updateMenuBarIcon()
        updateMenuItems()
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        // Create the icon with status dot
        let icon = createMenuBarIcon(
            showDot: appState.showStatusDot,
            dotColor: appState.statusDotNSColor
        )
        button.image = icon
    }

    private func updateMenuItems() {
        guard let menu = statusItem?.menu else { return }

        // Update instructional text with current shortcut
        if let instructionItem = menu.item(withTag: 1) {
            let shortcutDisplay = appState.recordingToggleShortcut.displayString
            instructionItem.title = "Press \(shortcutDisplay) to record"
        }

        // Update transcribe file menu item
        if let transcribeFileItem = menu.item(withTag: 2) {
            // Disable during file transcription, if model not loaded, or if mic permission missing
            transcribeFileItem.isEnabled = appState.isModelLoaded
                && !appState.isTranscribingFile
                && appState.hasMicrophonePermission
        }

        // Update permission warning item visibility
        if let permissionWarningItem = menu.item(withTag: 3) {
            permissionWarningItem.isHidden = appState.allPermissionsGranted
        }

        // Update Copy Last Transcript item (tag 5)
        if let copyLastItem = menu.item(withTag: 5) {
            copyLastItem.isEnabled = !TranscriptHistoryManager.shared.allRecords.isEmpty
        }

        // Update auto-type toggle checkmark (tag 6)
        if let autoTypeItem = menu.item(withTag: 6) {
            autoTypeItem.state = appState.autoTypeEnabled ? .on : .off
        }
    }

    private func createMenuBarIcon(showDot: Bool, dotColor: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw the waveform icon
            if let waveformImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Yapper") {
                var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

                // When showing a dot, isTemplate will be false so we need to manually
                // tint the icon for dark/light mode using labelColor which auto-adapts
                if showDot {
                    config = config.applying(.init(paletteColors: [.labelColor]))
                }

                let configuredImage = waveformImage.withSymbolConfiguration(config)
                configuredImage?.draw(in: NSRect(x: 1, y: 3, width: 16, height: 12))
            }

            // Draw status dot if needed
            if showDot && dotColor != .clear {
                let dotSize: CGFloat = 6
                let dotRect = NSRect(
                    x: rect.width - dotSize - 1,
                    y: 1,
                    width: dotSize,
                    height: dotSize
                )
                let dotPath = NSBezierPath(ovalIn: dotRect)
                dotColor.setFill()
                dotPath.fill()
            }

            return true
        }

        image.isTemplate = !showDot // Template only when no dot (allows system to adjust for dark/light mode)
        return image
    }

    // MARK: - Setup

    private func setupServices() {
        // Initialize all services
        // SWIFT TIP: These are initialized lazily when first accessed,
        // but we do it explicitly here for clarity.

        soundFeedbackService = SoundFeedbackService(appState: appState)
        audioRecorder = AudioRecorder()
        transcriptionService = TranscriptionService()
        textInjector = TextInjector()
        accessibilityReader = AccessibilityReader()

        // Initialize audio device manager for microphone selection
        audioDeviceManager = AudioDeviceManager()
        appState.audioDeviceManager = audioDeviceManager
        appState.updateAvailableInputDevices(audioDeviceManager?.availableDevices ?? [])

        // Monitor hot-plug events (device connect/disconnect)
        audioDeviceManager?.onDevicesChanged = { [weak self] in
            guard let self else { return }
            self.appState.updateAvailableInputDevices(self.audioDeviceManager?.availableDevices ?? [])
        }

        // Initialize LLM service and configure the selected provider
        llmService = LLMService()
        configureLLMService()

        // Create overlay window controller
        overlayWindow = OverlayWindowController(appState: appState)

        // Create toast pill for transient notifications (language switch, auto-type, etc.)
        toastPillWindow = ToastPillWindowController(appState: appState)

        // Observe showOverlay state to hide overlay window when it becomes false
        observeOverlayState()

        // Start loading the transcription model in the background
        modelLoadingTask = Task {
            await loadTranscriptionModel()
        }
    }

    private func checkPermissions() {
        // Check microphone permission
        // SWIFT TIP: `Task { }` creates an async context, like an IIFE with async in JS
        // Capture audioRecorder and appState locally for use in async context
        let audioRecorder = self.audioRecorder
        let appState = self.appState

        Task {
            let micPermission = await audioRecorder?.checkPermission() ?? false
            await MainActor.run {
                appState.updateMicrophonePermission(micPermission)
            }
        }

        // Check accessibility permission
        let accessibilityEnabled = AXIsProcessTrusted()
        appState.updateAccessibilityPermission(accessibilityEnabled)

        if !accessibilityEnabled {
            print("⚠️ Accessibility permission not granted. Text injection will not work.")
            // We'll prompt the user in the UI
        }
    }

    /// Observe the showOverlay state and hide the overlay window when it becomes false.
    /// This handles the auto-hide after success/error states.
    private func observeOverlayState() {
        overlayObserverTask?.cancel()
        overlayObserverTask = Task { [weak self] in
            guard let self = self else { return }

            // Continuously observe using withObservationTracking
            while !Task.isCancelled {
                let shouldHide = await withCheckedContinuation { continuation in
                    // Track changes to showOverlay
                    _ = withObservationTracking {
                        self.appState.showOverlay
                    } onChange: {
                        // When showOverlay changes, resume and check the new value
                        Task { @MainActor in
                            continuation.resume(returning: !self.appState.showOverlay)
                        }
                    }
                }

                if shouldHide {
                    self.overlayWindow?.hide()
                }
            }
        }
    }

    /// Observe recordingState changes to register/unregister the cancel hotkey.
    /// When active (recording/processing/enhancing), register so Escape works.
    /// When idle, unregister so Escape is free for other apps.
    private func observeRecordingState() {
        recordingStateObserverTask?.cancel()
        recordingStateObserverTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let newState = await withCheckedContinuation { continuation in
                    _ = withObservationTracking {
                        self.appState.recordingState
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume(returning: self.appState.recordingState)
                        }
                    }
                }

                switch newState {
                case .recording, .processing, .aiTransforming, .aiTransformResult, .aiQA, .aiQAResult:
                    self.hotkeyManager?.reregisterCancelHotkey()
                case .idle, .error:
                    self.hotkeyManager?.unregisterCancelHotkey()
                }
            }
        }
    }

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()

        // Register recording shortcut with smart detection (supports both toggle and hold-to-record modes)
        // - Quick press (<0.3s): Toggle mode - press again to stop recording
        // - Hold (>=0.3s): Hold-to-record mode - release any key to stop recording
        hotkeyManager?.registerRecordingHotkey(
            shortcut: appState.recordingToggleShortcut,
            keyDownHandler: { [weak self] in
                // SWIFT TIP: [weak self] prevents memory leaks (retain cycles)
                // It's like using `useCallback` with deps in React to avoid stale closures
                self?.handleRecordingKeyDown()
            },
            keyUpHandler: { [weak self] in
                self?.handleRecordingKeyUp()
            }
        )

        // Store cancel hotkey shortcut/handler (registered dynamically when recording starts)
        hotkeyManager?.registerCancelHotkey(
            shortcut: appState.cancelRecordingShortcut
        ) { [weak self] in
            self?.handleCancelRecording()
        }
        // Immediately unregister so Escape is free when idle
        hotkeyManager?.unregisterCancelHotkey()

        // Register language toggle hotkey
        hotkeyManager?.registerLanguageToggleHotkey(
            shortcut: appState.languageToggleShortcut
        ) { [weak self] in
            self?.handleLanguageToggle()
        }

        // Register auto-type toggle hotkey
        hotkeyManager?.registerAutoTypeToggleHotkey(
            shortcut: appState.autoTypeToggleShortcut
        ) { [weak self] in
            self?.handleAutoTypeToggle()
        }

        // Observe recording state to register/unregister cancel hotkey dynamically
        observeRecordingState()

        // Listen for shortcut changes from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutsChanged),
            name: .shortcutsChanged,
            object: nil
        )

        // Listen for API key changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChanged),
            name: .apiKeyChanged,
            object: nil
        )

        // Listen for LLM provider/model changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLLMProviderChanged),
            name: .llmProviderChanged,
            object: nil
        )

        // Listen for model selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelSelectionChanged(_:)),
            name: .modelSelectionChanged,
            object: nil
        )

        // Listen for model download cancellation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelDownloadCancelled),
            name: .modelDownloadCancelled,
            object: nil
        )

        // Listen for models cleared from disk
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelsCleared),
            name: .modelsCleared,
            object: nil
        )
    }

    /// Handle shortcut changes from Settings
    @objc private func handleShortcutsChanged() {
        print("⌨️ Shortcuts changed, re-registering hotkeys...")
        hotkeyManager?.updateShortcuts(
            recordingShortcut: appState.recordingToggleShortcut,
            cancelShortcut: appState.cancelRecordingShortcut,
            languageToggleShortcut: appState.languageToggleShortcut,
            autoTypeToggleShortcut: appState.autoTypeToggleShortcut
        )
        // Also update the menu item shortcut display
        updateMenuItemShortcuts()
    }

    /// Handle API key changes from Settings
    @objc private func handleAPIKeyChanged() {
        print("🔑 API key changed, reconfiguring LLM service...")
        configureLLMService()
    }

    @objc private func handleLLMProviderChanged() {
        print("🤖 LLM provider/model changed, reconfiguring...")
        configureLLMService()
    }

    /// Handle model selection changes from Settings
    @objc private func handleModelSelectionChanged(_ notification: Notification) {
        guard let modelName = notification.userInfo?["modelName"] as? String else {
            print("❌ Model selection notification missing modelName")
            return
        }

        print("🔄 Model selection notification received: \(modelName)")

        // Cancel any in-progress model loading before starting a new one
        modelLoadingTask?.cancel()
        modelLoadingTask = Task {
            await reloadTranscriptionModel(modelName: modelName)
        }
    }

    /// Handle model download cancellation from Settings
    @objc private func handleModelDownloadCancelled() {
        print("⛔ Model download cancelled by user")
        modelLoadingTask?.cancel()
        modelLoadingTask = nil

        // Clean up partial download files so isDownloaded stays false
        ModelStorageManager.removeModelFiles(for: appState.selectedModel)

        // Unload any partially loaded model
        Task {
            await transcriptionService?.unloadModel()
        }

        // Reset loading state
        appState.isModelLoaded = false
        appState.isLoadingModel = false
        appState.isModelDownloading = false
        appState.modelLoadingProgress = 0.0
        appState.loadedModel = nil
    }

    /// Handle all downloaded models cleared from disk
    @objc private func handleModelsCleared() {
        print("🗑️ Models cleared from disk, resetting state...")

        // Cancel any in-progress model loading
        modelLoadingTask?.cancel()
        modelLoadingTask = nil

        // Unload current model
        Task {
            await transcriptionService?.unloadModel()
        }

        // Reset all model state
        appState.isModelLoaded = false
        appState.isLoadingModel = false
        appState.isModelDownloading = false
        appState.modelLoadingProgress = 0.0
        appState.loadedModel = nil

        // Re-download the selected model
        let selectedModel = appState.selectedModel
        modelLoadingTask = Task {
            await reloadTranscriptionModel(modelName: selectedModel)
        }
    }

    /// Configure the LLM service with the selected provider and model
    private func configureLLMService() {
        let provider = appState.selectedLLMProvider
        let model = appState.selectedLLMModel

        // Configure all providers that have API keys
        for p in LLMService.Provider.allCases {
            if let apiKey = APIKeyStorage.shared.retrieve(forAccount: p.storageAccount) {
                llmService?.configure(provider: p, apiKey: apiKey)
            } else {
                llmService?.unconfigure(provider: p)
            }
        }

        // Set the active provider if it has an API key
        if let apiKey = APIKeyStorage.shared.retrieve(forAccount: provider.storageAccount) {
            llmService?.configure(provider: provider, apiKey: apiKey, model: model)
            llmService?.setActiveProvider(provider, model: model)
            print("🤖 LLM service configured with \(provider.displayName) (\(model.displayName))")
        } else {
            print("⚠️ No API key for selected provider \(provider.displayName)")
        }
    }

    /// Update menu item to reflect changed shortcut
    private func updateMenuItemShortcuts() {
        guard let menu = statusItem?.menu,
              let instructionItem = menu.item(withTag: 1) else { return }

        // Update the instructional text with the new shortcut
        let shortcutDisplay = appState.recordingToggleShortcut.displayString
        instructionItem.title = "Press \(shortcutDisplay) to record"
    }

    // MARK: - Recording Flow

    /// Handle notification from menu bar to toggle recording
    @objc private func handleToggleRecordingNotification() {
        // Menu bar uses toggle behavior (key-down handler)
        handleRecordingKeyDown()
    }

    /// Handle recording shortcut key-down
    /// This is called immediately when the user presses the recording shortcut.
    /// Mode (toggle vs hold) is determined later based on timing.
    private func handleRecordingKeyDown() {
        print("🎹 AppDelegate.handleRecordingKeyDown - current state: \(appState.recordingState), showOverlay: \(appState.showOverlay), showCompletedIndicator: \(appState.showCompletedIndicator)")

        switch appState.recordingState {
        case .idle:
            // Start recording - we don't know yet if this is toggle or hold mode
            startRecording()

        case .recording:
            // Key-down during recording = user is doing a toggle-style stop
            // This is a subsequent press (not a release), so stop recording
            stopRecording()
            hotkeyManager?.resetHoldState()

        case .processing, .aiTransforming, .aiQA:
            // Ignore during processing, enhancing, transforming, or Q&A
            break

        case .aiTransformResult, .aiQAResult:
            // Block new recording — user must dismiss the result card first (Esc)
            break

        case .error:
            // Clear error and immediately start recording (don't make user press twice)
            appState.recordingState = .idle
            appState.showOverlay = false
            overlayWindow?.hide()
            hotkeyManager?.resetHoldState()
            // Start recording immediately after clearing error
            startRecording()
        }
    }

    /// Handle recording shortcut key-up (only called in hold-to-record mode)
    /// This is called when any key in the shortcut combo is released after being held >= 0.3s.
    private func handleRecordingKeyUp() {
        print("🎹 Recording key-up - current state: \(appState.recordingState)")

        // Only stop if we're actively recording
        guard appState.recordingState == .recording else {
            hotkeyManager?.resetHoldState()
            return
        }

        print("🎹 Hold mode: stopping recording on key release")
        stopRecording()
        hotkeyManager?.resetHoldState()
    }

    /// Handle language toggle shortcut.
    /// For English-only models (e.g. Parakeet v2), this is a no-op because
    /// secondaryLanguage is cleared when switching to such a model.
    private func handleLanguageToggle() {
        // Ignore during active recording
        guard !appState.recordingState.isRecording else { return }
        // Ignore if no secondary language configured (always true for English-only models)
        guard appState.secondaryLanguage != nil else { return }

        appState.toggleLanguage()

        toastPillWindow?.show(languageSwitch: appState.languageSwitchDisplayText)
    }

    private func handleAutoTypeToggle() {
        performAutoTypeToggle()
    }

    private func performAutoTypeToggle() {
        appState.setAutoTypeEnabled(!appState.autoTypeEnabled)
        let icon = appState.autoTypeEnabled ? "keyboard" : "keyboard.badge.ellipsis"
        let text = appState.autoTypeEnabled ? "Auto-type enabled" : "Auto-type disabled"
        toastPillWindow?.show(icon: icon, text: text)
    }

    /// Legacy toggle method - kept for backward compatibility
    private func handleRecordingToggle() {
        handleRecordingKeyDown()
    }

    /// Cancel recording, processing, or enhancement when Esc is pressed
    private func handleCancelRecording() {
        switch appState.recordingState {
        case .recording:
            print("❌ Recording cancelled")
            _ = audioRecorder?.stopRecording()

        case .processing, .aiTransforming, .aiQA:
            print("❌ Transcription/enhancement/transform/Q&A cancelled")
            transcriptionTask?.cancel()
            transcriptionTask = nil
            typingTask?.cancel()
            typingTask = nil

        case .aiTransformResult, .aiQAResult:
            print("👋 AI response dismissed")
            appState.dismissAIResponse()
            hotkeyManager?.resetHoldState()
            return

        case .idle, .error:
            return
        }

        appState.cancelRecording()
        overlayWindow?.hide()
        hotkeyManager?.resetHoldState()
    }

    /// Start recording audio
    private func startRecording() {
        // Check permissions first
        guard appState.hasMicrophonePermission else {
            print("⚠️ Microphone permission missing")
            appState.setError("No mic access")
            soundFeedbackService?.play(.error)
            overlayWindow?.show()
            requestMicrophonePermission()
            return
        }

        guard appState.hasAccessibilityPermission else {
            print("⚠️ Accessibility permission missing")
            appState.setError("No accessibility access")
            soundFeedbackService?.play(.error)
            overlayWindow?.show()
            textInjector?.requestPermission()
            return
        }

        guard appState.isModelLoaded else {
            print("⚠️ Model not loaded")
            if appState.isLoadingModel {
                appState.setError("Model still loading...")
            } else {
                appState.setError("No model available")
            }
            soundFeedbackService?.play(.error)
            overlayWindow?.show()
            return
        }

        // Detect selected text to determine interaction mode (dictation vs AI transform)
        let selectedText = accessibilityReader?.readSelectedText()
        if let selectedText, !selectedText.isEmpty {
            // Validate selection length
            guard selectedText.count <= AccessibilityReader.maxSelectionLength else {
                appState.setError("Selected text too long (max ~10,000 chars)")
                soundFeedbackService?.play(.error)
                overlayWindow?.show()
                return
            }
            // AI Transform requires a configured LLM
            guard llmService?.isConfigured() ?? false else {
                appState.setError("AI Transform requires an API key. Configure in Settings → AI.")
                soundFeedbackService?.play(.error)
                overlayWindow?.show()
                return
            }
            appState.interactionMode = .aiTransform(selectedText: selectedText)
        } else {
            appState.interactionMode = nil
        }

        // All checks passed — play sound BEFORE mic starts
        soundFeedbackService?.play(.recordingStarted)

        print("🎙️ Starting recording...")
        appState.startRecording()
        overlayWindow?.show()

        // Track recording start time for duration calculation
        recordingStartTime = Date()

        // Capture appState locally to avoid capturing self in Sendable closure
        let appState = self.appState

        // Resolve selected microphone UID to a CoreAudio device ID
        let selectedDeviceID: AudioDeviceID?
        if let uid = appState.selectedMicrophoneUID {
            selectedDeviceID = audioDeviceManager?.resolveDeviceID(forUID: uid)
            if selectedDeviceID == nil {
                AppLogger.audio.warning("Selected microphone '\(uid)' not found, using system default")
            }
        } else {
            selectedDeviceID = nil
        }

        // Stop level monitoring (Settings UI) to avoid two engines on the same device
        audioDeviceManager?.stopLevelMonitoring()

        // Start audio capture
        let deviceUsed = audioRecorder?.startRecording(deviceID: selectedDeviceID) { audioLevel in
            // Update audio level for visualization
            // This callback is called frequently during recording
            Task { @MainActor in
                appState.audioLevel = audioLevel
            }
        }

        // Warn if the selected mic couldn't be used (fell back to system default)
        if selectedDeviceID != nil && deviceUsed != true {
            AppLogger.audio.warning("Selected microphone unavailable, recording with system default")
            appState.microphoneFellBack = true
        }
    }

    /// Stop recording and transcribe
    private func stopRecording() {
        print("⏹️ Stopping recording...")

        appState.stopRecording()

        // Stop audio capture and get the audio data
        guard let audioData = audioRecorder?.stopRecording() else {
            appState.setError("No audio recorded")
            soundFeedbackService?.play(.error)
            overlayWindow?.hide()
            return
        }

        // Transcribe the audio — cancel any in-flight transcription AND typing
        transcriptionTask?.cancel()
        typingTask?.cancel()
        typingTask = nil
        transcriptionTask = Task {
            await transcribeAudio(audioData)
        }
    }

    /// Transcribe audio data.
    /// Routes to streaming or batch mode depending on engine and whether AI enhancement is active.
    /// Parakeet always uses the batch path (its speed makes batch + typeText indistinguishable from streaming).
    private func transcribeAudio(_ audioData: Data) async {
        print("🧠 Transcribing audio...")

        // Calculate recording duration
        let recordingDuration: TimeInterval
        if let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
        } else {
            recordingDuration = 0
        }

        let isTransformMode = appState.interactionMode?.isAITransform == true

        // Parakeet doesn't support token-by-token streaming, so always use batch path.
        // Its 110-190x RTF means batch is effectively instant anyway.
        // AI Transform always uses batch — we need the full transcription as an instruction.
        let modelId = ModelIdentifier(persistedValue: appState.selectedModel)
        let supportsStreaming = modelId?.engine == .whisper

        if !supportsStreaming || isTransformMode {
            await transcribeAudioBatch(audioData, recordingDuration: recordingDuration)
        } else {
            await transcribeAudioStreaming(audioData, recordingDuration: recordingDuration)
        }
    }

    /// Streaming transcription path — types text token-by-token as the backend decodes.
    ///
    /// Uses an AsyncStream to serialize typing: the backend callback (which may fire on a
    /// background thread) yields deltas into the stream, and a single consumer task on
    /// MainActor types them one at a time. This prevents interleaving from concurrent Tasks.
    private func transcribeAudioStreaming(_ audioData: Data, recordingDuration: TimeInterval) async {
        let transcriptionService = self.transcriptionService
        let textInjector = self.textInjector

        do {
            let language = appState.selectedLanguage
            let vocabulary = appState.customVocabulary

            try Task.checkCancellation()

            // Initial delay to let overlay settle and focus return to the target app
            try await Task.sleep(for: .milliseconds(100))

            try Task.checkCancellation()

            print("🔄 Starting streaming transcription...")

            // Create a stream to serialize token deltas for ordered typing.
            // The callback yields deltas from a background thread; the consumer
            // types them one-at-a-time on MainActor, preventing interleaving.
            let (stream, continuation) = AsyncStream.makeStream(of: String.self)

            // Cancel any previous typing task to prevent two concurrent typing loops.
            // This is the primary defense against interleaved output.
            self.typingTask?.cancel()
            self.typingTask = nil

            // Start the single typing consumer — types each delta atomically
            // When auto-type is disabled, skip injection (text still goes to history)
            let shouldType = appState.autoTypeEnabled
            let newTypingTask = Task { @MainActor in
                for await delta in stream {
                    try Task.checkCancellation()
                    if shouldType {
                        try textInjector?.typeStringAtomically(delta)
                    }
                }
            }
            self.typingTask = newTypingTask
            defer {
                newTypingTask.cancel()
                self.typingTask = nil
            }

            // Run streaming transcription — onToken yields deltas into the stream
            let finalText: String?
            do {
                finalText = try await transcriptionService?.transcribeStreaming(
                    audioData: audioData,
                    language: language,
                    customVocabulary: vocabulary,
                    onToken: { delta in
                        continuation.yield(delta)
                    }
                )
            } catch {
                // Ensure the stream is finished even on error so the typing task exits
                continuation.finish()
                throw error
            }

            // Signal no more deltas — the typing task's for-await loop will end
            continuation.finish()

            // Wait for all queued typing to complete
            do {
                try await newTypingTask.value
            } catch is CancellationError {
                // Typing task was cancelled (e.g. new recording started) — expected
            } catch {
                print("⚠️ Typing task error: \(error)")
            }

            guard let finalText else {
                appState.setError("Transcription failed")
                soundFeedbackService?.play(.error)
                overlayWindow?.hide()
                return
            }

            try Task.checkCancellation()

            let cleanedText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedText.isEmpty {
                appState.setError("No speech detected")
                soundFeedbackService?.play(.error)
                overlayWindow?.hide()
                return
            }

            print("📝 Streaming transcription complete: \(cleanedText)")

            // Save to transcript history
            let record = TranscriptRecord(
                text: cleanedText,
                duration: recordingDuration,
                language: language
            )
            TranscriptHistoryManager.shared.addRecord(record)
            print("💾 Saved transcript to history (duration: \(record.formattedDuration))")

            // Show success indicator (text was already typed incrementally)
            appState.completeTranscription(cleanedText)
            soundFeedbackService?.play(.transcriptionComplete)

        } catch is CancellationError {
            print("❌ Streaming transcription cancelled")
            appState.cancelRecording()
            overlayWindow?.hide()
        } catch {
            print("❌ Streaming transcription error: \(error)")
            appState.setError(error.localizedDescription)
            soundFeedbackService?.play(.error)
            overlayWindow?.hide()
        }
    }

    /// Batch transcription path — transcribes fully, then types all at once.
    /// Used when the engine doesn't support streaming (Parakeet) or in AI Transform mode.
    private func transcribeAudioBatch(_ audioData: Data, recordingDuration: TimeInterval) async {
        let transcriptionService = self.transcriptionService
        let llmService = self.llmService
        let textInjector = self.textInjector

        do {
            let language = appState.selectedLanguage
            let vocabulary = appState.customVocabulary

            try Task.checkCancellation()

            guard let transcription = try await transcriptionService?.transcribe(
                audioData: audioData,
                language: language,
                customVocabulary: vocabulary
            ) else {
                appState.setError("Transcription failed")
                soundFeedbackService?.play(.error)
                overlayWindow?.hide()
                return
            }

            try Task.checkCancellation()

            let cleanedText = transcription.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedText.isEmpty {
                appState.setError("No speech detected")
                soundFeedbackService?.play(.error)
                overlayWindow?.hide()
                return
            }

            print("📝 Transcription: \(cleanedText)")

            let finalText = cleanedText

            try Task.checkCancellation()

            // Branch: AI Transform → AI Q&A → normal dictation
            if case .aiTransform(let selectedText) = appState.interactionMode {
                // Transform path — stream LLM response into the overlay card
                appState.startAIResponseStreaming(recordingState: .aiTransforming)

                do {
                    guard let stream = llmService?.transformStream(
                        text: selectedText,
                        instruction: finalText
                    ) else {
                        appState.failAIResponseStream("LLM service not configured", resultState: .aiTransformResult, errorPrefix: "Transform")
                        soundFeedbackService?.play(.error)
                        return
                    }

                    for try await token in stream {
                        try Task.checkCancellation()
                        appState.appendAIResponseToken(token)
                    }

                    guard !appState.aiResponseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        appState.failAIResponseStream("Empty response from API", resultState: .aiTransformResult, errorPrefix: "Transform")
                        soundFeedbackService?.play(.error)
                        return
                    }

                    appState.completeAIResponseStream(recordingState: .aiTransformResult)
                    soundFeedbackService?.play(.transcriptionComplete)

                    // Save to history
                    let record = TranscriptRecord(
                        text: appState.aiResponseText,
                        duration: recordingDuration,
                        language: language
                    )
                    TranscriptHistoryManager.shared.addRecord(record)
                    print("💾 Saved transform to history (duration: \(record.formattedDuration))")

                    // Do NOT hide overlay — user dismisses via Escape after copying
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    print("❌ AI Transform stream failed: \(error.localizedDescription)")
                    appState.failAIResponseStream(error.localizedDescription, resultState: .aiTransformResult, errorPrefix: "Transform")
                    soundFeedbackService?.play(.error)
                }
            } else if let question = detectHeyYapper(in: finalText) {
                // "Hey Yapper" detected — route to Q&A
                try await handleAIQA(question: question, recordingDuration: recordingDuration, language: language)
            } else {
                // Normal dictation path
                // Save to transcript history
                let record = TranscriptRecord(
                    text: finalText,
                    duration: recordingDuration,
                    language: language
                )
                TranscriptHistoryManager.shared.addRecord(record)
                print("💾 Saved transcript to history (duration: \(record.formattedDuration))")

                // Inject text via Accessibility API (skip when auto-type is disabled)
                if appState.autoTypeEnabled {
                    try await textInjector?.typeText(finalText)
                }

                // Show success indicator
                appState.completeTranscription(finalText)
                soundFeedbackService?.play(.transcriptionComplete)
            }

        } catch is CancellationError {
            print("❌ Transcription cancelled")
            appState.cancelRecording()
            overlayWindow?.hide()
        } catch {
            print("❌ Transcription error: \(error)")
            appState.setError(error.localizedDescription)
            soundFeedbackService?.play(.error)
            overlayWindow?.hide()
        }
    }

    // MARK: - AI Q&A ("Hey Yapper")

    /// Detect "Hey Yapper" prefix (case-insensitive, fuzzy) and extract the question.
    /// Returns the stripped question, or nil if the prefix is not found.
    /// Includes common speech-to-text misrecognitions as fallback triggers.
    private func detectHeyYapper(in text: String) -> String? {
        // Require a configured LLM — if not, fall back to normal dictation
        guard llmService?.isConfigured() ?? false else { return nil }

        // Canonical + common STT misrecognitions of "Hey Yapper", case-insensitive.
        // Each pattern is a regex matching the trigger prefix (without trailing punctuation).
        let triggerPatterns: [String] = [
            // — Canonical —
            #"hey\s+yapper"#,

            // — Vowel/consonant swaps on "Yapper" —
            #"hey\s+yaper"#,          // single P
            #"hey\s+yapper"#,         // (redundant, kept for clarity)
            #"hey\s+yappar"#,         // -ar ending
            #"hey\s+yappor"#,        // -or ending
            #"hey\s+yappur"#,         // -ur ending
            #"hey\s+yepper"#,         // e instead of a
            #"hey\s+yeper"#,          // e + single P
            #"hey\s+yipper"#,         // i instead of a
            #"hey\s+yopper"#,         // o instead of a
            #"hey\s+yupper"#,         // u instead of a

            // — Missing leading Y —
            #"hey\s+apper"#,          // "hey apper"
            #"hey\s+upper"#,          // "hey upper"

            // — Y → other consonant —
            #"hey\s+rapper"#,         // Y→R
            #"hey\s+japper"#,         // Y→J
            #"hey\s+napper"#,         // Y→N
            #"hey\s+dapper"#,         // Y→D
            #"hey\s+tapper"#,         // Y→T
            #"hey\s+zapper"#,         // Y→Z
            #"hey\s+jabber"#,         // Y→J + P→B
            #"hey\s+yabber"#,         // P→B

            // — Plural / suffix drift —
            #"hey\s+yappers"#,        // trailing S
            #"hey\s+yap\s+per"#,      // space inserted
            #"hey\s+yap\s+her"#,      // "yap her"
            #"hey\s+yap"#,            // truncated

            // — "Hey" misspellings —
            #"hay\s+yapper"#,         // "hay"
            #"hey\s+a\s+yapper"#,     // inserted article "a"
            #"a\s+yapper"#,           // "hey" dropped, article remains
            #"hei\s+yapper"#,         // phonetic "hei"

            // — No space / merged —
            #"heyyapper"#,            // no space
        ]

        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for trigger in triggerPatterns {
            let fullPattern = "^\(trigger)[,.:;!?\\s]*"
            if let range = lowered.range(of: fullPattern, options: [.regularExpression, .caseInsensitive]) {
                let question = String(lowered[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return question.isEmpty ? nil : question
            }
        }

        return nil
    }

    /// Handle the AI Q&A flow — stream the LLM answer into the overlay card.
    private func handleAIQA(question: String, recordingDuration: TimeInterval, language: String) async throws {
        appState.interactionMode = .aiQA(question: question)
        appState.startAIResponseStreaming(recordingState: .aiQA)

        do {
            guard let stream = llmService?.qaStream(question: question) else {
                appState.failAIResponseStream("LLM service not configured", resultState: .aiQAResult, errorPrefix: "Q&A")
                soundFeedbackService?.play(.error)
                return
            }

            for try await token in stream {
                try Task.checkCancellation()
                appState.appendAIResponseToken(token)
            }

            guard !appState.aiResponseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appState.failAIResponseStream("Empty response from API", resultState: .aiQAResult, errorPrefix: "Q&A")
                soundFeedbackService?.play(.error)
                return
            }

            appState.completeAIResponseStream(recordingState: .aiQAResult)
            soundFeedbackService?.play(.transcriptionComplete)

            // Save Q&A answer to history
            let record = TranscriptRecord(
                text: appState.aiResponseText,
                duration: recordingDuration,
                language: language
            )
            TranscriptHistoryManager.shared.addRecord(record)
            print("💾 Saved Q&A answer to history (duration: \(record.formattedDuration))")

            // Do NOT hide overlay — user dismisses via Escape after copying
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("❌ AI Q&A stream failed: \(error.localizedDescription)")
            appState.failAIResponseStream(error.localizedDescription, resultState: .aiQAResult, errorPrefix: "Q&A")
            soundFeedbackService?.play(.error)
        }
    }

    // MARK: - Model Loading

    private func loadTranscriptionModel() async {
        print("========================================")
        print("🎙️ APP DELEGATE: Starting model load")
        print("========================================")
        print("🎙️ Selected model: \(appState.selectedModel)")
        print("🎙️ TranscriptionService exists: \(transcriptionService != nil)")

        // Capture appState for use in Sendable closure
        let appState = self.appState
        let selectedModel = appState.selectedModel

        appState.isLoadingModel = true

        do {
            print("🎙️ Calling transcriptionService.loadModel()...")

            try await transcriptionService?.loadModel(
                modelName: selectedModel,
                progressHandler: { @Sendable progress in
                    print("📊 Progress callback: \(progress)")
                    Task { @MainActor in
                        appState.modelLoadingProgress = progress
                    }
                },
                phaseHandler: { @Sendable phase in
                    print("📊 Phase callback: \(phase)")
                    Task { @MainActor in
                        appState.isModelDownloading = (phase == .downloading)
                    }
                }
            )

            print("🎙️ loadModel() returned successfully")

            appState.isModelLoaded = true
            appState.isLoadingModel = false
            appState.loadedModel = selectedModel
            print("========================================")
            print("✅ APP DELEGATE: Model loaded successfully!")
            print("========================================")

        } catch is CancellationError {
            print("⛔ APP DELEGATE: Model loading cancelled")
        } catch {
            print("========================================")
            print("❌ APP DELEGATE: Model loading failed!")
            print("========================================")
            print("❌ Error: \(error)")
            print("❌ Localized: \(error.localizedDescription)")

            appState.isLoadingModel = false
            appState.setError("Failed to load speech model: \(error.localizedDescription)")
        }
    }

    /// Reload the transcription model with a new model
    /// Called when user changes the model in settings
    func reloadTranscriptionModel(modelName: String) async {
        print("========================================")
        print("🔄 APP DELEGATE: Switching model to \(modelName)")
        print("========================================")

        // Capture appState for use in Sendable closure
        let appState = self.appState

        // Update state to show loading
        appState.isModelLoaded = false
        appState.isLoadingModel = true
        appState.modelLoadingProgress = 0.0
        appState.isModelDownloading = true

        // Unload current model
        await transcriptionService?.unloadModel()

        // Load the new model
        do {
            try await transcriptionService?.loadModel(
                modelName: modelName,
                progressHandler: { @Sendable progress in
                    Task { @MainActor in
                        appState.modelLoadingProgress = progress
                    }
                },
                phaseHandler: { @Sendable phase in
                    Task { @MainActor in
                        appState.isModelDownloading = (phase == .downloading)
                    }
                }
            )

            appState.isModelLoaded = true
            appState.isLoadingModel = false
            appState.loadedModel = modelName
            print("✅ Model switched successfully to \(modelName)")
        } catch is CancellationError {
            print("⛔ Model switch cancelled")
        } catch {
            print("❌ Failed to switch model: \(error)")
            appState.isLoadingModel = false
            appState.setError("Failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        // Capture audioRecorder and appState locally for use in async context
        let audioRecorder = self.audioRecorder
        let appState = self.appState

        Task {
            let granted = await audioRecorder?.requestPermission() ?? false
            await MainActor.run {
                appState.hasMicrophonePermission = granted
            }
        }
    }

    /// Open System Settings to the Accessibility pane
    func openAccessibilitySettings() {
        // This deep-links to System Settings > Privacy & Security > Accessibility
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Open System Settings to the Microphone pane
    func openMicrophoneSettings() {
        // This deep-links to System Settings > Privacy & Security > Microphone
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    /// Handle permission refresh notification (from Settings window)
    @objc private func handlePermissionsRefresh() {
        // Check accessibility (synchronous)
        let accessibilityEnabled = AXIsProcessTrusted()
        appState.updateAccessibilityPermission(accessibilityEnabled)

        // Check microphone (async)
        // Capture audioRecorder and appState locally for use in async context
        let audioRecorder = self.audioRecorder
        let appState = self.appState

        Task {
            let micPermission = await audioRecorder?.checkPermission() ?? false
            await MainActor.run {
                appState.updateMicrophonePermission(micPermission)
            }
        }
    }
}
