# Yapper Documentation

**Yapper** is a macOS menu bar app that turns speech into text. Press a hotkey, speak naturally, and your words appear in any application.

---

## Documentation

| Document | Audience | Content |
|----------|----------|---------|
| [Product Overview](./product-overview.md) | Everyone | Features, vision, how it works |
| [User Flows](./user-flows.md) | Designers, PMs | User journeys and interactions |
| [Architecture](./architecture.md) | Developers | Key technical decisions and rationale |
| [Edge Cases](./edge-cases.md) | Developers, QA | Error handling and fallback behaviors |

---

## Quick Start

1. **Install** - Drag Yapper to Applications
2. **Launch** - Yapper appears in menu bar (no dock icon)
3. **Grant Permissions**:
   - Microphone: System will prompt automatically
   - Accessibility: Manual grant in System Settings > Privacy > Accessibility
4. **Wait for Model** - First launch downloads WhisperKit model (~1.5GB)
5. **Use** - Press `Option+Space` to record, press again to stop

---

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)
- ~2GB disk space (app + Whisper model)
- Microphone and Accessibility permissions

---

## For Developers

Technical reference for LLM-assisted development is in [CLAUDE.md](../CLAUDE.md) at the project root.
