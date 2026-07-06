# Contributing

Thanks for helping keep Yapper useful.

Yapper is maintained on a best-effort basis. The most helpful contributions are focused bug fixes, documentation improvements, compatibility updates for newer macOS/Xcode versions, and release automation.

## Development Setup

1. Install macOS 14 or newer and Xcode 15 or newer.
2. Clone the repository.
3. Open `Yapper.xcodeproj`.
4. Let Xcode resolve Swift Package Manager dependencies.
5. Build and run the `Yapper` scheme.

If signing fails, select the Yapper target in Xcode and configure a local development team.

## Before Opening A Pull Request

- Keep changes focused.
- Update docs when behavior changes.
- Test dictation, permissions, settings, and any touched feature manually.
- Avoid committing local build output from `dist/`, `DerivedData`, or Xcode user state.
- Do not add API keys, signing certificates, Sparkle private keys, provisioning profiles, or notarization credentials.

## Useful Commands

```bash
./scripts/build-release.sh
```

Use this to create local `dist/` artifacts. Published releases may require signing and notarization; see `docs/release-guide.md`.

## Maintenance Priorities

1. Keep the app buildable on current macOS and Xcode versions.
2. Keep the install and permission flow documented.
3. Preserve local-first dictation as the default path.
4. Keep optional cloud AI behavior explicit and user-controlled.
