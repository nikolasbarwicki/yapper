import Foundation
import os

// MARK: - Transcription Service

/// Thin coordinator that delegates to the active `TranscriptionBackend`.
///
/// The public API is unchanged from the original WhisperKit-only version,
/// so `AppDelegate`, `FileTranscriptionView`, and other callers need no changes.
actor TranscriptionService {

    // MARK: - Properties

    /// The currently active backend (WhisperKit or FluidAudio).
    private var backend: (any TranscriptionBackend)?

    /// Whether the model is loaded and ready
    var isReady: Bool {
        backend?.isReady ?? false
    }

    /// Unload the current model to free memory
    func unloadModel() {
        AppLogger.transcription.info("Unloading current backend")
        backend?.unloadModel()
        backend = nil
    }

    // MARK: - Model Loading

    /// Load a model identified by the colon-prefixed format: `"whisper:large-v3-turbo"`, `"parakeet:tdt-0.6b-v2"`.
    ///
    /// Creates the appropriate backend, then delegates loading to it.
    /// The progress/phase callbacks follow the same convention as before:
    /// 0–0.8 = download, 0.8–1.0 = load/prewarm.
    func loadModel(
        modelName: String,
        progressHandler: @escaping @Sendable (Double) -> Void,
        phaseHandler: @escaping @Sendable (ModelLoadPhase) -> Void = { _ in }
    ) async throws {
        AppLogger.transcription.info("TranscriptionService: loading \(modelName)")

        // Parse the model identifier
        guard let modelId = ModelIdentifier(persistedValue: modelName) else {
            // Fallback for unexpected format — treat as whisper
            AppLogger.transcription.warning("Could not parse model ID '\(modelName)', falling back to WhisperKit")
            let whisper = WhisperKitBackend()
            try await whisper.loadModel(variant: modelName, progressHandler: progressHandler, phaseHandler: phaseHandler)
            self.backend = whisper
            return
        }

        // Always unload the previous backend before loading a new model.
        // Even within the same engine, model objects are memory-heavy and
        // should be explicitly released rather than relying on ARC alone.
        if let existing = backend {
            existing.unloadModel()
            backend = nil
        }

        // Create backend for the requested engine
        let newBackend: any TranscriptionBackend
        switch modelId.engine {
        case .whisper:
            newBackend = WhisperKitBackend()
        case .parakeet:
            newBackend = FluidAudioBackend()
        }

        try await newBackend.loadModel(
            variant: modelId.variant,
            progressHandler: progressHandler,
            phaseHandler: phaseHandler
        )

        self.backend = newBackend
    }

    // MARK: - Transcription

    /// Transcribe audio data to text (batch mode).
    func transcribe(
        audioData: Data,
        language: String = "en",
        customVocabulary: [String] = []
    ) async throws -> String? {
        guard let backend = backend else {
            throw TranscriptionError.modelNotLoaded
        }

        AppLogger.transcription.info("Transcription started via \(backend.engine.rawValue) backend")
        return try await backend.transcribe(
            audioData: audioData,
            language: language,
            customVocabulary: customVocabulary
        )
    }

    // MARK: - Streaming Transcription

    /// Transcribe audio data with token-by-token streaming via callback.
    func transcribeStreaming(
        audioData: Data,
        language: String = "en",
        customVocabulary: [String] = [],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String? {
        guard let backend = backend else {
            throw TranscriptionError.modelNotLoaded
        }

        AppLogger.transcription.info("Streaming transcription started via \(backend.engine.rawValue) backend")
        return try await backend.transcribeStreaming(
            audioData: audioData,
            language: language,
            customVocabulary: customVocabulary,
            onToken: onToken
        )
    }

    // MARK: - Engine Info

    /// The engine of the currently loaded backend, if any.
    var currentEngine: TranscriptionEngine? {
        backend?.engine
    }
}

// MARK: - Model Load Phase

/// Phases of the model loading process
enum ModelLoadPhase: Sendable {
    case downloading  // Downloading model files
    case loading      // Loading model into memory and prewarming
}

// MARK: - Errors

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)
    case downloadTimedOut

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech model not loaded. Please wait for download to complete."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .downloadTimedOut:
            return "Model download timed out. Please check your internet connection and try again."
        }
    }
}
