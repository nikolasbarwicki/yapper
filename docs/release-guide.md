# Yapper Release Guide

How to build and publish a community version of Yapper.

## Prerequisites

For local unsigned builds, only Xcode is required.

For signed public releases, you also need:

- A `Developer ID Application` signing certificate
- Apple notarization credentials configured for `xcrun notarytool`
- A GitHub repository where releases can be published

This repository does not include a personal development team identifier. Configure your own signing team locally in Xcode or through your release automation.

## Step 1: Bump The Version

In Xcode, update both version fields in the Yapper target's **General** tab:

- **Version** (`MARKETING_VERSION`): The user-facing version, such as `2.0.1`
- **Build** (`CURRENT_PROJECT_VERSION`): Integer build number, incremented for each release

## Step 2: Build Release Artifacts

```bash
./scripts/build-release.sh
```

This outputs to `dist/`:

- `Yapper.app`
- `Yapper.zip`
- `Yapper.dmg`

## Step 3: Optional Notarization

```bash
xcrun notarytool submit dist/Yapper.zip \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple dist/Yapper.app
```

Wait for `status: Accepted` before distributing a signed release.

If you staple the app, recreate the ZIP afterward so the archive contains the stapled ticket:

```bash
cd dist
rm -f Yapper.zip
ditto -c -k --keepParent Yapper.app Yapper.zip
```

Use `ditto` because it preserves macOS extended attributes.

## Step 4: Publish GitHub Release

1. Create a GitHub release for the version tag.
2. Upload `dist/Yapper.zip` and `dist/Yapper.dmg`.
3. Include macOS version requirements and a short changelog.
4. Note whether the build is signed and notarized.

## Automatic Updates

Sparkle is not currently wired into open-source builds. If maintainers want automatic updates later, add a new appcast, public key, package dependency, plist configuration, and menu UI that points at infrastructure controlled by the maintainer.

## Quick Reference

```bash
./scripts/build-release.sh
xcrun notarytool submit dist/Yapper.zip --apple-id "..." --team-id "..." --password "..." --wait
xcrun stapler staple dist/Yapper.app
cd dist && rm -f Yapper.zip && ditto -c -k --keepParent Yapper.app Yapper.zip
```
