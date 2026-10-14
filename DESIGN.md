# Ultra Transcribe design system

## Direction

Operate mode. A compact recording instrument in the menu bar and a quiet reading surface for transcripts, using the native macOS 27 material language. The original recorder's orange action, speaker colors, shared logo and dot-matrix waveform remain. Navigation and actions use translucent materials; content stays opaque. No decorative glass behind paragraphs or form rows.

## Tokens (`Sources/Views/Theme.swift`)

- Surfaces: semantic macOS window background, text background, secondary label and separator colors, adapting to appearance.
- Accent: the logo's orange for primary actions and selected navigation; ember for pressed.
- Destructive actions: semantic macOS system red with a Trash glyph, not color alone.
- Speakers: **You green** RGB 0.10/0.56/0.36, **Colleagues orange** RGB 0.91/0.45/0.07, with adaptive dark colors and deep tones for waveform gradients.
- Radii: cards 16 pt, fields and navigation rows 10 pt, key caps 5 pt. Action buttons and segmented choices use capsules. Controls are 34 pt high, compact actions 28 pt.
- Type: SF for content, sentence-case tabs and action labels; monospaced 11 pt uppercase with 0.6 tracking for metadata.
- Motion: 160 ms feedback, 240 ms selection. Shared controls and indeterminate progress honor Reduce Motion.

## Components (`Sources/Views/Components.swift`)

`MonoLabel`, `ControlStyle` (primary/secondary glass, borderless quiet, press and disabled feedback), `IconButton`, `ToggleChip`, `FlowLayout`, `TabStrip` (selected capsule), `card()` (opaque grouped content), `EditableTitle`, `SpeakerAvatar`, `DotProgress`, `DotWaveform`, `InlineHint`, `LogoMark` / `LogoGlyph`, `Shake`, `SwitchKnob`, `Segmented` and `KeyCaps`.

`glassSurface()` uses the system's Liquid Glass on macOS 26 and later, including macOS 27. `GlassControls` groups related effects in one renderer. macOS 15 uses a standard material for secondary actions and solid orange for primary actions. Reduce Transparency or Increase Contrast uses opaque controls with stronger borders. `sidebarSurface()` and `popoverSurface()` use native `NSVisualEffectView` materials with the same opaque accessibility fallback. Avoid nested glass.

## Surfaces

- **Logo:** `Sources/Views/LogoGlyph.swift` is the only definition: a 7×5 dot lattice with an orange waveform. `LogoMark` draws the mark in SwiftUI, the status item draws it as a template image, and `LogoGlyph.appIcon(size:)` draws the full macOS icon (Apple 1024 grid: 824 plate, 185.4 corners, baked shadow y 12 σ 16 30%; "Ember": top-lit orange plate with rim light; flat white dots, faint white lattice). `scripts/icon/generate.sh` renders `AppIcon` from it and the Credits pane shows the same image.
- **Menu-bar icon:** glyph only, no text. Recording: columns follow live audio. Paused: the logo shape at 40% opacity. Transcribing: the waveform fills in from left to right with progress (a travelling ripple until progress is known).
- **Panel (380 pt):** native popover material, SF header with the shared logo and glass More control. Ready/live content stays on an opaque card. You/Colleagues source pills have 34 pt targets and full single-line labels. The live card retains editable name, participant levels, talk-time split, health hints, live lines and notes. A 66 pt waveform leads to the timer and grouped glass recorder actions. Starting and saving use dot progress, not spinners. Recent meetings and the update hint remain available.
- **Library window:** native unified toolbar with a sidebar button; ⌃⌘S and the remembered collapsed state remain. A 280 pt translucent sidebar contains logo, settings, start, search and orange-tinted selected rows. The detail stays opaque with status, grouped glass Copy/Export/More actions, editable title, date/duration/participants and Transcript / AI notes / My notes capsule tabs.
- **Library row actions:** native `List` swipe tracking reveals a 36 pt red circular Trash button with a white glyph and no rectangular fill. Full swipes do not delete. The action opens the existing confirmation dialog; protected meetings have no swipe action.
- **Transcript (`TranscriptViews.swift`):** a `ConversationMap` (two dot rows, You above Colleagues, orange playhead, click to play) and talk time head the transcript. Speaker turns: avatar and colored name with start time; a colored rail binds every line beneath; per-line timestamps seek playback; right-to-left lines align right; a mono language code per line when a meeting mixes languages; unsure lines in secondary color with a dotted underline; the line being played gets a soft speaker-colored background and stays in view. Right-click: Play from Here, Copy Line, Edit Line (in place, orange focus ring), Transcribe Again As. While transcribing or recording live, finished lines appear read-only under the progress.
- **Player:** both tracks together, speed 1× to 2×, slider and close, on one inset glass surface with borderless inner controls.
- **AI notes:** empty state with template picker and Analyze with AI; inline failure with Open Settings; loading; rendered notes with task checkboxes, re-analyze.
- **Settings:** native titlebar and 208 pt translucent sidebar with orange selection, a named pane heading, neutral grouped background and opaque `SettingsSection` cards. `SettingsRow`, `SettingsToggle`, `SwitchKnob`, `Segmented` and `KeyCaps` remain shared. All six panes and update states remain. Model and template sheets share the same grouped surfaces and action controls.
- **AI rename:** the renamed row cross-fades its title and glows orange with “Renamed by AI” for 2.5 s.
- **Setup:** 580 pt window with a quiet step header, opaque scrolling content and grouped glass footer actions. All six steps, Skip/Back behavior, permission actions and shared model/language/key fields remain.
