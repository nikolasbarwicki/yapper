import SwiftUI
import AppKit
import AVFoundation

// MARK: - Permission Status View

/// A single permission row showing status and grant button
struct PermissionStatusView: View {
    let title: String
    let description: String
    let isGranted: Bool
    let settingsURL: String
    /// Optional action to run instead of opening system settings (e.g., for microphone permission request)
    var grantAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.system(size: 16))
                .frame(width: 20)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Grant button (only shown when not granted)
            if !isGranted {
                Button("Grant Permission") {
                    if let grantAction {
                        grantAction()
                    } else {
                        openSettings()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func openSettings() {
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Permissions Status Section

/// A section showing both Microphone and Accessibility permission status
struct PermissionsStatusSection: View {
    @Environment(AppState.self) private var appState

    private var hasMissingPermissions: Bool {
        !appState.allPermissionsGranted
    }

    var body: some View {
        Section {
            PermissionStatusView(
                title: "Microphone",
                description: "Required to capture your voice for transcription",
                isGranted: appState.hasMicrophonePermission,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                grantAction: requestMicrophonePermission
            )

            PermissionStatusView(
                title: "Accessibility",
                description: "Required to type transcribed text into other apps",
                isGranted: appState.hasAccessibilityPermission,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        } header: {
            HStack {
                Text("Permissions")
                if hasMissingPermissions {
                    Spacer()
                    Text("Action Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.orange)
                        )
                }
            }
        } footer: {
            if hasMissingPermissions {
                Text("Grant the permissions above for Yapper to work properly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Request microphone permission using the system dialog, or open settings if previously denied
    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            // Permission hasn't been requested yet - show the system dialog
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run {
                    appState.updateMicrophonePermission(granted)
                }
            }
        case .denied, .restricted:
            // Permission was denied - open System Settings since the dialog won't show again
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .authorized:
            // Already authorized, update state
            appState.updateMicrophonePermission(true)
        @unknown default:
            // Fallback to opening settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Permissions Banner

/// Compact orange banner shown at the top of the settings detail area when permissions are missing
struct PermissionsBanner: View {
    @Environment(AppState.self) private var appState

    private var missingMic: Bool { !appState.hasMicrophonePermission }
    private var missingAccessibility: Bool { !appState.hasAccessibilityPermission }

    private var bannerText: String {
        if missingMic && missingAccessibility {
            return "Microphone and Accessibility access required"
        } else if missingMic {
            return "Microphone access required"
        } else {
            return "Accessibility access required"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
            Text(bannerText)
                .font(.callout)
            Spacer()
            Button("Grant Access") { grantAccess() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.gradient)
    }

    private func grantAccess() {
        if missingMic {
            requestMicrophonePermission()
        }
        // Always open accessibility settings if missing (mic dialog appears separately)
        if missingAccessibility {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run {
                    appState.updateMicrophonePermission(granted)
                }
            }
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .authorized:
            appState.updateMicrophonePermission(true)
        @unknown default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    Form {
        PermissionsStatusSection()
    }
    .formStyle(.grouped)
    .environment(AppState())
    .frame(width: 500)
}
