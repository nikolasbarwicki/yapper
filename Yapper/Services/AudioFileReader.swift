@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

// MARK: - Audio File Reader

/// Reads and converts audio files to WhisperKit-compatible format (16kHz mono Float32 PCM).
/// Supports MP3, WAV, and M4A formats.
final class AudioFileReader {

    // MARK: - Types

    /// Information about an audio file
    struct AudioFileInfo: Equatable {
        let url: URL
        let fileName: String
        let fileSize: Int64
        let duration: TimeInterval
    }

    /// Errors that can occur during audio file reading
    enum AudioFileError: LocalizedError {
        case unsupportedFormat
        case fileNotFound
        case invalidAudioFile
        case conversionFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Unsupported audio format. Please use MP3, WAV, or M4A files."
            case .fileNotFound:
                return "The audio file could not be found."
            case .invalidAudioFile:
                return "The file does not contain valid audio data."
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .cancelled:
                return "Audio loading was cancelled."
            }
        }
    }

    /// Supported audio file types
    static let supportedTypes: [UTType] = [.mp3, .wav, .mpeg4Audio]

    // MARK: - Properties

    /// WhisperKit expects 16kHz mono audio
    private let targetSampleRate: Double = 16000

    /// Thread-safe cancellation flag using a lock
    private let cancelLock = NSLock()
    private var _isCancelled = false
    private var isCancelled: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return _isCancelled
        }
        set {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            _isCancelled = newValue
        }
    }

    // MARK: - Public Methods

    /// Get information about an audio file
    /// - Parameter url: The URL of the audio file
    /// - Returns: Information about the audio file
    func getFileInfo(url: URL) async throws -> AudioFileInfo {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileError.fileNotFound
        }

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Get audio duration using AVAudioFile
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioFileError.invalidAudioFile
        }

        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

        return AudioFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            duration: duration
        )
    }

    /// Load and convert an audio file to WhisperKit format
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - progressHandler: Called with progress (0.0-1.0) during loading
    /// - Returns: Audio data as 16kHz mono Float32 PCM
    func loadAudio(url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> Data {
        isCancelled = false

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileError.fileNotFound
        }

        // Read the audio file
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioFileError.invalidAudioFile
        }

        let sourceFormat = audioFile.processingFormat
        let sourceFrameCount = AVAudioFrameCount(audioFile.length)

        print("📁 Loading audio file: \(url.lastPathComponent)")
        print("📁 Source format: \(sourceFormat)")
        print("📁 Frame count: \(sourceFrameCount)")

        // Create target format (16kHz mono Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileError.conversionFailed("Failed to create target audio format")
        }

        // Create converter
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFileError.conversionFailed("Failed to create audio converter")
        }

        // Calculate output frame count
        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(sourceFrameCount) * ratio)

        // Read and convert in chunks for progress reporting
        let chunkSize: AVAudioFrameCount = 16384
        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(outputFrameCount))

        var framesRead: AVAudioFrameCount = 0

        while framesRead < sourceFrameCount {
            // Check for cancellation
            if isCancelled {
                throw AudioFileError.cancelled
            }

            // Calculate frames to read in this chunk
            let framesToRead = min(chunkSize, sourceFrameCount - framesRead)

            // Create input buffer for this chunk
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: framesToRead
            ) else {
                throw AudioFileError.conversionFailed("Failed to create input buffer")
            }

            // Read frames from file
            do {
                try audioFile.read(into: inputBuffer, frameCount: framesToRead)
            } catch {
                throw AudioFileError.conversionFailed("Failed to read audio file: \(error.localizedDescription)")
            }

            // Calculate output size for this chunk
            let chunkOutputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

            guard let chunkOutputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: chunkOutputFrameCount
            ) else {
                throw AudioFileError.conversionFailed("Failed to create chunk output buffer")
            }

            // Convert this chunk
            var error: NSError?
            let status = converter.convert(to: chunkOutputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error {
                throw AudioFileError.conversionFailed(error?.localizedDescription ?? "Unknown conversion error")
            }

            // Extract samples from converted buffer
            if let channelData = chunkOutputBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: Int(chunkOutputBuffer.frameLength)
                ))
                allSamples.append(contentsOf: samples)
            }

            framesRead += inputBuffer.frameLength

            // Report progress
            let progress = Double(framesRead) / Double(sourceFrameCount)
            await MainActor.run {
                progressHandler(progress)
            }

            // Yield to allow cancellation checks
            await Task.yield()
        }

        print("📁 Conversion complete: \(allSamples.count) samples")

        // Convert float array to Data
        let data = allSamples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }

        return data
    }

    /// Cancel the current loading operation
    func cancel() {
        isCancelled = true
    }
}
