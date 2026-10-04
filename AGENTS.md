# AGENTS.md · Ultra Transcribe

Guidance for anyone (human or agent) changing this repo. Read it before editing. `README.md` covers usage; `DESIGN.md` covers visual decisions; `QA.md` records what was actually verified; `CHANGELOG.md` lists releases.

## Product in one paragraph

A macOS menu-bar agent (`LSUIElement`, bundle `tn.achraf.ultratranscribe`, by achraf.tn, site ultra.achraf.tn). One click records **You** (microphone, green) and **Colleagues** (Mac audio, orange) on separate tracks. After Stop, Qwen3-ASR transcribes locally in a Python/MLX worker. Only when the user clicks **Analyze with AI** is the transcript text, never audio, sent to their OpenRouter model, using an editable template. There is no local language model.

## Priorities, not afterthoughts

These are part of every change, planned up front and reviewed like features:

- **UI and UX.** Every feature ships with its idle, active, loading, empty and error states designed, consistent with the design system below, and checked on screen.
- **Versioning.** [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. While in `0.x`, breaking changes bump MINOR, everything else PATCH. `CFBundleShortVersionString` is the semver; `CFBundleVersion` is a build number that only ever increases. Tag releases `vX.Y.Z` and record them in `CHANGELOG.md`.
- **Updates and update management.** Users must always know which version they run and how to get the next one. `Updater` reads the GitHub Releases API (Settings → Credits, the right-click menu, and a daily automatic check that notifies), and installs a release in place only if it has the same bundle identifier, the same developer team signature and a higher version; the old copy goes to the Trash. It depends on tags `vX.Y.Z` and one `.zip` asset containing `Ultra Transcribe.app`, so every release must keep that shape. Next steps: notarization, then signed delta updates (for example Sparkle). Never ship a change that makes an older install unable to upgrade: keep data formats backward compatible and migrations tested.

## Non-negotiables

- Audio never leaves the Mac. Nothing goes to the network unless the user explicitly asks (Analyze, key validation, model catalog, model download, update install), except the daily update check, which only reads the public GitHub release list and can be turned off.
- The app is menu-bar first: everything must be doable from the status item (left-click panel, right-click native menu). No Dock icon, no ⌘-Tab entry.
- Permission prompts only follow a user action: microphone and Mac audio at the first recording or in setup, notifications when the person turns them on.
- Never lose user data. Recordings, transcripts and notes are the user's. Move to Trash instead of deleting, decode old JSON tolerantly (`decodeIfPresent` with defaults), and migrate rather than reset (see `Keychain.read()` legacy migration).
- No Keychain or other blocking or prompting system calls at launch. Read the OpenRouter key only on a user action.
- Tests never touch real user state: use a temp `MeetingLibrary` root and inject `AppState.readKey`.

## Repo map

| Path | What |
|---|---|
| `Sources/UltraTranscribeApp.swift` | App delegate, window routing, quit flow |
| `Sources/StatusBarController.swift` | Status item, popover, right-click `NSMenu`, animated icon |
| `Sources/Core/` | `AppState` (single source of UI state), recording lifecycle, processing queue and analysis, models, persistence, Keychain |
| `Sources/Recording/` | Mic (`AVAudioRecorder`), system audio (Core Audio process tap), level meter, playback, import |
| `Sources/Services/` | `LocalEngine` (worker subprocess, live follow mode, single-line redo), `OpenRouter` (validate, catalog, analyze, title parsing), `Updater` (GitHub Releases, verified install), `Notifier`, `GlobalHotKey` |
| `Sources/Views/` | `Theme` (tokens), `LogoGlyph` (the logo), `Components` (shared controls), `TranscriptViews` (transcript lines, conversation map, hints), `SetupView` (first run), screens |
| `Sources/Resources/worker.py` | Transcription pipeline (typed with basedpyright, linted with ruff) |
| `scripts/build.sh` | Release build, bundle, sign; `scripts/icon/generate.sh` regenerates the app icon from `LogoGlyph.swift` |
| `scripts/eval/eval.py` | Recognition regression set (synthetic EN/FR/AR meeting with known text), scorer, and a real-time replay to test live mode |

## Commands (run what you touch, once, and read the output)

```sh
swift build && swift test                              # 47+ tests must pass, none skipped
basedpyright --project pyrightconfig.json              # worker types: 0 errors
ruff check Sources/Resources/worker.py scripts/eval/eval.py
bash scripts/build.sh                                  # signed .app in build/
codesign --verify --deep --strict "build/Ultra Transcribe.app"
```

Quit the running app before rebuilding the copy it runs from, and check that no meeting is `recording`/`processing` first.

## Engineering rules

- **KISS and DRY.** Smallest correct change. Duplication beats a premature abstraction, but anything used twice that defines look or behavior (logo, colors, buttons, rows, source toggles) lives in exactly one place.
- **One source of truth** for state (`AppState`), tokens (`Theme`), logo (`LogoGlyph`), source toggles (`SourcePicker`), speaker naming (`TranscriptSegment.speaker`) and title parsing (`MeetingAnalysis.parse`).
- **No type escapes.** No force-unwraps except constant URLs, no `try!`, no empty `catch`. Errors are `AppError.message` with a sentence the user can act on.
- **Main actor for UI state.** Long work runs in the worker process or detached tasks; cancellation is honored (`runOperation`, `cancelProcessing`).
- **Comments explain why, not what.** Keep docstrings for non-obvious rules (language constraint, rename rule, Keychain migration).
- **Delete dead code.** If an experiment didn't prove itself (see "Rejected" below), remove it instead of leaving it behind a flag.

## Evidence before claims

- **Recognition changes are measured on real audio,** never guessed. Run `scripts/eval/eval.py` (synthetic set with known text) and A/B on real meeting copies in a temp dir; compare lines, words and languages per side. Record results in `QA.md`.
  - Proven: utterance segmentation at pauses, 70 Hz high-pass, mild spectral denoise, gain to −20 dBFS (up to +40 dB), allowed-language logits constraint (plus "None" for no speech), filler/sound-event filter, mic-echo dedupe, speech detection relative to each track's own noise floor and loudest speech (no fixed loudness bar), quiet stretches as short clips of their own, re-decoding an unsure "None" as the likeliest language, re-decoding answers that recite the Names and terms prompt without it.
  - Rejected: a "Saudi Arabic" context hint (recited on silence, drifted Arabic to English); envelope-correlation bleed detection (never fired, dropped a real line); comparing text confidence across languages; a head start for the speaker's previous language; one 4 dB margin for all speech; splitting regions by their own loudest speech.
- **Performance claims come from benchmarks.** RAM per model is measured via `proc_pid_rusage` phys_footprint (Activity Monitor "Memory"); numbers live in `ASRModel.memoryGB`/`speed`.
- **UI is verified by using the built app,** with screenshots of the real surfaces. Report anything not seen on screen as unverified.
- **Say what failed.** If a gate fails or you couldn't run it, write that down plainly.

## Safe UI automation on the user's Mac

The user is often working on the same machine.

- Never click blind coordinates. Find targets through Accessibility (status item frame, menu items by title, elements by label) and click only our own windows, menus and status item.
- Never send keystrokes unless Ultra Transcribe is confirmed frontmost. A popover being key is not enough, because typing would go to the user's app.
- Never interact with security prompts (Keychain, TCC). Tell the user what to approve.
- Never create recordings that capture the room without saying so; label test meetings and mention them.

## Design system (follow it, don't reinvent it)

Visual authority: the warm "Transcript AI" recorder reference. Mode: Operate. Scanability, consistency and native behavior come before decoration.

- **Tokens only.** Colors, radii and motion come from `Theme`: `background`, `paper`, `line`, `secondary`, `orange` (primary action), `you` (green), `colleagues` (orange), radii 8/6, `feedback` 160 ms, `selection` 240 ms snappy. Never hardcode a hex or a radius in a view.
- **One logo.** Draw the mark only with `LogoMark` (SwiftUI) or `LogoGlyph.dots` (AppKit). The full icon ("Ember": macOS grid, baked shadow, lit orange plate, flat white dots) is `LogoGlyph.appIcon(size:)`; `scripts/icon/generate.sh` renders `AppIcon` from it and Credits shows it. Never hand-draw a "similar" mark or a second icon.
- **One accent.** Orange means "act" (record, primary buttons, focus, selection). Green and orange also identify speakers, and that pairing is reserved for You and Colleagues everywhere: avatars, rails, waveform, talk-time bar, toggles.
- **Type voice.** SF for content; monospaced uppercase `MonoLabel` for metadata, tabs and button labels. Titles 18 to 26 pt semibold with slight negative tracking.
- **Shared controls only:** `ControlStyle` (primary/secondary/quiet), `IconButton`, `SourcePill`/`SourcePicker`, `ToggleChip`, `SwitchKnob`, `Segmented`, `TabStrip`, `EditableTitle`, `NoteEditor`, `DotProgress`, `DotWaveform`, `SettingsSection`/`SettingsRow`/`SettingsToggle`, `RowStyle`, `card()`. Extend these; don't fork them.
- **No system blue.** Custom selection (`RowStyle(selected:)`), `.focusEffectDisabled()` where a ring would appear on open, and `makeFirstResponder(nil)` when presenting windows and popovers.
- **Omit before adding.** If an element doesn't help the next action, remove it. No explanatory filler, no counts nobody asked for, one short footnote per section at most. Copy is plain, specific and short.
- **States are designed, not defaulted.** Every surface has idle, active, loading (dot-matrix, not spinners), empty and error states. Errors are inline, say what happened, and offer the next action (for example "Open Settings").
- **Micro-interactions with purpose:** hover lift, press scale 0.97, sliding indicators, cross-fades on tab and pane changes, shake to refuse, rename glow. Respect Reduce Motion. No decorative loops except live audio and progress.
- **Native citizenship:** right-click menu, keyboard shortcuts in menus (⌘N, ⌘⇧P, ⌘⇧S, ⌘L, ⌃⌘S, ⌘,), real text views for editing, RTL text aligned right, VoiceOver labels on icon-only controls.
- **Consistency check before shipping UI:** same logo, same tokens, same component, same copy tone on every surface (panel, library, settings, menu bar, icon). Inspect once with screenshots, fix everything in one batch, confirm once.

## Shipping

- Bump `CFBundleShortVersionString` (semver) and `CFBundleVersion` (build, always increasing) in `packaging/Info.plist`, add a `CHANGELOG.md` entry, update `QA.md`, then tag `vX.Y.Z` and publish a GitHub release with the zipped app.
- Deliver by copying `build/Ultra Transcribe.app` to `~/Desktop` and `~/Applications`. Move old copies to the Trash, don't delete them, then verify the signature.
- Commit with a short imperative subject and bullet body; never push or publish without being asked.
- Update `README.md`, `DESIGN.md`, `QA.md`, `CHANGELOG.md` and `Sources/Resources/Help.md` when behavior or design changes.
- Writing style everywhere (docs, UI copy, commits, release notes): plain, specific and professional. No em dashes, no hype words, no emoji.
