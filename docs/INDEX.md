# Yapper Documentation Index

Navigation map for developers and AI coding agents.

## Quick Lookup

| If you need to... | Start with |
| --- | --- |
| Understand the app from a user perspective | [User Guide](user-guide.md) |
| Understand current architecture and code structure | [Technical Guide](technical-guide.md) |
| Ship a release | [Release Guide](release-guide.md) |
| Understand AI Q&A behavior | [AI Q&A Voice Assistant](ai-qa-voice-assistant.md) |
| Read historical scans | [Archive](archive/) |

## Root Documentation

### User Guide

**Path:** [`user-guide.md`](user-guide.md)

Complete end-user manual. Covers installation, permissions, recording modes, file transcription, keyboard shortcuts, language switching, AI modes, microphone selection, open-source availability, settings, transcript history, troubleshooting, and privacy.

### Technical Guide

**Path:** [`technical-guide.md`](technical-guide.md)

Developer-facing architecture documentation for current source. Covers app structure, runtime flow, core services, dependencies, persistence, permissions, and build notes. Current builds have no activation, trial, or license check path.

### Release Guide

**Path:** [`release-guide.md`](release-guide.md)

Community release workflow for local builds, optional Developer ID signing, notarization, and GitHub Releases publishing.

### AI Q&A Voice Assistant

**Path:** [`ai-qa-voice-assistant.md`](ai-qa-voice-assistant.md)

Feature doc for "Hey Yapper" voice assistant mode. Describes wake-phrase detection, Q&A panel display, keyboard shortcuts for the answer card, LLM provider requirements, and streaming response flow.

## Archive

Historical scans and transition notes live under [`archive/`](archive/). They can mention removed licensing, trial, Polar, or Sparkle behavior and should not be treated as current implementation documentation.

## Reading Order

**New to the codebase?**

1. `user-guide.md` - understand the app from the user's point of view
2. `technical-guide.md` - understand current architecture and services
3. `release-guide.md` - understand build and publication workflow

**Working on a specific feature?**

1. `technical-guide.md` - find the main service or view boundary
2. The relevant source files under `Yapper/`
3. `user-guide.md` - verify expected user-facing behavior

**Debugging or investigating behavior?**

1. `technical-guide.md` - follow the runtime flow
2. `user-guide.md` - verify expected behavior
3. `docs/archive/` - check historical context only when investigating old commits
