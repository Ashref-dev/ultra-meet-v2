# QA

What was verified for the current release, and how. Update this file with every release; say plainly what was not verified.

## 0.5.0

Environment: Apple Silicon, 24 GB memory, macOS 27. App built with `scripts/build.sh`, signed with Apple Development, `codesign --verify --deep --strict` passing.

### Automated

- `swift test`: 34 tests pass, none skipped. They cover persistence, crash recovery, retention, preference migration (including the language setting), templates, automatic titles and AI rename rules, analysis output parsing across model formats, speaker labels and grouping, right-to-left detection, the talk-time meter, model recommendation by memory, and failure paths without a model or key. Tests use a temporary library and never touch the Keychain.
- `basedpyright`: 0 errors. `ruff`: clean.

### Used through the real interface

Clicks were real mouse events on targets found through the Accessibility API, limited to the app's own windows and menus.

- Menu-bar agent: no Dock icon; left-click panel, right-click menu; Start, Pause, Resume and Stop from the menu; meeting named automatically.
- Menu-bar icon shows only the logo: live dots while recording, a ripple while transcribing.
- English, Arabic and French speech played through Mac audio was transcribed as Colleagues; Stop opened the speaker-grouped transcript.
- Analyze with AI with a real OpenRouter key renamed an automatically named meeting and returned every section in 69 seconds.
- Library sidebar collapses and expands; Settings panes and Credits were checked on screen.
- App icon, Credits icon, menu-bar icon and panel logo render from the same `LogoGlyph.swift`.

### Recognition study

A real 12-minute English and Saudi Arabic meeting was transcribed with each pipeline.

| Pipeline | Lines in a wrong language |
|---|---|
| 25-second chunks, free language detection | 32 (Chinese, Hindi, Persian, Dutch, Russian, Cantonese, Portuguese) |
| Utterance segmentation, denoise, English and Arabic only | 0 |

Rejected after measurement: a "Saudi Arabic" context hint (recited on silence, pushed Arabic into English) and envelope-correlation bleed detection (did not trigger on real room noise, removed a real line).

### Memory benchmark

`proc_pid_rusage` physical footprint while transcribing two minutes of real audio: 0.6B 1.9 GB, 1.7B 8-bit 3.5 GB, 1.7B BF16 5.0 GB.

### Not verified

- Typing into the panel note field by automation (keystrokes could reach another app).
- The paused menu-bar icon and the rename highlight on screen.
- Effect of Voice Isolation on accuracy.
- Notarized distribution and in-app update installation.
