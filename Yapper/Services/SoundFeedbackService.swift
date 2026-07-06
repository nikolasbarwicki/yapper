import AppKit

/// Plays system sounds for key app events (recording start, transcription complete, error).
/// Disabled by default — users opt in via Settings → General.
@MainActor
final class SoundFeedbackService {

    enum SoundEvent {
        case recordingStarted
        case transcriptionComplete
        case error
    }

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func play(_ event: SoundEvent) {
        guard appState.soundFeedbackEnabled else { return }

        let soundName: NSSound.Name
        switch event {
        case .recordingStarted:
            soundName = "Purr"
        case .transcriptionComplete:
            soundName = "Pop"
        case .error:
            soundName = "Funk"
        }

        NSSound(named: soundName)?.play()
    }
}
