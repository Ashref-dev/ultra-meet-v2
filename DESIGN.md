# Ultra Transcribe design system

## Direction

Warm Instrument. Operate mode. A compact recording instrument in the menu bar and a quiet reading surface for transcripts. Native macOS chrome (toolbar, sidebar and popover materials, Liquid Glass on action controls) sits over our own warm paper palette. The brand lives in precise details: the orange accent, the dot logo, dot-matrix waveform and progress, monospaced uppercase metadata, and green You / orange Colleagues. Content (transcripts, notes, settings cards) stays on opaque paper; glass is only used on controls, never nested.

## Tokens (`Sources/Views/Theme.swift`)

- Surfaces, adaptive light / dark: `background` RGB 0.965/0.955/0.94 and 0.11/0.105/0.10; `paper` white and 0.16/0.15/0.14; `secondary` 0.43/0.39/0.35 and 0.73/0.70/0.66; `line` black 9% and white 10%. `backgroundColor` is the same background as an `NSColor`, used for window backgrounds.
- Accent: `orange` (the logo ink) for primary actions, focus and selection; `ember` when pressed; `selectionFill` is orange at 12%.
- Destructive: `destructive`, a warm red (0.78/0.20/0.14 light, 0.95/0.42/0.34 dark), always paired with a Trash glyph or a destructive label.
- Speakers: `you` green 0.10/0.56/0.36 and `colleagues` orange 0.91/0.45/0.07, with adaptive dark tones and deep tones for the waveform.
- Radii, continuous corners: `radius` 12 for cards and sections, `controlRadius` 8 for buttons, fields, rows, tabs, segmented controls and chips, `chipRadius` 5 for key caps and tags. No capsule buttons, tabs, segmented controls or chips. Only the switch track, avatars, dots, bars and the swipe Trash button are round.
- Sizes: `controlHeight` 30, `compactControlHeight` 26, `swipeActionSize` 32. Spacing uses 4, 8, 12, 16, 20 and 24.
- Type: SF for content. 11.5 pt captions and footnotes, 13 pt body, 14 pt transcript and notes, 18 pt card and sheet headings, 20 pt pane headings, 26 pt meeting and setup titles, with slight negative tracking. Button and tab labels are sentence case, 12.5 pt semibold (11.5 compact). `Theme.mono` (11 pt, uppercase, 0.6 tracking) is for metadata only.
- Motion: `feedback` 160 ms ease-out for hover, press and cross-fades; `selection` 240 ms snappy for sliding indicators and pane changes. Every animation is off with Reduce Motion.

## Components (`Sources/Views/Components.swift`)

- `ControlStyle` (primary orange glass, secondary clear glass, quiet borderless; `compact`, `expand`, `square`; hover, press 0.97, disabled 45%, destructive role in red). `IconButton` and `MoreMenu` (the ellipsis menu) build on it. `RecordLabel` swaps the record glyph for dot progress.
- `GlassControls` groups neighboring glass controls into one `GlassEffectContainer`. `glassSurface()` uses Liquid Glass on macOS 26 and later; macOS 15 uses a material or solid tint; Reduce Transparency or Increase Contrast uses opaque paper with a stronger border.
- The menu-bar panel is a borderless `GlassPanel` (not an `NSPopover`, whose own frosted frame would cover the glass) drawn with `panelGlass()`: frosted (regular) Liquid Glass tinted by `Theme.glassTint`, white 20% in light mode and black 30% in dark mode. Text on the glass uses the system's vibrant `.primary` and `.secondary` (`onGlass`, `secondaryText()`); paper cards switch back to the warm palette. macOS 15 uses the popover material, and Reduce Transparency or Increase Contrast an opaque background.
- `floatingSidebar(_:)`: library and Settings sidebars share their window's color (paper or warm background) and float as a card with a hairline and a soft shadow, inset 8 pt, with no divider.
- `thinScrollbars()`: every scroll view uses `ThinScroller`, a 3 pt warm knob with no track that widens to 6 pt under the pointer, in overlay style.
- `card()` (paper, hairline, 12 pt), `field(focused:)` (paper, hairline, orange focus border), `SearchField`, `RowStyle` (hover and orange selection fill), `PressStyle`, `TabStrip` (sliding orange fill), `Segmented` (sliding paper thumb inset 2 pt), `ToggleChip`, `SwitchKnob`, `KeyCaps`, `LinkLabel`, `MonoLabel`, `EditableTitle`, `SpeakerAvatar`, `DotProgress`, `DotWaveform`, `Shake`, `FlowLayout`. `InlineHint` (TranscriptViews) is the one inline message for errors, warnings and suggestions. `SettingsSection`, `SettingsRow`, `SettingsToggle` and `RowDivider` live in SettingsView.
- No system blue: every root gets `.tint(Theme.orange)` through `SurfaceRoot`, sheets set it again, fields draw their own orange focus border, and focus rings are disabled where they would appear on open.

## Performance

- The popover and every window are built once and reused. `SurfaceRoot` sets the `offscreen` environment value from a `Visibility` object (popover delegate, window occlusion). While offscreen, `DotWaveform` and the live card observe `LevelMeter.still` instead of the live meter, and `DotProgress` pauses its timeline.
- No file reads in `body`: the model-installed check and the meeting's audio listing are cached and refreshed when their inputs change. `MarkdownNotes` is `Equatable`. Library search is filtered once per render.

## Surfaces

- **Logo:** `Sources/Views/LogoGlyph.swift` is the only definition: a 7×5 dot lattice with an orange waveform. `LogoMark` draws it in SwiftUI, the status item draws it as a template image, and `LogoGlyph.appIcon(size:)` draws the macOS icon ("Ember": top-lit orange plate on Apple's 1024 grid, baked shadow, flat white dots). `scripts/icon/generate.sh` renders `AppIcon` from it.
- **Menu-bar icon:** glyph only. Recording: columns follow live audio. Paused: the logo at 40%. Transcribing: the waveform fills from left to right (a travelling ripple until progress is known).
- **Panel (380 pt):** a non-activating `GlassPanel`, key from the first click so its glass and orange controls show active while the call app keeps focus; header with logo, title, recording state and `MoreMenu`. The ready or live card is paper. Source pills, live name, participants, talk time, health hints, live lines and notes. A 64 pt waveform, then the timer and grouped glass recorder actions. Recent meetings and the update hint below.
- **Library:** unified toolbar with the sidebar button (⌃⌘S, remembered). A 272 pt floating sidebar with logo, settings, start, search (⌘F) and rows with orange selection that press in slightly. Swiping a row reveals a 32 pt round red Trash button; it opens the confirmation dialog, full swipes do nothing, protected meetings have none. The detail is paper: status, grouped glass Copy (named for the open tab, ⌘⇧C, disabled when the tab is empty), Export (⌘⇧E) and More, editable title, date · duration, and Transcript / AI notes / My notes tabs (⌘1 to ⌘3). Shortcuts show as quiet `ShortcutHint` text beside their buttons.
- **Transcript:** conversation map and talk time, speaker turns with avatar, name and a colored rail, per-line timestamps that seek, right-to-left alignment, language codes in mixed meetings, unsure lines underlined, the playing line highlighted. Right-click: Play from Here, Copy Line, Edit Line, Transcribe Again As, then Start Meeting Here, End Meeting Here and Restore Full Meeting. Trim: orange bracket handles on the conversation map, the cut parts at 30%, a time label while dragging, and one quiet line under the map (scissors, "Trimmed to 02:10 to 42:10", orange Restore).
- **Player:** one glass bar with borderless play, speed and close controls and an orange slider.
- **AI notes:** empty state with template picker and Analyze with AI, inline failure with Open Settings, dot-progress loading, rendered notes with Re-analyze.
- **Settings:** 208 pt floating sidebar with orange selection, a pane heading, warm background and paper `SettingsSection` cards. Six panes. Transcription lists every speech model as a radio row (name, maker and languages, then mono size, memory and speed) with Download or Installed and a delete button; the download's dot progress opens under its row. The language chips follow the model: several, one, or a plain list for models that detect the language. Model and template sheets use the same fields and controls.
- **Setup:** 580 pt window on the warm background, step dots in the header, cards inside the scrolling page, a divider and the footer actions. Six steps with Skip and Back.
- **AI rename:** the row cross-fades its title and glows orange with "Renamed by AI" for 2.5 s.
