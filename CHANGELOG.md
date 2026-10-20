# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org): `0.x` releases may still change behavior between minor versions.

## Unreleased

- Recording is more robust on every kind of Mac and audio setup. The audio callback only copies samples; conversion and disk writes happen separately, so a busy disk can't cause dropouts. A device that stops delivering audio (unplugged, a stalled driver, after sleep) is reopened within seconds, and the gap is kept as silence so both tracks stay in sync. Timing uses the moment each buffer was captured.
- Mac audio is recorded through a capture device that contains only Mac audio, not your speakers or headphones; if a Mac can't run that, it falls back automatically.
- Automatic microphone choice works on desktop Macs: a USB or display microphone is used before a Bluetooth headset, and virtual devices (Zoom, Teams, BlackHole) are used only when chosen. Audio interfaces with several inputs get an Input channel choice in Settings → Recording. The microphone list updates when devices are plugged in, and the You toggle names the microphone that will record.
- If Mac audio can't be recorded, the microphone still records and the panel says why, instead of the meeting failing.
- Deleted audio, by you or by the retention setting, now goes to the Trash. Shortening retention asks before it removes anything.
- Background audio compression never competes with a meeting: it pauses for a recording, protects the meeting it is working on from deletion, finishes cleanly on quit, and tidies up a track left in both formats by an earlier quit.
- An interrupted Transcribe Again no longer brings back an earlier transcript over your corrections. Meetings stopped during a model download are transcribed once it finishes.
- Cancelling or quitting always finishes, even if the speech model doesn't respond. Worker errors show one readable line and where the full log is.
- Errors in the library show inline with a way to fix them (Open Settings), not as a dialog. A missing speech model offers Open Settings instead of a Transcribe Again that can't work.
- Orange accent for dialogs, focus rings and text selection; keyboard focus is visible on tabs, segmented controls, toggles and lists. Orange, green and colleague text meet WCAG AA contrast in light and dark mode.
- The status item says when a speech model is downloading, and panel tooltips work.
- Update checks require the download to be signed by Apple-issued certificates for this developer and app. Notifications no longer show meeting titles. Setup's test recordings stay inside the private library and are cleared at launch. Removing the OpenRouter key also removes the copy saved before the rebrand.
- Trim a meeting: drag the handles on the conversation map, or right-click a line and choose Start Meeting Here or End Meeting Here. The cut part is left out of the transcript, playback, AI notes, export and copy, and Restore brings it back. Audio and lines are never deleted.
- Recording no longer changes what you hear. Opening a Bluetooth headset's microphone switches it to call quality (muffled, compressed sound for everything it plays), so the microphone is now chosen in Settings → Recording, and Automatic records your Mac's microphone whenever the default input is a Bluetooth headset. Mac audio is captured without opening any device's microphone.
- Both tracks are recorded through Core Audio from one shared start, and recording follows the hardware: switching speakers or headphones, or plugging in a microphone, moves the recording to the new device instead of losing the rest of the meeting.
- Playback brings You and Colleagues to the same level, turning a loud microphone down as well as lifting quiet call audio.
- Much smaller storage. Recordings are 16-bit (Mac audio was 32-bit), and once a meeting is transcribed its audio is kept as lossless FLAC at full 48 kHz, about a ninth of the size. Earlier meetings are compressed in the background after launch. Each file is read back and compared sample by sample before the original is removed.
- The menu-bar panel opens active: the record button is orange and the glass at full strength on the first click, without taking focus from your call app.
- Removed the Mic mode setting and menu item: Ultra Transcribe records the microphone as it is, and its own processing cleans the audio for transcription.

## 0.7.1 · 2026-10-15

- The menu-bar panel is frosted Liquid Glass on macOS 26 and later: it blurs what is behind it, tinted lighter in light mode and darker in dark mode, with the system's vibrant text colors. It still opens under the icon and closes on Esc, a click elsewhere or a second click on the icon.
- The library and Settings sidebars share the main area's color and float as a card, with no divider. Rows press in slightly when clicked.
- Ultra-thin scrollbars everywhere: no gray track, a warm knob that widens under the pointer.
- Copy is named for the open tab (Copy transcript, Copy AI notes, Copy my notes) and is disabled when there is nothing to copy. Copy and Export show their shortcuts, ⌘⇧C and ⌘⇧E.
- New shortcuts: ⌘F searches meetings, ⌘1 to ⌘3 switch between Transcript, AI notes and My notes, and Esc clears the search. In the library, ↑ and ↓ move between meetings and ⌫ moves one to the Trash after confirming. Space plays or pauses a finished meeting's audio; it never starts or stops a recording.
- Drop an audio file on the library window to import and transcribe it.
- A meeting's header names the speech model that transcribed it.
- Settings → AI Analysis → Analyze after transcription writes AI notes as soon as a meeting is transcribed. Off by default.
- A meeting whose audio was deleted says so in one small line instead of a banner.
- The app bundle no longer ships stray Python cache files.

## 0.7.0 · 2026-10-15

- A library of local speech models in Settings → Transcription: Whisper Large v3 Turbo, Cohere Transcribe and Cohere Transcribe Arabic, Parakeet TDT v3, Granite Speech 4.0 and Voxtral Mini Realtime join Qwen3-ASR. Download or delete each one; size, memory and speed are shown for every model.
- Languages follow the model: several per meeting for Qwen3-ASR and Whisper, exactly one for Cohere, detected automatically for Parakeet, Granite and Voxtral. Transcribe Again offers only what the meeting's model supports.
- Native macOS styling from a contributor (thanks, Rayen): Liquid Glass controls on macOS 26 and later, a translucent sidebar and popover, a toolbar sidebar button, and swipe left on a library meeting to move it to the Trash.
- One design across every surface: the warm palette, no system blue, 12 and 8 pt corners instead of capsules, and shared controls for menus, search and record buttons.
- Faster opening and closing: live visuals pause while the panel or a window is hidden, model and audio-folder checks no longer read the disk while drawing, and windows paint before their first frame.
- Reduce Transparency, Increase Contrast and Reduce Motion are honored everywhere.
- Repeat builds work when Homebrew's `uv` is read-only.

## 0.6.1 · 2026-10-12

- Meeting names in the sidebar and menu-bar panel get the full row width and wrap to two lines; the duration moved to the end of the date line. Long titles in a meeting's header wrap instead of being cut off.

## 0.6.0 · 2026-10-05

Recognition you can trust in mixed-language meetings, clean call audio, live transcripts, and update management.

### Recording
- Call audio is recorded cleanly. When the output device ran at 44.1 kHz (most headphones), call audio was saved as 48 kHz: pitched up about 9% and cut by a short silence about 86 times a second, which sounded like static. It is now converted from the device's real rate, including when that rate changes mid-call, and the timeline is only padded for real interruptions. Recordings made before this release keep that damage.

### Transcription
- Speech detection no longer needs a minimum loudness. Quiet laptop microphones and whispers are transcribed; only real silence is skipped. On a real meeting the old fixed bar sat 12 dB above the microphone's own noise floor.
- Transcribe while recording (on by default): the transcript is ready seconds after Stop and can be followed live in the panel and the meeting window.
- Both sides are transcribed in time order, so an in-progress transcript reads from the top.
- A transcript that only repeats the Names and terms list is decoded again without it, which recovers lines that were lost before.
- Each line stores how sure the recognizer was; unsure lines are marked in the transcript and flagged to the AI.
- Arabic lines get Arabic punctuation; microphone echo of the call is matched regardless of diacritics.
- A crash or quit during a live recording still leaves a finished transcript for recovery.

### Transcript and playback
- Conversation map: when You and Colleagues spoke, clickable to play from there, with talk time per side measured from the transcript.
- Playback plays both sides together, at 1× to 2×, highlighting and following the line being heard. Each side is brought to a comfortable level (up to +24 dB for a quiet microphone) with a limiter against clipping; the recordings themselves are not changed.
- Click a line to play from it; double-click to correct it in place, with the cursor at the end of the line. Dragging the scrubber is smooth and playback jumps on release.
- A meeting whose audio was deleted, by you, by retention or outside the app, says so instead of failing silently, and no longer offers to transcribe again.
- Right-click a line to play, copy, correct it, or transcribe it again as a given language. Corrections offer to add new names to Names and terms.
- Language label on each line when a meeting uses more than one language.
- Library search ignores accents and Arabic spelling variants and shows the matching line.

### AI analysis
- The AI now receives talk time per side, the languages heard, your typed notes, and which lines were unclear, with stricter rules never to mix up You and Colleagues.

### App
- First-run setup: permissions with a live microphone check, speech model and languages, optional OpenRouter key, notifications. The app ships without speech models; setup downloads the one you pick, and optional steps can be skipped.
- Speech model downloads use plain HTTPS and show the gigabytes received. The Xet transfer used before stalled at 0 bytes on some networks.
- Updates: Settings → Credits checks GitHub Releases, installs a verified release in place (same bundle identifier and developer team, previous copy moved to the Trash) and relaunches. An automatic daily check notifies you of new versions and can be turned off.
- Control-Option-Command-R starts or stops recording from any app.
- Notification when a transcript is ready while you work elsewhere.
- Recording warnings for a silent microphone or a call playing on another device.
- Two-tone dot waveform (deep to light) as in the reference design, filling the full width at any window size; the menu-bar icon fills in as a transcript progresses.
- Switches have a centered knob; a saved OpenRouter key shows as saved instead of "Not validated yet".

## 0.5.0 · 2026-10-04

First public pre-release.

- Menu-bar recorder: one-click, automatically named meetings; right-click menu with Start, Pause, Resume and Stop.
- Separate You (microphone) and Colleagues (Mac audio) tracks, live waveform, talk time and in-meeting notes.
- Local transcription with Qwen3-ASR (0.6B, 1.7B 8-bit, 1.7B BF16) on Apple Silicon, with measured memory use and a recommendation per Mac.
- Multilingual recognition with a "Languages spoken" setting that prevents misdetected languages.
- Speaker-grouped transcripts with right-to-left support, playback from any timestamp, copy and Markdown export.
- Analyze with AI through OpenRouter: key validation, live model catalog, editable templates, automatic meeting titles.
- Meeting library with search and a collapsible sidebar; settings with General, Recording, Transcription, AI Analysis, Storage and Credits.
