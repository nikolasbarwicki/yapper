@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

// MARK: - Audio Device Manager

/// Manages audio input device enumeration, hot-plug monitoring, and level metering via CoreAudio.
///
/// SWIFT CONCEPT: CoreAudio C API bridge
/// macOS has no AVAudioSession (that's iOS-only). Instead we use the CoreAudio
/// Hardware Abstraction Layer (HAL) C functions: AudioObjectGetPropertyData,
/// AudioObjectAddPropertyListener, AudioUnitSetProperty, etc.
/// These use AudioObjectPropertyAddress structs to query/set device properties.
@MainActor
final class AudioDeviceManager {

    // MARK: - Properties

    /// Current list of available input devices, updated on hot-plug events
    private(set) var availableDevices: [AudioInputDevice] = []

    /// Callback fired when device list changes (hot-plug/unplug)
    var onDevicesChanged: (() -> Void)?

    /// Whether the CoreAudio property listener is installed
    private var listenerInstalled = false

    // MARK: - Level Monitoring

    /// Temporary audio engine used for level monitoring in Settings UI
    private var levelEngine: AVAudioEngine?

    /// Whether level monitoring is active
    private(set) var isMonitoringLevel = false

    /// Amplification factor for audio level visualization (matches AudioRecorder)
    private let audioLevelAmplificationFactor: Float = 10.0

    // MARK: - Initialization

    init() {
        availableDevices = Self.enumerateInputDevices()
        installDeviceChangeListener()
    }

    deinit {
        // deinit is nonisolated in Swift 6, so we inline the cleanup
        // rather than calling the @MainActor-isolated method.
        guard listenerInstalled else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            selfPtr
        )
    }

    // MARK: - Device Enumeration

    /// Enumerate all audio input devices on the system.
    /// Filters to devices with at least one input channel.
    static func enumerateInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get the total size needed to hold all device IDs
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else {
            AppLogger.audio.error("Failed to get audio devices data size: \(status)")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            AppLogger.audio.error("Failed to get audio devices: \(status)")
            return []
        }

        // Filter to physical devices with input channels (matches macOS System Settings behavior)
        var devices: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            guard isPhysicalDevice(deviceID),
                  hasInputChannels(deviceID),
                  let name = getDeviceName(deviceID),
                  let uid = getDeviceUID(deviceID) else {
                continue
            }
            devices.append(AudioInputDevice(
                audioDeviceID: deviceID,
                uid: uid,
                name: name
            ))
        }

        return devices
    }

    // MARK: - Device Properties

    /// Check if a device is a physical (non-virtual, non-aggregate) device.
    /// Filters out internal aggregate devices (e.g. CADefaultDeviceAggregate)
    /// and virtual devices created by apps (e.g. ZoomAudioDevice),
    /// matching the behavior of macOS System Settings > Sound > Input.
    private static func isPhysicalDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &transportType
        )
        guard status == noErr else { return true } // If we can't determine, include it

        // Exclude aggregate devices (system internal) and virtual devices (app-created)
        let excludedTypes: [UInt32] = [
            kAudioDeviceTransportTypeAggregate,
            kAudioDeviceTransportTypeVirtual,
        ]

        return !excludedTypes.contains(transportType)
    }

    /// Check if a device has input channels (i.e., is a microphone / input device)
    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        // Allocate buffer for the AudioBufferList
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }

        let getStatus = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, data
        )
        guard getStatus == noErr else { return false }

        let bufferList = data.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let totalChannels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return totalChannels > 0
    }

    /// Get the human-readable name of a device
    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        getCFStringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    /// Get the stable UID string of a device (persists across reboots)
    private static func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        getCFStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    /// Read a CFString property from a CoreAudio device.
    /// Uses Unmanaged<CFString> to avoid "forming UnsafeMutableRawPointer to CFString" warnings,
    /// since Unmanaged is a plain struct (no ARC reference for the compiler to worry about).
    private static func getCFStringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &value
        )
        // AudioObjectGetPropertyData transfers ownership of CFType objects to the caller
        guard status == noErr, let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }

    // MARK: - Resolve UID to DeviceID

    /// Resolve a persisted UID to a runtime AudioDeviceID.
    /// Returns nil if the device is not currently connected.
    func resolveDeviceID(forUID uid: String) -> AudioDeviceID? {
        availableDevices.first { $0.uid == uid }?.audioDeviceID
    }

    // MARK: - Hot-plug Monitoring

    /// Install a CoreAudio property listener for device connect/disconnect events
    private func installDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // SWIFT CONCEPT: Unmanaged
        // CoreAudio callbacks are C functions — they can't capture Swift context.
        // We pass `self` as an opaque pointer (clientData) and reconstruct it in the callback.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            selfPtr
        )

        if status == noErr {
            listenerInstalled = true
            AppLogger.audio.info("Audio device change listener installed")
        } else {
            AppLogger.audio.error("Failed to install device change listener: \(status)")
        }
    }

    /// Remove the CoreAudio property listener
    private func removeDeviceChangeListener() {
        guard listenerInstalled else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangeCallback,
            selfPtr
        )
        listenerInstalled = false
    }

    /// Refresh the device list — called from the CoreAudio callback
    func refreshDevices() {
        let newDevices = Self.enumerateInputDevices()
        if newDevices != availableDevices {
            availableDevices = newDevices
            AppLogger.audio.info("Audio devices changed: \(newDevices.count) input device(s)")
            onDevicesChanged?()
        }
    }

    // MARK: - Level Monitoring (for Settings UI)

    /// Start monitoring audio levels from a specific device (or system default if nil).
    /// The callback receives a normalized level (0.0–1.0) on the main thread.
    func startLevelMonitoring(deviceID: AudioDeviceID?, callback: @escaping @Sendable (Float) -> Void) {
        stopLevelMonitoring()

        let engine = AVAudioEngine()

        // Set the input device if specified.
        // SWIFT CONCEPT: CoreAudio AudioUnit lifecycle
        // After changing the device via AudioUnitSetProperty, the AudioUnit must be
        // uninitialized and reinitialized so it picks up the new device's stream format.
        // Without this, accessing inputFormat(forBus:0) triggers -10877 (InvalidElement).
        if let deviceID {
            guard let audioUnit = engine.inputNode.audioUnit else {
                AppLogger.audio.error("Level monitor: cannot access inputNode audioUnit")
                return
            }

            // Uninitialize → change device → reinitialize
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
            if status != noErr {
                AppLogger.audio.error("Level monitor: failed to set device (status: \(status))")
            }

            AudioUnitInitialize(audioUnit)
        }

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        let amplification = audioLevelAmplificationFactor

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let level = min(rms * amplification, 1.0)

            callback(level)
        }

        do {
            engine.prepare()
            try engine.start()
            levelEngine = engine
            isMonitoringLevel = true
            AppLogger.audio.info("Level monitoring started")
        } catch {
            AppLogger.audio.error("Failed to start level monitoring: \(error.localizedDescription)")
        }
    }

    /// Stop the level monitoring engine
    func stopLevelMonitoring() {
        guard let engine = levelEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        levelEngine = nil
        isMonitoringLevel = false
        AppLogger.audio.info("Level monitoring stopped")
    }
}

// MARK: - CoreAudio C Callback

/// Free function for the CoreAudio property listener callback.
/// CoreAudio callbacks must be plain C functions — they cannot be closures or instance methods.
/// We reconstruct the AudioDeviceManager from the opaque clientData pointer and dispatch to MainActor.
private func audioDeviceChangeCallback(
    objectID: AudioObjectID,
    numberAddresses: UInt32,
    addresses: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()

    Task { @MainActor in
        manager.refreshDevices()
    }

    return noErr
}
