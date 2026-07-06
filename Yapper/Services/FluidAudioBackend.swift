import Foundation
import os
import FluidAudio

// MARK: - FluidAudio Backend

/// Wraps FluidAudio (NVIDIA Parakeet TDT) to conform to `TranscriptionBackend`.
///
/// Marked `@unchecked Sendable` because it is only ever accessed from
/// the `TranscriptionService` actor, which serializes all calls.
final class FluidAudioBackend: TranscriptionBackend, @unchecked Sendable {

    let engine: TranscriptionEngine = .parakeet

    private var asrManager: AsrManager?
    private var modelLoaded = false

    var isReady: Bool { modelLoaded }

    // MARK: - Load

    func loadModel(
        variant: String,
        progressHandler: @escaping @Sendable (Double) -> Void,
        phaseHandler: @escaping @Sendable (ModelLoadPhase) -> Void
    ) async throws {
        AppLogger.transcription.info("FluidAudioBackend: loading variant \(variant)")

        let version: AsrModelVersion
        switch variant {
        case "tdt-0.6b-v2": version = .v2
        case "tdt-0.6b-v3": version = .v3
        default:
            AppLogger.transcription.error("Unknown Parakeet variant: \(variant)")
            throw TranscriptionError.transcriptionFailed("Unknown Parakeet variant: \(variant)")
        }

        // Phase 1: Download (0% – 80%)
        // Note: FluidAudio's download API doesn't expose a progress callback,
        // so we can only report 0% → 80% (complete). Granular progress isn't available.
        progressHandler(0.0)
        phaseHandler(.downloading)

        // Store models in Application Support alongside WhisperKit models
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("Yapper/parakeet-models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Check if already downloaded
        let alreadyCached = AsrModels.modelsExist(at: modelsDir, version: version)
        if alreadyCached {
            AppLogger.transcription.info("Parakeet models already cached, skipping download")
            progressHandler(0.8)
        } else {
            AppLogger.transcription.info("Downloading Parakeet \(variant) models...")
            // Download with 5-minute timeout (matches WhisperKitBackend)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await AsrModels.download(to: modelsDir, version: version)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    throw TranscriptionError.downloadTimedOut
                }
                // Wait for whichever finishes first
                try await group.next()
                group.cancelAll()
            }
            progressHandler(0.8)
        }

        // Phase 2: Load & compile (80% – 100%)
        phaseHandler(.loading)
        AppLogger.transcription.info("Loading Parakeet models into memory...")

        let models = try await AsrModels.load(from: modelsDir, version: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        self.asrManager = manager
        self.modelLoaded = true
        progressHandler(1.0)
        AppLogger.transcription.info("Parakeet model loaded successfully")
    }

    // MARK: - Unload

    func unloadModel() {
        AppLogger.transcription.info("FluidAudioBackend: unloading model")
        modelLoaded = false
        if let manager = asrManager {
            asrManager = nil
            Task { await manager.cleanup() }
        }
    }

    // MARK: - Batch Transcription

    func transcribe(
        audioData: Data,
        language: String,
        customVocabulary: [String]
    ) async throws -> String? {
        guard let asrManager = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        // Note: `language` and `customVocabulary` are accepted for protocol conformance
        // but not passed to FluidAudio. Parakeet v2 is English-only; v3 supports 25 languages
        // but FluidAudio's `transcribe()` API does not yet accept a language parameter.
        let samples = Self.audioDataToSamples(audioData)
        AppLogger.transcription.debug("Parakeet transcribing \(samples.count) samples (~\(Double(samples.count) / 16000)s)")

        let result = try await asrManager.transcribe(samples)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.transcription.info("Parakeet transcription complete: \(text.count) chars, RTFx: \(result.rtfx)")
        return text.isEmpty ? nil : text
    }

    // MARK: - Streaming Transcription

    /// Parakeet doesn't have a token-by-token streaming callback like WhisperKit.
    /// Since it transcribes at 110-190x real-time, 10s of audio completes in ~50-100ms,
    /// which is effectively instant. We batch-transcribe and emit the full text as a single token.
    func transcribeStreaming(
        audioData: Data,
        language: String,
        customVocabulary: [String],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String? {
        let text = try await transcribe(
            audioData: audioData,
            language: language,
            customVocabulary: customVocabulary
        )
        if let text = text {
            onToken(text)
        }
        return text
    }

    // MARK: - Helpers

    private static func audioDataToSamples(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }
    }
}
