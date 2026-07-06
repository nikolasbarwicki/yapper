@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

// MARK: - Audio Recorder

/// Records audio from the system microphone.
///
/// SWIFT CONCEPT: AVAudioEngine
/// This is Apple's modern audio framework. Think of it as a graph of audio nodes:
/// - Input (microphone) -> Processing -> Output (speakers) or Buffer (recording)
/// We're using it to capture raw audio samples for WhisperKit.
///
/// WHY NOT AVAudioRecorder?
/// AVAudioRecorder saves to a file in a compressed format.
/// WhisperKit needs raw PCM audio data, so AVAudioEngine is more appropriate.
@MainActor
final class AudioRecorder {

    // MARK: - Constants

    /// Target sample rate for WhisperKit (16kHz mono)
    private let targetSampleRate: Double = 16000

    /// Amplification factor for audio level visualization.
    /// Audio RMS values are typically very small (0.01-0.1), so we boost them for visibility.
    private let audioLevelAmplificationFactor: Float = 10.0

    // MARK: - Properties

    /// The audio engine manages the audio processing graph
    private let audioEngine = AVAudioEngine()

    /// Accumulated audio samples during recording
    private var audioBuffer: [Float] = []

    /// Whether we're currently recording
    private var isRecording = false

    /// Callback for audio level updates (for visualization)
    private var levelCallback: (@Sendable (Float) -> Void)?

    // MARK: - Initialization

    init() {
        // Access inputNode early to trigger Core Audio hardware initialization.
        // Without this, the first recording attempt fails because the audio
        // subsystem hasn't finished initializing by the time start() is called.
        _ = audioEngine.inputNode
    }

    // MARK: - Permission Handling

    /// Check if we have microphone permission
    func checkPermission() async -> Bool {
        // AVCaptureDevice.authorizationStatus returns the current permission state
        // This is similar to checking navigator.permissions.query() in web
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            // Permission hasn't been asked yet
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Request microphone permission from the user
    func requestPermission() async -> Bool {
        // This triggers the system permission dialog
        // "Yapper would like to access the microphone"
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Device Selection

    /// Set the input device on the audio engine's input node.
    /// Pass nil to use the system default device.
    ///
    /// SWIFT CONCEPT: CoreAudio HAL on macOS
    /// AVAudioSession does NOT exist on macOS. Instead, we set the device
    /// directly on the AudioUnit backing AVAudioEngine's inputNode.
    /// Returns `true` if the device was set successfully (or nil was passed for system default).
    @discardableResult
    private func setInputDevice(_ deviceID: AudioDeviceID?) -> Bool {
        guard let deviceID else {
            AppLogger.audio.info("Using system default input device")
            return true
        }

        guard let audioUnit = audioEngine.inputNode.audioUnit else {
            AppLogger.audio.error("Cannot access inputNode audioUnit")
            return false
        }

        // Uninitialize → change device → reinitialize so the AudioUnit picks up
        // the new device's stream format. Without this, accessing inputFormat(forBus:0)
        // triggers -10877 (kAudioUnitErr_InvalidElement).
        AudioUnitUninitialize(audioUnit)

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        AudioUnitInitialize(audioUnit)

        if status == noErr {
            AppLogger.audio.info("Input device set to AudioDeviceID \(deviceID)")
            return true
        } else {
            AppLogger.audio.error("Failed to set input device (status: \(status)), falling back to default")
            return false
        }
    }

    // MARK: - Recording

    /// Start recording audio from the microphone.
    /// - Parameters:
    ///   - deviceID: CoreAudio device ID to record from, or nil for system default
    ///   - levelCallback: Called frequently with current audio level (0.0-1.0)
    /// - Returns: `true` if the requested device was used; `false` if it fell back to the system default.
    @discardableResult
    func startRecording(deviceID: AudioDeviceID? = nil, levelCallback: @escaping @Sendable (Float) -> Void) -> Bool {
        guard !isRecording else {
            AppLogger.audio.warning("Already recording")
            return false
        }

        self.levelCallback = levelCallback
        audioBuffer.removeAll()

        // Set the input device before accessing format (changing device changes native format)
        let deviceSetOK = setInputDevice(deviceID)

        do {
            // Get the input node (microphone)
            let inputNode = audioEngine.inputNode

            // Get the native format of the microphone
            let nativeFormat = inputNode.inputFormat(forBus: 0)

            // Create the format we want (16kHz mono for WhisperKit)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ) else {
                AppLogger.audio.error("Failed to create target audio format")
                return false
            }

            // Create a converter to resample from native format to 16kHz
            guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
                AppLogger.audio.error("Failed to create audio converter")
                return false
            }

            // SWIFT CONCEPT: Tap
            // A "tap" is like an event listener on the audio stream.
            // Every time audio comes through, this closure is called.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }

            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            AppLogger.audio.info("Recording started")
            return deviceSetOK

        } catch {
            AppLogger.audio.error("Failed to start recording: \(error.localizedDescription)")
            return false
        }
    }

    /// Process incoming audio buffer
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        // Calculate audio level for visualization
        // RMS (Root Mean Square) gives us the "volume" of the audio
        let level = calculateAudioLevel(buffer)
        levelCallback?(level)

        // Convert to 16kHz for WhisperKit
        guard let convertedBuffer = convertBuffer(buffer, converter: converter, targetFormat: targetFormat) else {
            return
        }

        // Extract float samples and add to our buffer
        if let channelData = convertedBuffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channelData,
                count: Int(convertedBuffer.frameLength)
            ))
            audioBuffer.append(contentsOf: samples)
        }
    }

    /// Convert audio buffer to target format (16kHz mono)
    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // Calculate the number of frames in the output buffer
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            return nil
        }

        var error: NSError?

        // SWIFT CONCEPT: withUnsafeMutablePointer
        // This gives us direct memory access (like pointers in C)
        // Swift usually hides pointers, but audio APIs need them for performance
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            AppLogger.audio.error("Audio conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    /// Calculate the audio level (RMS) for visualization
    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0

        // Calculate RMS (Root Mean Square)
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))

        // Convert to 0-1 range with amplification for visibility
        return min(rms * audioLevelAmplificationFactor, 1.0)
    }

    /// Stop recording and return the audio data
    func stopRecording() -> Data? {
        guard isRecording else {
            AppLogger.audio.warning("Not currently recording")
            return nil
        }

        // Stop the audio engine and remove the tap
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRecording = false
        levelCallback = nil

        AppLogger.audio.info("Recording stopped. Captured \(self.audioBuffer.count) samples")

        // Convert float array to Data for WhisperKit
        // SWIFT CONCEPT: withUnsafeBufferPointer
        // This creates a temporary pointer to the array's memory
        // We use it to create a Data object without copying
        let data = audioBuffer.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }

        return data
    }
}
