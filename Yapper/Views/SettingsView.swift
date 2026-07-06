import CoreAudio
import SwiftUI

// MARK: - Settings Pane

/// Panes for the Tahoe-style sidebar navigation
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case transcription = "Transcription"
    case aiEnhancement = "AI"
    case preferences = "Preferences"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .transcription: return "waveform"
        case .aiEnhancement: return "sparkles"
        case .preferences: return "gear"
        }
    }
}


// MARK: - Settings View

/// The settings window for configuring Yapper.
/// Uses a Tahoe-style NavigationSplitView with a persistent sidebar
/// and a detail pane for each settings category.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPane: SettingsPane
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showClearModelsConfirmation = false
    @State private var modelsDiskUsage: Int64 = 0
    /// Changing this UUID forces the model picker to re-evaluate `isDownloaded` labels
    @State private var pickerRefreshId = UUID()

    /// Initialize with an optional starting pane (defaults to transcription)
    init(initialPane: SettingsPane = .transcription) {
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedPane) {
                Label("Transcription", systemImage: "waveform")
                    .tag(SettingsPane.transcription)
                Label("AI", systemImage: "sparkles")
                    .tag(SettingsPane.aiEnhancement)
                Label("Preferences", systemImage: "gear")
                    .tag(SettingsPane.preferences)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            VStack(spacing: 0) {
                if !appState.allPermissionsGranted {
                    PermissionsBanner()
                }
                detailContent
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedPane {
        case .transcription:
            transcriptionPane
        case .aiEnhancement:
            AISettingsView()
        case .preferences:
            preferencesPane
        }
    }

    // MARK: - Model Picker Binding

    /// Custom binding for the model picker that triggers model reload on selection change
    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                // Always use selectedModel for the picker display
                // This ensures consistency and avoids SwiftUI re-triggering the setter
                appState.selectedModel
            },
            set: { newValue in
                // Guard against setting the same value (prevents duplicate triggers)
                guard newValue != appState.selectedModel else { return }

                print("🔄 Model selection changed: \(appState.selectedModel) -> \(newValue)")

                // Update the selected model preference
                appState.setSelectedModel(newValue)

                // If the new model doesn't support the current language, reset
                if let modelInfo = AvailableModels.find(newValue) {
                    if modelInfo.isEnglishOnly {
                        // English-only model: force primary to English, clear secondary
                        appState.setPrimaryLanguage("en")
                        appState.setSecondaryLanguage(nil)
                    } else if let supported = modelInfo.supportedLanguages {
                        if !supported.contains(appState.primaryLanguage) {
                            appState.setPrimaryLanguage("en")
                        }
                        if let secondary = appState.secondaryLanguage, !supported.contains(secondary) {
                            appState.setSecondaryLanguage(nil)
                        }
                    }
                }

                // Notify AppDelegate to reload the model via NotificationCenter
                NotificationCenter.default.post(
                    name: .modelSelectionChanged,
                    object: nil,
                    userInfo: ["modelName": newValue]
                )
            }
        )
    }

    // MARK: - Transcription View

    /// ModelInfo for the currently selected model
    private var currentModelInfo: ModelInfo? {
        AvailableModels.find(appState.selectedModel)
    }

    /// Languages available for the currently selected model.
    /// Returns all languages for Whisper (supportedLanguages == nil), or the model's specific list.
    private var availableLanguages: [(code: String, name: String)] {
        if let supported = currentModelInfo?.supportedLanguages {
            return Self.allLanguages.filter { supported.contains($0.code) }
        }
        return Self.allLanguages
    }

    // MARK: - Microphone Picker Binding

    /// Bridges String? (AppState) ↔ String (Picker tag) using empty string for nil (System Default)
    private var microphoneBinding: Binding<String> {
        Binding(
            get: { appState.selectedMicrophoneUID ?? "" },
            set: { newValue in
                let uid = newValue.isEmpty ? nil : newValue
                guard uid != appState.selectedMicrophoneUID else { return }
                appState.setSelectedMicrophoneUID(uid)
            }
        )
    }

    /// Resolve the currently selected microphone UID to a CoreAudio AudioDeviceID
    private var selectedMicrophoneDeviceID: AudioDeviceID? {
        guard let uid = appState.selectedMicrophoneUID else { return nil }
        return appState.audioDeviceManager?.resolveDeviceID(forUID: uid)
    }

    private var transcriptionPane: some View {
        Form {
            // MARK: Microphone Section
            if let deviceManager = appState.audioDeviceManager {
                Section {
                    Picker("Input Device", selection: microphoneBinding) {
                        Text("System Default").tag("")
                        if !appState.availableInputDevices.isEmpty {
                            Divider()
                            ForEach(appState.availableInputDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    // Warning when selected device is unavailable
                    if let uid = appState.selectedMicrophoneUID,
                       !appState.availableInputDevices.contains(where: { $0.uid == uid }) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Selected microphone is unavailable. Using system default.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Live audio level meter
                    MicrophoneLevelView(
                        audioDeviceManager: deviceManager,
                        selectedDeviceID: selectedMicrophoneDeviceID
                    )

                    Text("Choose which microphone to use for recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Microphone")
                }
            }

            // MARK: Model Section
            Section {
                Picker("Speech Model", selection: pickerSelection) {
                    ForEach(AvailableModels.groupedByEngine, id: \.engine) { group in
                        Section(group.engine.displayName) {
                            ForEach(group.models, id: \.persistedValue) { model in
                                Text(model.displayName)
                                    .tag(model.persistedValue)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .disabled(appState.isLoadingModel)
                .id(pickerRefreshId)

                Text("Parakeet models are faster and use less memory. Whisper models support more languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.isModelLoaded {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Active: \(modelDisplayName(appState.loadedModel ?? "unknown"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !appState.isLoadingModel {
                    // No model loaded and not loading (e.g. after cancellation)
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                        Text("No model loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Download") {
                            NotificationCenter.default.post(
                                name: .modelSelectionChanged,
                                object: nil,
                                userInfo: ["modelName": appState.selectedModel]
                            )
                        }
                        .controlSize(.small)
                    }
                } else if appState.isModelDownloading {
                    // Downloading phase - show progress bar with cancel button
                    // Parakeet downloads don't report granular progress (stays at 0),
                    // so show an indeterminate bar until progress > 0.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Downloading \(modelDisplayName(appState.selectedModel))...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if appState.modelLoadingProgress > 0 {
                                Text("\(Int(appState.modelLoadingProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        HStack(spacing: 6) {
                            if appState.modelLoadingProgress > 0 {
                                ProgressView(value: appState.modelLoadingProgress)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                            }
                            Button {
                                NotificationCenter.default.post(name: .modelDownloadCancelled, object: nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel download")
                        }
                    }
                } else {
                    // Loading/prewarming phase - show spinner
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading \(modelDisplayName(appState.selectedModel))...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Downloaded models: \(FileSizeFormatter.format(modelsDiskUsage))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showClearModelsConfirmation = true
                    } label: {
                        Text("Clear Downloaded Models")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isLoadingModel || appState.isModelDownloading)
                }
                .confirmationDialog(
                    "Clear Downloaded Models?",
                    isPresented: $showClearModelsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear \(FileSizeFormatter.format(modelsDiskUsage))", role: .destructive) {
                        do {
                            try ModelStorageManager.clearAllModels()
                            modelsDiskUsage = 0
                            pickerRefreshId = UUID()
                            NotificationCenter.default.post(name: .modelsCleared, object: nil)
                        } catch {
                            print("❌ Failed to clear models: \(error.localizedDescription)")
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all downloaded speech models (\(FileSizeFormatter.format(modelsDiskUsage))). The selected model will be re-downloaded automatically.")
                }
            } header: {
                Text("Model")
            }

            Section {
                if currentModelInfo?.isEnglishOnly == true {
                    // English-only model: show disabled pickers with constant values
                    Picker("Primary Language", selection: .constant("en")) {
                        Text("English").tag("en")
                    }
                    .pickerStyle(.menu)
                    .disabled(true)

                    Picker("Secondary Language", selection: .constant("")) {
                        Text("None").tag("")
                    }
                    .pickerStyle(.menu)
                    .disabled(true)

                    Text("This model only supports English transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Primary Language", selection: Binding(
                        get: { appState.primaryLanguage },
                        set: { appState.setPrimaryLanguage($0) }
                    )) {
                        ForEach(availableLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Your main dictation language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Secondary Language", selection: Binding(
                        get: { appState.secondaryLanguage ?? "" },
                        set: { appState.setSecondaryLanguage($0.isEmpty ? nil : $0) }
                    )) {
                        Text("None").tag("")
                        ForEach(availableLanguages.filter { $0.code != appState.primaryLanguage }, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Toggle with \(appState.languageToggleShortcut.displayString) for quick switching.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Language")
            }

            Section {
                VocabularyTagInputView()

                if !appState.customVocabulary.isEmpty {
                    Button("Clear All") {
                        appState.clearVocabulary()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Custom Vocabulary")
            } footer: {
                Text("Add names, acronyms, and specialized terms to improve recognition accuracy. Example: \"Yapper\", \"ACME Corp\", \"OAuth\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            modelsDiskUsage = ModelStorageManager.totalDiskUsage()
        }
        .onChange(of: appState.isLoadingModel) { _, isLoading in
            if !isLoading {
                // Model loading just finished (success, failure, or cancel) —
                // refresh the download indicators and disk usage
                modelsDiskUsage = ModelStorageManager.totalDiskUsage()
                pickerRefreshId = UUID()
            }
        }
    }

    // MARK: - Preferences Pane

    private var preferencesPane: some View {
        Form {
            Section {
                ShortcutSettingRow(
                    shortcutType: .recordingToggle,
                    shortcut: Bindable(appState).recordingToggleShortcut,
                    onShortcutChanged: { newShortcut in
                        appState.setRecordingToggleShortcut(newShortcut)
                        notifyShortcutsChanged()
                    }
                )

                ShortcutSettingRow(
                    shortcutType: .cancelRecording,
                    shortcut: Bindable(appState).cancelRecordingShortcut,
                    onShortcutChanged: { newShortcut in
                        appState.setCancelRecordingShortcut(newShortcut)
                        notifyShortcutsChanged()
                    }
                )

                ShortcutSettingRow(
                    shortcutType: .languageToggle,
                    shortcut: Bindable(appState).languageToggleShortcut,
                    onShortcutChanged: { newShortcut in
                        appState.setLanguageToggleShortcut(newShortcut)
                        notifyShortcutsChanged()
                    }
                )

                ShortcutSettingRow(
                    shortcutType: .autoTypeToggle,
                    shortcut: Bindable(appState).autoTypeToggleShortcut,
                    onShortcutChanged: { newShortcut in
                        appState.setAutoTypeToggleShortcut(newShortcut)
                        notifyShortcutsChanged()
                    }
                )
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                HStack {
                    Text("Click on a shortcut to record a new one. Keyboard shortcuts work globally, even when other apps are focused.")
                    Spacer()
                    Button("Reset to Defaults") {
                        appState.resetShortcut(.recordingToggle)
                        appState.resetShortcut(.cancelRecording)
                        appState.resetShortcut(.languageToggle)
                        appState.resetShortcut(.autoTypeToggle)
                        notifyShortcutsChanged()
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Auto-type to focused app", isOn: Binding(
                    get: { appState.autoTypeEnabled },
                    set: { appState.setAutoTypeEnabled($0) }
                ))

                Text("When enabled, transcribed text is automatically typed into the focused text field. When disabled, text is only saved to history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Fixed overlay position", isOn: Binding(
                    get: { appState.overlayPositionFixed },
                    set: { appState.setOverlayPositionFixed($0) }
                ))

                Text("When enabled, the recording indicator appears at the top center of your screen. When disabled, it follows your cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Sound feedback", isOn: Binding(
                    get: { appState.soundFeedbackEnabled },
                    set: { appState.setSoundFeedbackEnabled($0) }
                ))

                Text("Play subtle sounds when recording starts and transcription completes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Output")
            }

            AvailabilitySection()

            AppFooterView()
        }
        .formStyle(.grouped)
        .onAppear {
            NotificationCenter.default.post(name: .permissionsNeedRefresh, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            NotificationCenter.default.post(name: .permissionsNeedRefresh, object: nil)
        }
    }

    // MARK: - Language List (bridged from SupportedLanguages)

    private static let allLanguages: [(code: String, name: String)] =
        SupportedLanguages.all.map { ($0.code, $0.name) }

    // MARK: - Helpers

    private func notifyShortcutsChanged() {
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    private func modelDisplayName(_ modelId: String) -> String {
        AvailableModels.find(modelId)?.displayName ?? modelId
    }
}

// MARK: - Vocabulary Tag Input View

/// A tag-based input for custom vocabulary words
struct VocabularyTagInputView: View {
    @Environment(AppState.self) private var appState
    @State private var newWord: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Input field with Add button
            HStack {
                TextField("Add word or phrase...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isInputFocused = false
                        }
                    }
                    .onSubmit {
                        addWord()
                    }

                Button("Add") {
                    addWord()
                }
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Tags display
            if !appState.customVocabulary.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(appState.customVocabulary, id: \.self) { word in
                        VocabularyTagView(word: word) {
                            appState.removeVocabularyWord(word)
                        }
                    }
                }
            } else {
                Text("No custom vocabulary added yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func addWord() {
        appState.addVocabularyWord(newWord)
        newWord = ""
        isInputFocused = true
    }
}

/// A single vocabulary tag with remove button
struct VocabularyTagView: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.tertiary, lineWidth: 0.5)
        )
    }
}

/// A flow layout that wraps items to new lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Availability Section


/// Open-source availability section for the General settings tab
struct AvailabilitySection: View {
    var body: some View {
        Section {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Open Source")
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("No license key required")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } header: {
            Text("Availability")
        }
    }
}

// MARK: - Keyboard Shortcut View

/// Displays a keyboard shortcut as styled key caps
struct KeyboardShortcutView: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.tertiary, lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - App Footer View

/// Footer view showing app version and contact info
struct AppFooterView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }

    // TODO: Replace with actual email address
    private let contactEmail = "hello@yapper.to"
    // TODO: Replace with actual changelog URL
    private let changelogURL = "https://yapper.to/changelog/"

    var body: some View {
        VStack(spacing: 6) {
            Text("Yapper \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("Developed by voice using Yapper")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "mailto:\(contactEmail)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope")
                            .font(.caption2)
                        Text("Feedback")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                Text("·")
                    .foregroundStyle(.quaternary)

                Button {
                    if let url = URL(string: changelogURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("Changelog")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 750, height: 520)
}
