# Yapper

Yapper is a native macOS menu bar app for voice-to-text dictation. It records speech, transcribes it on your Mac with WhisperKit or FluidAudio, optionally sends text to an LLM for transformation or Q&A, and types the result into the focused app.

Yapper is now open source. No license key, trial, purchase, or activation is required.

## Features

| Feature | Description |
| --- | --- |
| Voice dictation | Start and stop recording with a global keyboard shortcut. |
| On-device transcription | Use WhisperKit or FluidAudio/NVIDIA Parakeet models locally. |
| Text injection | Type transcribed text into the currently focused field. |
| File transcription | Transcribe dropped audio files from a dedicated window. |
| Language switching | Configure primary and secondary languages and toggle quickly. |
| Optional AI tools | Transform selected text or ask questions with Gemini, OpenAI, Anthropic, or xAI API keys. |
| Transcript history | Search previous transcripts and manage retention. |
| Model storage | View downloaded model size and clear local models. |

## Requirements

- macOS 14.0 Sonoma or newer
- Xcode 15.0 or newer
- Apple Silicon Mac recommended for local speech model performance
- Microphone permission
- Accessibility permission if you want Yapper to type into other apps

## Install

There are two supported paths.

### Download A Release

1. Open the repository's GitHub Releases page.
2. Download the latest `Yapper.dmg` or `Yapper.zip` if a community release is available.
3. Move `Yapper.app` to `/Applications`.
4. On first launch, right-click `Yapper.app` and choose `Open` if macOS shows an unidentified developer warning.
5. Grant microphone and accessibility permissions when prompted.

Community builds may be unsigned unless a maintainer publishes a notarized release.

### Build From Source

```bash
git clone https://github.com/nikolasbarwicki/yapper-app.git
cd yapper-app
open Yapper.xcodeproj
```

Then in Xcode:

1. Select the `Yapper` scheme.
2. Select your Mac as the run destination.
3. Press `Cmd+R`.
4. If signing fails, open the target settings and choose your personal development team or use local signing settings.

You can also create local distribution artifacts:

```bash
./scripts/build-release.sh
```

The script writes `Yapper.app`, `Yapper.zip`, and `Yapper.dmg` into `dist/`.

## First Launch

1. Grant microphone access so Yapper can record audio.
2. Grant accessibility access so Yapper can type into other apps.
3. Wait for the selected transcription model to download and load. The default Parakeet model is around 800 MB.
4. Press `Option+Space` to record.

## Keyboard Shortcuts

| Action | Default | Customizable |
| --- | --- | --- |
| Start/stop recording | `Option+Space` | Yes |
| Cancel recording | `Escape` | Yes |
| Toggle language | `Shift+Option+L` | Yes |
| Toggle auto-type | `Shift+Option+T` | Yes |

## AI Providers

Yapper works without any cloud API keys for normal dictation. Optional AI Transform and Q&A features require your own provider key.

| Provider | Example models in the app |
| --- | --- |
| Gemini | `gemini-3-flash-preview`, `gemini-3-pro-preview` |
| OpenAI | `gpt-5-mini`, `gpt-5-nano` |
| Anthropic | `claude-sonnet-4-5`, `claude-haiku-4-5` |
| xAI | `grok-4`, `grok-4-1-fast` |

API keys are stored locally in Keychain. AI requests are sent to the selected provider only when you use an AI feature.

## Privacy

- Speech transcription runs locally for the built-in transcription engines.
- Downloaded speech models are stored on your Mac.
- Transcript history is stored locally.
- Optional AI features send the selected text, transcribed instruction, or question to the provider you configure.
- Yapper needs accessibility access only to read selected text for AI Transform and type output into focused apps.

## Documentation

- [User Guide](docs/user-guide.md)
- [Technical Guide](docs/technical-guide.md)
- [Documentation Index](docs/INDEX.md)
- [Release Guide](docs/release-guide.md)

Older generated analysis docs live under `docs/archive/` and are historical only.

## Repository Layout

```text
Yapper/
├── App/          # App lifecycle and menu bar coordination
├── Models/       # App state and domain models
├── Services/     # Audio, transcription, LLM, hotkeys, text injection, storage
├── Views/        # SwiftUI/AppKit windows and settings
├── Utilities/    # Shared formatting, logging, model storage helpers
└── Resources/    # Assets

docs/             # User, technical, release, and archived historical documentation
scripts/          # Build and release helper scripts
```

## Contributing

This project is maintained on a best-effort basis. Bug fixes, documentation improvements, release automation, and compatibility updates are welcome.

Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Please do not open a public issue for sensitive vulnerability reports. See [SECURITY.md](SECURITY.md).

## License

Yapper is available under the [MIT License](LICENSE).
