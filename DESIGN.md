# Ultra Transcribe design system

## Direction

Operate mode. A compact recording instrument in the menu bar and a quiet reading surface for transcripts. The supplied “Transcript AI” recorder (warm paper, white card, orange stop button, dot-matrix spectrogram, mono labels) is the visual authority.

## Tokens (`Sources/Views/Theme.swift`)

- Surfaces: background RGB 0.965/0.955/0.94, paper white; dark-mode equivalents.
- Accent: orange RGB 0.85/0.25/0.08 for record/primary actions only; ember for pressed.
- Speakers: **You green** RGB 0.10/0.56/0.36, **Colleagues orange** RGB 0.91/0.45/0.07, each with a deep tone (`youDeep`, `colleaguesDeep`) for two-tone gradients. Used in avatars, rails, waveform, conversation map, talk time, toggles.
- Radii: cards 8 pt, controls 6 pt, chips 4 pt. Sharp, not bubbly.
- Type: SF for content; monospaced 11 pt uppercase with 0.6 tracking for metadata, tabs and buttons.
- Motion: 160 ms ease-out feedback, 240 ms snappy selection; Reduce Motion respected.

## Components (`Sources/Views/Components.swift`)

`MonoLabel`, `ControlStyle` (primary/secondary/quiet, hover lift, press scale), `IconButton`, `ToggleChip`, `FlowLayout`, `TabStrip` (sliding indicator), `card()`, `EditableTitle` (hover reveals field and pencil, orange focus ring), `SpeakerAvatar` (live level halo), `DotProgress`, `DotWaveform` (live level history, deep speaker tone at the center line fading to the light tone at the edges, as in the reference; idle shape in ember to orange), `InlineHint` (one-line hint with an optional action), `LogoMark` / `LogoGlyph` (shared by the menu-bar icon), `Shake` (refusal feedback).

## Surfaces

- **Logo:** `Sources/Views/LogoGlyph.swift` is the only definition: a 7×5 dot lattice with an orange waveform. `LogoMark` draws the mark in SwiftUI, the status item draws it as a template image, and `LogoGlyph.appIcon(size:)` draws the full macOS icon (Apple 1024 grid: 824 plate, 185.4 corners, baked shadow y 12 σ 16 30%; "Ember": top-lit orange plate with rim light; flat white dots, faint white lattice). `scripts/icon/generate.sh` renders `AppIcon` from it and the Credits pane shows the same image.
- **Menu-bar icon:** glyph only, no text. Recording: columns follow live audio. Paused: the logo shape at 40% opacity. Transcribing: the waveform fills in from left to right with progress (a travelling ripple until progress is known).
- **Panel (380 pt):** header with logo and ⋯ menu. Idle card: title, date, compact You/Colleagues source pills (shake when you try to turn both off). Live card: editable name, participant avatars with level halos, talk-time split bar, health hints (silent microphone, no Mac audio), the last three live transcript lines with speaker dots, 96 pt `NoteEditor` (multi-line, scrolls, 14 pt fades at top and bottom, orange focus ring). 66 pt waveform, timer, pause, start/stop. Recent meetings with an “All meetings ↗” button when idle. An update hint appears above the waveform when a new version is out.
- **Library window:** collapsible (toolbar button, ⌃⌘S, remembered) 270 pt sidebar (logo, settings, start, search, rows with paper selection and dot progress), meeting detail with status, Copy/Export/⋯, editable title, date/duration/participants, Transcript / AI notes / My notes tabs.
- **Transcript (`TranscriptViews.swift`):** a `ConversationMap` (two dot rows, You above Colleagues, orange playhead, click to play) and talk time head the transcript. Speaker turns: avatar and colored name with start time; a colored rail binds every line beneath; per-line timestamps seek playback; right-to-left lines align right; a mono language code per line when a meeting mixes languages; unsure lines in secondary color with a dotted underline; the line being played gets a soft speaker-colored background and stays in view. Right-click: Play from Here, Copy Line, Edit Line (in place, orange focus ring), Transcribe Again As. While transcribing or recording live, finished lines appear read-only under the progress.
- **Player:** both sides together, speed 1× to 2×, slider, close.
- **AI notes:** empty state with template picker and Analyze with AI; inline failure with Open Settings; loading; rendered notes with task checkboxes, re-analyze.
- **Settings:** own sidebar (logo, orange selection), 540 pt content column of `SettingsSection` cards with `SettingsRow` / `SettingsToggle` (shared `SwitchKnob`), `Segmented` with sliding thumb, `KeyCaps`. Panes: General, Recording (reuses `SourcePicker`), Transcription (model cards with measured memory and a Recommended badge), AI Analysis, Storage, Credits (app icon, version, update states: check, up to date, available with notes and Install and Relaunch, installing, failed; automatic check toggle; links).
- **AI rename:** the renamed row cross-fades its title and glows orange with “Renamed by AI” for 2.5 s.
- **Setup:** 580 pt window with step capsules: welcome, You (live microphone check), Colleagues (asks for Mac audio), speech model and languages (shared `SpeechModelList`, `LanguageChips`), optional OpenRouter key (shared `OpenRouterKeyField`), ready (notifications, login, updates, global shortcut). Skip and Back on every step.
