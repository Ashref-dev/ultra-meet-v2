# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org): `0.x` releases may still change behavior between minor versions.

## 0.6.0 · 2026-10-04

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
