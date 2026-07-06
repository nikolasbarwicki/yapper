import Foundation

// MARK: - Transcription Backend Protocol

/// A backend that can load a model and transcribe audio.
///
/// Conformers wrap a specific ML framework (WhisperKit, FluidAudio, etc.)
/// and are owned by the `TranscriptionService` actor, which ensures
/// single-threaded access — so `@unchecked Sendable` is safe.
protocol TranscriptionBackend: Sendable {

    /// Which engine this backend represents.
    var engine: TranscriptionEngine { get }

    /// Whether a model is loaded and ready to transcribe.
    var isReady: Bool { get }

    /// Load (and optionally download) a model variant.
    /// - Parameters:
    ///   - variant: The model variant string (e.g. `"large-v3-turbo"`, `"tdt-0.6b-v2"`).
    ///   - progressHandler: Called with 0.0–1.0 progress. 0–0.8 = download, 0.8–1.0 = load.
    ///   - phaseHandler: Called when transitioning between download and load phases.
    func loadModel(
        variant: String,
        progressHandler: @escaping @Sendable (Double) -> Void,
        phaseHandler: @escaping @Sendable (ModelLoadPhase) -> Void
    ) async throws

    /// Release model resources.
    func unloadModel()

    /// Batch-transcribe audio.
    /// - Parameters:
    ///   - audioData: Raw PCM audio (16 kHz, mono, Float32).
    ///   - language: BCP-47 language code, or `"auto"`.
    ///   - customVocabulary: Words/phrases to bias recognition toward.
    /// - Returns: The transcribed text, or nil if nothing was detected.
    func transcribe(
        audioData: Data,
        language: String,
        customVocabulary: [String]
    ) async throws -> String?

    /// Stream-transcribe audio, calling `onToken` with delta text as decoding progresses.
    /// Backends that don't support true streaming should fall back to batch + single callback.
    /// - Returns: The final complete text.
    func transcribeStreaming(
        audioData: Data,
        language: String,
        customVocabulary: [String],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String?
}
