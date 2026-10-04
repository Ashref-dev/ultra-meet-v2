# AGENTS.md · Ultra Transcribe

Guidance for anyone (human or agent) changing this repo. Read it before editing. `README.md` covers usage and data layout; `DESIGN.md` covers visual decisions; `QA.md` records what was actually verified.

## Product in one paragraph

A macOS menu-bar agent (`LSUIElement`, bundle `tn.achraf.ultratranscribe`, by achraf.tn, site ultra.achraf.tn). One click records **You** (microphone, green) and **Colleagues** (Mac audio, orange) on separate tracks. After Stop, Qwen3-ASR transcribes locally in a Python/MLX worker. Only when the user clicks **Analyze with AI** is the transcript text, never audio, sent to their OpenRouter model, using an editable template. There is no local language model.

## Non-negotiables

- Audio never leaves the Mac. Nothing goes to the network unless the user explicitly asks (Analyze, key validation, model catalog, model download).
- The app is menu-bar first: everything must be doable from the status item (left-click panel, right-click native menu). No Dock icon, no ⌘-Tab entry.
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
| `Sources/Services/` | `LocalEngine` (worker subprocess), `OpenRouter` (validate, catalog, analyze, title parsing) |
| `Sources/Views/` | `Theme` (tokens), `LogoGlyph` (the logo), `Components` (shared controls), screens |
| `Sources/Resources/worker.py` | Transcription pipeline (typed with basedpyright, linted with ruff) |
| `scripts/build.sh` | Release build, bundle, sign; `scripts/icon/generate.sh` regenerates the app icon from `LogoGlyph.swift` |

## Commands (run what you touch, once, and read the output)

```sh
swift build && swift test                              # 34+ tests must pass, none skipped
basedpyright --project pyrightconfig.json              # worker types: 0 errors
ruff check Sources/Resources/worker.py
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

- **Recognition changes are measured on real audio,** never guessed. A/B on a real meeting copy in a temp dir; count wrong-language lines and inspect the mic track. Record results in `QA.md`.
  - Proven: utterance segmentation at pauses, 70 Hz high-pass, mild spectral denoise, gain to −20 dBFS, allowed-language logits constraint (plus "None" for no speech), filler/sound-event filter, mic-echo dedupe.
  - Rejected: a "Saudi Arabic" context hint (recited on silence, drifted Arabic to English); envelope-correlation bleed detection (never fired, dropped a real line).
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
- **Type voice.** SF for content; monospaced uppercase `MonoLabel` for metadata, tabs and button labels. Titles 18–26 pt semibold with slight negative tracking.
- **Shared controls only:** `ControlStyle` (primary/secondary/quiet), `IconButton`, `SourcePill`/`SourcePicker`, `ToggleChip`, `SwitchKnob`, `Segmented`, `TabStrip`, `EditableTitle`, `NoteEditor`, `DotProgress`, `DotWaveform`, `SettingsSection`/`SettingsRow`/`SettingsToggle`, `RowStyle`, `card()`. Extend these; don't fork them.
- **No system blue.** Custom selection (`RowStyle(selected:)`), `.focusEffectDisabled()` where a ring would appear on open, and `makeFirstResponder(nil)` when presenting windows and popovers.
- **Omit before adding.** If an element doesn't help the next action, remove it. No explanatory filler, no counts nobody asked for, one short footnote per section at most. Copy is plain, specific and short.
- **States are designed, not defaulted.** Every surface has idle, active, loading (dot-matrix, not spinners), empty and error states. Errors are inline, say what happened, and offer the next action (for example "Open Settings").
- **Micro-interactions with purpose:** hover lift, press scale 0.97, sliding indicators, cross-fades on tab and pane changes, shake to refuse, rename glow. Respect Reduce Motion. No decorative loops except live audio and progress.
- **Native citizenship:** right-click menu, keyboard shortcuts in menus (⌘N, ⌘⇧P, ⌘⇧S, ⌘L, ⌃⌘S, ⌘,), real text views for editing, RTL text aligned right, VoiceOver labels on icon-only controls.
- **Consistency check before shipping UI:** same logo, same tokens, same component, same copy tone on every surface (panel, library, settings, menu bar, icon). Inspect once with screenshots, fix everything in one batch, confirm once.

## Shipping

- Bump `CFBundleShortVersionString`/`CFBundleVersion` in `packaging/Info.plist` for user-visible releases.
- Deliver by copying `build/Ultra Transcribe.app` to `~/Desktop` and `~/Applications`. Move old copies to the Trash, don't delete them, then verify the signature.
- Commit locally with a short imperative subject and bullet body; never push without being asked.
- Update `README.md`, `DESIGN.md`, `QA.md` and `Sources/Resources/Help.md` when behavior or design changes.
