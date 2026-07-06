import SwiftUI
import UniformTypeIdentifiers

// MARK: - Progress Coordinator

/// A Sendable coordinator for safely updating progress across actor boundaries
@MainActor
final class ProgressCoordinator: @unchecked Sendable {
    private var updateHandler: (@MainActor (Double) -> Void)?

    func setHandler(_ handler: @escaping @MainActor (Double) -> Void) {
        updateHandler = handler
    }

    /// Returns a Sendable closure for progress reporting that can be passed to async APIs
    func makeProgressHandler() -> @Sendable (Double) -> Void {
        return { [weak self] progress in
            Task { @MainActor in
                self?.updateHandler?(progress)
            }
        }
    }
}

// MARK: - File Transcription State

/// Represents the state of file transcription
enum FileTranscriptionState: Equatable {
    case idle
    case fileSelected(AudioFileReader.AudioFileInfo)
    case loading(progress: Double)
    case transcribing(progress: Double)
    case completed(text: String)
    case error(message: String)
    case cancelled

    var isProcessing: Bool {
        switch self {
        case .loading, .transcribing:
            return true
        default:
            return false
        }
    }
}

// MARK: - File Transcription View

/// SwiftUI view for transcribing audio files
struct FileTranscriptionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // State
    @State private var state: FileTranscriptionState = .idle
    @State private var showCancelConfirmation = false
    @State private var showCopiedFeedback = false

    // Services - fresh AudioFileReader created per transcription
    @State private var currentAudioFileReader: AudioFileReader?
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var selectedFileInfo: AudioFileReader.AudioFileInfo?
    @State private var progressCoordinator = ProgressCoordinator()

    // Transcription service passed via init (not fragile AppDelegate cast)
    private let transcriptionService: TranscriptionService

    // Callback to provide cancel handler to window controller
    private let onCancelHandlerReady: ((@escaping () -> Void) -> Void)?

    init(
        transcriptionService: TranscriptionService,
        onCancelHandlerReady: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.transcriptionService = transcriptionService
        self.onCancelHandlerReady = onCancelHandlerReady
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content based on state
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer with actions
            footerView
        }
        .frame(width: 480, height: 400)
        .alert("Cancel Transcription?", isPresented: $showCancelConfirmation) {
            Button("Continue", role: .cancel) { }
            Button("Cancel", role: .destructive) {
                cancelTranscription()
            }
        } message: {
            Text("The transcription is still in progress. Are you sure you want to cancel?")
        }
        .onAppear {
            // Register cancel handler with window controller
            onCancelHandlerReady? { [self] in
                cancelTranscription()
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribe Audio File")
                    .font(.headline)
                Text("Convert audio files to text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .idle:
            filePickerView

        case .fileSelected(let fileInfo):
            fileInfoView(fileInfo)

        case .loading(let progress):
            progressView(title: "Loading Audio", progress: progress, indeterminate: false)

        case .transcribing:
            progressView(title: "Transcribing", progress: 0, indeterminate: true)

        case .completed(let text):
            completedView(text: text)

        case .error(let message):
            errorView(message: message)

        case .cancelled:
            cancelledView
        }
    }

    // MARK: - File Picker View

    private var filePickerView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Select an Audio File")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("Supported formats: MP3, WAV, M4A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Choose File...") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - File Info View

    private func fileInfoView(_ fileInfo: AudioFileReader.AudioFileInfo) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // File icon
            Image(systemName: "doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            // File details
            VStack(spacing: 12) {
                Text(fileInfo.fileName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Label(formatDuration(fileInfo.duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(formatFileSize(fileInfo.fileSize), systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Change file button
            Button("Choose Different File") {
                selectFile()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()
        }
        .padding()
    }

    // MARK: - Progress View

    private func progressView(title: String, progress: Double, indeterminate: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()

            if indeterminate {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)

                if !indeterminate {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let fileInfo = selectedFileInfo {
                    Text(fileInfo.fileName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Completed View

    private func completedView(text: String) -> some View {
        VStack(spacing: 16) {
            // Success indicator
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Transcription Complete")
                    .font(.headline)

                Spacer()

                // Copy button
                Button {
                    copyToClipboard(text)
                } label: {
                    Label(showCopiedFeedback ? "Copied!" : "Copy", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopiedFeedback ? .green : .blue)
            }
            .padding(.horizontal)
            .padding(.top)

            // Transcript text
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            )
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Transcription Failed")
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Try Again") {
                if let fileInfo = selectedFileInfo {
                    state = .fileSelected(fileInfo)
                } else {
                    state = .idle
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Cancelled View

    private var cancelledView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Transcription Cancelled")
                    .font(.headline)

                Text("The transcription was cancelled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Select New File") {
                state = .idle
                selectedFileInfo = nil
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            // Cancel/Close button
            Button(state.isProcessing ? "Cancel" : "Close") {
                if state.isProcessing {
                    showCancelConfirmation = true
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            // Action button
            switch state {
            case .fileSelected:
                Button("Start Transcription") {
                    startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isModelLoaded)

            case .completed:
                Button("Transcribe Another") {
                    state = .idle
                    selectedFileInfo = nil
                }
                .buttonStyle(.borderedProminent)

            default:
                EmptyView()
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFileReader.supportedTypes
        panel.message = "Select an audio file to transcribe"
        panel.prompt = "Select"

        // Start in home directory to avoid immediate permission prompts for Documents/Desktop
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            loadFileInfo(url: url)
        }
    }

    private func loadFileInfo(url: URL) {
        Task {
            do {
                // Create a fresh reader just for getting file info
                let reader = AudioFileReader()
                let fileInfo = try await reader.getFileInfo(url: url)
                await MainActor.run {
                    selectedFileInfo = fileInfo
                    state = .fileSelected(fileInfo)
                }
            } catch {
                await MainActor.run {
                    state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func startTranscription() {
        guard let fileInfo = selectedFileInfo else { return }

        appState.isTranscribingFile = true

        // Create a fresh AudioFileReader for this transcription
        let audioFileReader = AudioFileReader()
        currentAudioFileReader = audioFileReader

        transcriptionTask = Task {
            do {
                // Phase 1: Load and convert audio
                await MainActor.run {
                    state = .loading(progress: 0)
                }

                // Set up progress handler through coordinator
                progressCoordinator.setHandler { progress in
                    state = .loading(progress: progress)
                }

                let audioData = try await audioFileReader.loadAudio(
                    url: fileInfo.url,
                    progressHandler: progressCoordinator.makeProgressHandler()
                )

                // Check for cancellation
                if Task.isCancelled {
                    await MainActor.run { finishWithCancelled() }
                    return
                }

                // Phase 2: Transcribe (spinner - no progress available)
                await MainActor.run {
                    state = .transcribing(progress: 0)
                }

                guard let transcribedText = try await transcriptionService.transcribe(
                    audioData: audioData,
                    language: appState.selectedLanguage,
                    customVocabulary: appState.customVocabulary
                ) else {
                    throw AudioFileReader.AudioFileError.conversionFailed("No transcription result")
                }

                // Check for cancellation
                if Task.isCancelled {
                    await MainActor.run { finishWithCancelled() }
                    return
                }

                // Save to history and complete
                await MainActor.run {
                    let record = TranscriptRecord(
                        text: transcribedText,
                        duration: fileInfo.duration,
                        language: appState.selectedLanguage,
                        sourceFileName: fileInfo.fileName,
                        sourceFilePath: fileInfo.url.path,
                        sourceFileSize: fileInfo.fileSize
                    )
                    TranscriptHistoryManager.shared.addRecord(record)

                    state = .completed(text: transcribedText)
                    appState.isTranscribingFile = false
                    currentAudioFileReader = nil
                }

            } catch is CancellationError {
                await MainActor.run { finishWithCancelled() }
            } catch AudioFileReader.AudioFileError.cancelled {
                await MainActor.run { finishWithCancelled() }
            } catch {
                await MainActor.run {
                    state = .error(message: error.localizedDescription)
                    appState.isTranscribingFile = false
                    currentAudioFileReader = nil
                }
            }
        }
    }

    /// Centralized handler for cancellation to avoid race conditions
    private func finishWithCancelled() {
        state = .cancelled
        appState.isTranscribingFile = false
        currentAudioFileReader = nil
    }

    private func cancelTranscription() {
        currentAudioFileReader?.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        finishWithCancelled()
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        DurationFormatter.format(duration)
    }

    private func formatFileSize(_ size: Int64) -> String {
        FileSizeFormatter.format(size)
    }
}

// MARK: - Preview

#Preview {
    FileTranscriptionView(transcriptionService: TranscriptionService())
        .environment(AppState())
}
