import CoreAudio
import SwiftUI

// MARK: - Microphone Level View

/// A compact audio level meter bar for the Settings microphone picker.
/// Shows a thin animated bar that responds to the current input level,
/// letting users verify the correct microphone is selected.
struct MicrophoneLevelView: View {
    let audioDeviceManager: AudioDeviceManager
    let selectedDeviceID: AudioDeviceID?

    @State private var audioLevel: Float = 0.0

    /// Tracks the current monitoring session so that stale callbacks are ignored
    /// and so the correct session is stopped on disappear.
    @State private var monitoringSessionID: UUID?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(height: 4)

                    // Level fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor)
                        .frame(width: max(0, geometry.size.width * CGFloat(audioLevel)), height: 4)
                        .animation(.easeOut(duration: 0.08), value: audioLevel)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
        }
        .onAppear {
            startMonitoring(deviceID: selectedDeviceID)
        }
        .onDisappear {
            stopMonitoring()
        }
        .onChange(of: selectedDeviceID) { _, newDeviceID in
            // Restart monitoring on the newly selected device
            startMonitoring(deviceID: newDeviceID)
        }
    }

    /// Color shifts from green to yellow to red based on level
    private var levelColor: Color {
        if audioLevel > 0.8 {
            return .red
        } else if audioLevel > 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    private func startMonitoring(deviceID: AudioDeviceID?) {
        // Generate a new session ID; any prior session's callbacks will be ignored
        let sessionID = UUID()
        monitoringSessionID = sessionID
        audioLevel = 0

        audioDeviceManager.startLevelMonitoring(deviceID: deviceID) { level in
            Task { @MainActor in
                // Only update if this callback belongs to the current session
                guard monitoringSessionID == sessionID else { return }
                audioLevel = level
            }
        }
    }

    private func stopMonitoring() {
        monitoringSessionID = nil
        audioDeviceManager.stopLevelMonitoring()
        audioLevel = 0
    }
}
