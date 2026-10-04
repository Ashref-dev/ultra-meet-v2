# Ultra Transcribe design system

## Direction

Operate mode. A compact recording instrument in the menu bar and a quiet reading surface for transcripts. The supplied “Transcript AI” recorder (warm paper, white card, orange stop button, dot-matrix spectrogram, mono labels) is the visual authority.

## Tokens (`Sources/Views/Theme.swift`)

- Surfaces: background RGB 0.965/0.955/0.94, paper white; dark-mode equivalents.
- Accent: orange RGB 0.85/0.25/0.08 for record/primary actions only; ember for pressed.
- Speakers: **You green** RGB 0.10/0.56/0.36, **Colleagues orange** RGB 0.91/0.45/0.07. Used in avatars, rails, waveform, talk-time bar, toggles.
- Radii: cards 8 pt, controls 6 pt. Sharp, not bubbly.
- Type: SF for content; monospaced 11 pt uppercase with 0.6 tracking for metadata, tabs and buttons.
- Motion: 160 ms ease-out feedback, 240 ms snappy selection; Reduce Motion respected.

## Components (`Sources/Views/Components.swift`)

`MonoLabel`, `ControlStyle` (primary/secondary/quiet, hover lift, press scale), `IconButton`, `ToggleChip`, `FlowLayout`, `TabStrip` (sliding indicator), `card()`, `EditableTitle` (hover reveals field and pencil, orange focus ring), `SpeakerAvatar` (live level halo), `DotProgress`, `DotWaveform` (live level history colored by speaker), `LogoMark` / `LogoGlyph` (shared by the menu-bar icon), `Shake` (refusal feedback).

## Surfaces

- **Menu-bar icon:** template dot-matrix logo; while recording, its columns follow live audio and the timer sits beside it; paused collapses to a flat dotted line.
- **Panel (380 pt):** header with logo and ⋯ menu. Idle card: title, date, compact You/Colleagues source pills (shake when you try to turn both off). Live card: editable name, participant avatars with level halos, talk-time split bar, quick note. 66 pt waveform, timer, pause, start/stop. Recent meetings when idle.
- **Library window:** fixed 270 pt sidebar (logo, settings, start, search, rows with paper selection and dot progress), meeting detail with status, Copy/Export/⋯, editable title, date/duration/participants, Transcript / AI notes / My notes tabs.
- **Transcript:** speaker turns. Avatar and colored name with start time head each turn; a colored rail binds every line beneath; per-line timestamps seek playback; right-to-left lines align right.
- **AI notes:** empty state with template picker and Analyze with AI; inline failure with Open Settings; loading; rendered notes with task checkboxes, re-analyze.
- **Settings:** sidebar panes General, Recording, Transcription, AI Analysis, Storage. Language chips, model cards, key validation, searchable model catalog sheet with prices, template editor sheet.
