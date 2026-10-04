# QA · 2.1 (polish pass)

- Menu bar shows only the glyph, no timer (screenshots while recording and transcribing; the ripple was visible). The faded paused state was added afterwards and not captured on screen.
- Panel note field: taller, focused with an orange ring. Typing was not automated, because synthetic keystrokes would reach the foreground app.
- Library sidebar collapses and expands; Settings panes (General, Recording, Transcription, Storage) checked on screen.
- AI analysis with the user's key and model renamed `Meeting · Sat, 3 Oct at 21:55` to “Launch Plan Task Review” and produced all sections in 69 s.
- RAM benchmark in README. 34 unit tests pass; tests no longer touch the real Keychain.
- Rebrand: bundle ID `tn.achraf.ultratranscribe`. The saved OpenRouter key migrates from the old Keychain entry; macOS asks once for microphone and Mac-audio permission and to allow Keychain access.

# QA · 2.0 (menu-bar redesign)

Verified on this Mac (Apple Silicon, macOS 27), with the app built by `scripts/build.sh`, signed with Apple Development, `codesign --verify --deep --strict` passing.

## Automated

- `swift test`: 32 tests pass (persistence, recovery, retention, legacy preferences and language migration, template persistence, auto-title and AI rename rules, analysis output parsing, speaker labels and grouping, RTL detection, talk-share meter, transcription queue without a model, analysis without a key).
- `basedpyright` 0 errors; `ruff` clean.

## Driven through the real UI

Clicks were real mouse events at targets located by the accessibility API.

- Launch: agent app, no Dock icon; panel opens from the icon; no focus ring on ⋯.
- Right-click menu: Start Recording, Pause, Resume, Stop. Meeting auto-named `Meeting · Sun, 4 Oct at 08:24`.
- Live: menu-bar timer; panel live card with participants, talk-time bar, note field and green/orange waveform; paused state dims the timer and flattens the icon.
- English, Arabic and French speech played through Mac audio was transcribed correctly as Colleagues. French was kept verbatim while only English and Arabic were allowed.
- Stop opened the library on the new meeting with a speaker-grouped transcript.
- AI notes without a key: inline message, then Open Settings jumped to AI Analysis; the model catalog loaded 466 OpenRouter models with prices.
- Sidebar: paper selection, no blue highlight; layout stays put after interacting with the detail pane.

## Recognition study (real 12-minute English/Saudi-Arabic meeting)

| Variant | Lines in a wrong language/script |
|---|---|
| 1.0 pipeline (25 s chunks, free language detection) | 32 (Chinese, Hindi, Persian, Dutch, Russian, Cantonese, Portuguese) |
| Utterance segmentation + English/Arabic constraint + denoise | 0 |

Rejected after measurement: a “Saudi Arabic” context hint (the model recited it on silence and drifted Arabic into English), and envelope-correlation speaker-bleed detection (did not fire on real room noise and dropped one genuine line).

## Not verified

- A paid OpenRouter analysis (no key on this Mac). Request building, output parsing and rename rules are unit-tested.
- Effect of Voice Isolation mic mode on accuracy.
- Live transcription: not implemented; transcription runs after Stop.
- Notarized distribution.
