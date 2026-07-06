import Foundation
import os
@preconcurrency import WhisperKit

// MARK: - WhisperKit Backend

/// Wraps WhisperKit to conform to `TranscriptionBackend`.
///
/// Marked `@unchecked Sendable` because it is only ever accessed from
/// the `TranscriptionService` actor, which serializes all calls.
final class WhisperKitBackend: TranscriptionBackend, @unchecked Sendable {

    let engine: TranscriptionEngine = .whisper

    private var whisperKit: WhisperKit?

    var isReady: Bool { whisperKit != nil }

    // MARK: - Load

    func loadModel(
        variant: String,
        progressHandler: @escaping @Sendable (Double) -> Void,
        phaseHandler: @escaping @Sendable (ModelLoadPhase) -> Void
    ) async throws {
        AppLogger.transcription.info("WhisperKitBackend: loading variant \(variant)")

        let fullModelName = ModelIdentifier.whisperKitModelName(for: variant)

        // Models directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("Yapper/models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Check if model is already cached (HuggingFace Hub stores at: <base>/models/<repo>/<variant>/)
        let hubCacheDir = modelsDir
            .appendingPathComponent("models/\(ModelIdentifier.whisperKitHubRepo)", isDirectory: true)
            .appendingPathComponent(fullModelName, isDirectory: true)
        let alreadyCached = (try? FileManager.default.contentsOfDirectory(atPath: hubCacheDir.path))?.isEmpty == false

        let modelFolder: URL
        if alreadyCached {
            AppLogger.transcription.info("WhisperKit model already cached, skipping download")
            progressHandler(0.0)
            phaseHandler(.downloading)
            progressHandler(0.8)
            modelFolder = hubCacheDir
        } else {
            AppLogger.transcription.info("Downloading model: \(fullModelName)")
            progressHandler(0.0)
            phaseHandler(.downloading)

            // Download with timeout
            modelFolder = try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await WhisperKit.download(
                        variant: fullModelName,
                        downloadBase: modelsDir,
                        progressCallback: { progress in
                            let downloadProgress = progress.fractionCompleted * 0.8
                            AppLogger.transcription.debug("Download progress: \(Int(progress.fractionCompleted * 100))%")
                            progressHandler(downloadProgress)
                        }
                    )
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    throw TranscriptionError.downloadTimedOut
                }

                guard let result = try await group.next() else {
                    throw TranscriptionError.downloadTimedOut
                }
                group.cancelAll()
                return result
            }
        }

        AppLogger.transcription.info("Model folder: \(modelFolder.path)")
        progressHandler(0.8)
        phaseHandler(.loading)

        // Initialize WhisperKit
        whisperKit = try await WhisperKit(
            modelFolder: modelFolder.path,
            tokenizerFolder: modelsDir,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: true,
            logLevel: .debug,
            prewarm: true,
            load: true,
            download: false
        )

        progressHandler(1.0)
        AppLogger.transcription.info("WhisperKit model loaded successfully")
    }

    // MARK: - Unload

    func unloadModel() {
        AppLogger.transcription.info("WhisperKitBackend: unloading model")
        whisperKit = nil
    }

    // MARK: - Batch Transcription

    func transcribe(
        audioData: Data,
        language: String,
        customVocabulary: [String]
    ) async throws -> String? {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let samples = Self.audioDataToSamples(audioData)
        let languageCode: String? = language == "auto" ? nil : language

        let promptTokens = Self.buildPromptTokens(
            vocabulary: customVocabulary,
            tokenizer: whisperKit.tokenizer
        )

        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode,
            temperature: 0,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true
        )

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        guard let result = results.first else { return nil }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Streaming Transcription

    func transcribeStreaming(
        audioData: Data,
        language: String,
        customVocabulary: [String],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String? {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let samples = Self.audioDataToSamples(audioData)
        let languageCode: String? = language == "auto" ? nil : language

        let promptTokens = Self.buildPromptTokens(
            vocabulary: customVocabulary,
            tokenizer: whisperKit.tokenizer
        )

        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode,
            temperature: 0,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true
        )

        // Delta tracking across 30-second windows
        final class StreamState: @unchecked Sendable {
            private let lock = NSLock()
            private var _previousText: String = ""
            private var _lastWindowId: Int = -1

            func computeDelta(text: String, windowId: Int) -> String {
                lock.lock()
                defer { lock.unlock() }

                let cleanedText = text.replacingOccurrences(
                    of: "<\\|[^|]*\\|>",
                    with: "",
                    options: .regularExpression
                )

                if windowId != _lastWindowId {
                    _lastWindowId = windowId
                    _previousText = ""
                }

                let delta: String
                if cleanedText.count > _previousText.count {
                    delta = String(cleanedText[cleanedText.index(cleanedText.startIndex, offsetBy: _previousText.count)...])
                    _previousText = cleanedText
                } else {
                    delta = ""
                }
                return delta
            }
        }

        let state = StreamState()

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { progress in
                let delta = state.computeDelta(text: progress.text, windowId: progress.windowId)
                if !delta.isEmpty {
                    onToken(delta)
                }
                return nil
            }
        )

        let fullText = results
            .map {
                $0.text
                    .replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fullText.isEmpty ? nil : fullText
    }

    // MARK: - Helpers

    private static func audioDataToSamples(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }
    }

    private static func buildPromptTokens(vocabulary: [String], tokenizer: (any WhisperTokenizer)?) -> [Int]? {
        guard !vocabulary.isEmpty, let tokenizer = tokenizer else { return nil }
        let promptText = vocabulary.joined(separator: ", ")
        let tokens = tokenizer.encode(text: promptText)
        let specialTokenBegin = tokenizer.specialTokens.specialTokenBegin
        let filtered = tokens.filter { $0 < specialTokenBegin }
        return filtered.isEmpty ? nil : filtered
    }
}
