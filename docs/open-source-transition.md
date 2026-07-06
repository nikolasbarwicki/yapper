# Open Source Transition Notes

Yapper was originally distributed as a paid macOS app with Polar license activation and a 7-day trial. The app is now open source and local builds no longer require activation.

## Current Runtime Behavior

- App startup goes directly into normal setup.
- No Polar license check runs before the menu bar app starts.
- No trial starts on first launch.
- Settings shows Yapper as open source with no license key required.
- The former Sparkle appcast metadata and update menu are not wired into current builds.

## Historical Code

The historical licensing source files were removed from the active tree so public readers do not infer current trial or activation behavior. Older generated analysis notes that mention those components live under `docs/archive/` and are historical only.

## Release Distribution

Anyone may build Yapper from source under the MIT License. Maintainers who publish binaries should document whether those builds are signed and notarized.

Current open-source builds do not include an appcast URL, Sparkle public key, or menu item for update checks. Community maintainers who want automatic updates should add their own update infrastructure and signing keys.
