import CoreAudio
import Foundation

// MARK: - Audio Input Device

/// Represents a macOS audio input device discovered via CoreAudio.
///
/// SWIFT CONCEPT: Identifiable + Hashable
/// Identifiable lets SwiftUI use this in ForEach without explicit id:.
/// Hashable lets SwiftUI diff lists efficiently.
///
/// CoreAudio exposes two identifiers per device:
/// - `audioDeviceID` (AudioDeviceID / UInt32): Volatile runtime handle that changes across reboots.
/// - `uid` (String): Stable unique identifier from `kAudioDevicePropertyDeviceUID`, safe to persist.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// CoreAudio device ID (volatile — may change across reboots/reconnects)
    let audioDeviceID: AudioDeviceID

    /// Stable unique identifier string (persists across reboots).
    /// This is the value saved to UserDefaults for persistence.
    let uid: String

    /// Human-readable device name (e.g., "MacBook Pro Microphone", "Blue Yeti")
    let name: String

    // MARK: - Identifiable

    var id: String { uid }

    // Hashable/Equatable are compiler-synthesized, comparing all stored properties.
    // This ensures refreshDevices() detects audioDeviceID changes after device reconnects
    // (audioDeviceID is volatile and may change even when uid stays the same).
}
