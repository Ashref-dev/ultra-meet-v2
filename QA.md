# QA

What was verified for the current release, and how. Update this file with every release; say plainly what was not verified.

## Unreleased

Versus mode. `swift test`: 68 pass (9 new: alignment of lines with slightly different edges, the other side never sharing a row, agreement ignoring case, accents and punctuation, marked words, missed lines counted only against complete transcripts, column order and states with a trim, storage apart from the transcript with unreadable files skipped, a failing model reported without touching the meeting and releasing its protection, a recording or transcription putting the running model back in line). `basedpyright` 0 errors, `ruff` clean. Worker `transcribe --output` run on a copy of a real 5-minute meeting with Qwen3-ASR 0.6B (31 s) and Whisper Large v3 Turbo (352 s, about three times the estimate from the eval set, on a busy Mac): the transcript, partial and progress files went to the output folder and the meeting folder's listing was unchanged. The real three-way comparison (meeting's Qwen3-ASR 1.7B, 0.6B, Whisper) lined up as 139 rows with no line split across rows; Whisper's "Thank you." on silence and the language differences show as marked words. Not seen on screen: the Versus tab, picker, progress, column chips, Differences filter, popover and playback highlight.

Second pass after five read-only reviews (audio capture, state and persistence, UI and UX, transcription worker, security). `swift test`: 59 pass (new: automatic microphone on desktops and with virtual devices, channel lookup across streams, archive reconciling a track left in two formats, recovery keeping corrections over an older transcript). `basedpyright`: 0 errors. `ruff`: clean. Release build, strict signature verification, and the updater's new signing requirement checked against the installed app (accepted) and an ad-hoc signed copy (rejected). `python -I worker.py` runs.

- Not changed, needs evidence first: the echo filter can drop a short genuine reply that follows the same words from Mac audio within 2 s. Changing it needs a speakerphone test set (AGENTS.md: recognition changes are measured). Also open: playback normalization never turns speech down in the worker; `scripts/eval` reports matched-character error, not Levenshtein CER; live passes rescan all history (about 137 ms per track per pass at 3 hours); hardened runtime and notarization.
- Not seen or heard on hardware: the tap-only Mac audio device and its fallback, device stall recovery, sleep and wake, input channels on a multi-input interface, desktop Macs, the accent color in dialogs, focus rings, the retention confirmation.

Environment: Apple Silicon, 24 GB memory, macOS 27. `swift test`: 56 pass (new: automatic microphone never picks a Bluetooth headset, FLAC archive keeps 16-bit audio sample-exact and replaces originals only after verification, chosen-microphone preference, trim model and decoding, playback leveling down). Release build and strict signature verification passed.

- Why call audio sounded muffled: measured on three real meetings. Tracks recorded during calls had nothing above 8 to 12 kHz and the microphone track had hundreds of stretches of exact digital silence, the signature of a Bluetooth headset in call mode. The microphone was opened with `AVAudioRecorder` on the default input, which is the headset when one is connected.
- FLAC archive: a 3-minute real meeting went from 54 MB to 4.4 MB in 0.6 s; a 70-minute meeting projects from 1.1 GB to about 125 MB. The worker transcribed the original and the compressed copy of the same meeting into identical output: 30 lines, 200 words, no line different.
- The worker reads the new 16-bit little-endian CAF while it is still being written (live transcription), checked with an unclosed file.
- Not seen on screen or heard: recording through the new Core Audio capture (needs the user's microphone and permission), whether the Bluetooth headset now stays in full quality, following a device switch mid-meeting, the microphone menu, the panel opening active, trim handles and menu items, playback leveling. These are built and unit-tested only.

## 0.7.1

Environment: Apple Silicon, 24 GB memory, macOS 27, full Xcode. `swift test`: 49 pass (new checks: automatic analysis is off by default; model names in meeting headers). `basedpyright`: 0 errors. `ruff`: clean. Release build and strict signature verification passed.

- Seen on screen by the owner in the installed builds: the frosted panel glass in light mode, the floating library sidebar, thin scrollbars, the Copy and Export labels with shortcut hints.
- Not seen on screen: the panel in dark mode, typing in the panel and its More menu, arrow keys and ⌫ in the library, Space playback, dropping an audio file, the model name in the header, the one-line deleted-audio note, and Analyze after transcription. These were built and type-checked only.
- Space is handled only for a finished meeting with audio, and never while text is being edited; it cannot start or stop a recording.

## 0.7.0

Environment: Apple Silicon, 24 GB memory, macOS 27, full Xcode. `swift test`: 49 pass (two new: per-model languages and preferences decoding; deleting one model leaves the others). `basedpyright`: 0 errors. `ruff`: clean.

### Speech models

Each model was downloaded through `worker.py download` into a temporary folder and run on the `scripts/eval` meeting with `/usr/bin/time -l` (peak memory footprint, model load included), then deleted. Qwen3-ASR was re-run through the new engine dispatch and scored the same as before (Best and Balanced 0.047, Fast 0.115).

- Whisper Large v3 Turbo, limited to English, Arabic and French: 0.115, nothing missed; "تمام" read as French and "Oui" labeled English.
- Cohere Transcribe Arabic with Arabic chosen: 0.126; English and French lines were transcribed as spoken, so the chosen language is not used as a line label. The quietest English line (-56 dBFS) came out as Arabic.
- Parakeet TDT v3 and Granite Speech 4.0: English and French exact, Arabic written in Latin letters (neither supports Arabic).
- Voxtral Mini Realtime: 0.043, the lowest, at 39 s per minute and 7.0 GB.
- Cohere Transcribe (general) was not run: its download did not finish on this network. It uses the same engine and weight size as the Arabic model, whose numbers Settings shows for it.

### Interface

Checked in the built app with Accessibility and screenshots: the library and its sidebar, the menu-bar panel, and Settings → Transcription with Best, Cohere Transcribe and Parakeet selected. The language section switches to a single choice for Cohere and to the list of detected languages for Parakeet, and says which chosen languages a model does not support. Downloading a model and deleting one were exercised by tests, not through the interface. Setup, the AI notes tab, recording and playback were not re-checked after the design pass.

## 0.6.1

Checked in the built app: the library sidebar shows full AI titles on two lines with durations aligned at the right of the date line, short titles stay on one line, and a long title in the meeting header wraps. `swift test`: 47 pass.

## 0.6.0

Environment: Apple Silicon, 24 GB memory. App built with `scripts/build.sh`, signed with Apple Development. This release was verified in code, with automated tests, with the transcription worker on real and synthetic audio, and (build 6) by driving the built app through Accessibility with screenshots.

### Automated

- `swift test`: 47 tests pass, none skipped. New tests cover semantic version ordering, choosing the newest GitHub release (drafts skipped), refusing an unsigned update, talk time and the AI input (speaker split, languages, typed notes, unclear lines), Arabic and accent search folding, decoding 0.5 files with the new fields, name suggestions from corrections, editing a line, stopping a live recording (finishes instead of transcribing twice), silence tracking per side, swapping app copies on update (no staged copy left), keeping a meeting protected while its live transcription runs, and the playback level (a -40 dBFS track is lifted 22 dB, boosts stop at 24 dB, loud tracks are not turned down).
- `basedpyright`: 0 errors. `ruff`: clean (worker and `scripts/eval/eval.py`).
- The streaming reader and resampler return sample-identical audio to `soundfile` for the recorder's WAV (Int16) and CAF (Float32) files, read at once or in random chunks.

### Recognition

Synthetic set (`scripts/eval/eval.py`): 13 lines of English, French and Arabic from macOS voices, You at -45 to -57 dBFS including the Whisper voice, room noise at -72 dBFS, colleagues leaking into the microphone at -40 dB.

| Worker | Mean character error | Missed lines | Wrong language | Lines nobody said |
|---|---|---|---|---|
| 0.5.0 | 0.133 | 1 ("Oui.") | 0 | 1 (echo of an Arabic line) |
| 0.6.0 | 0.047 | 0 | 0 | 0 |

Real meetings (five, 0.5 to 12 minutes, English and Arabic with French): 0.6.0 keeps every line 0.5.0 found except two filler sounds and one hallucinated line of 255 question marks, and adds about ten real lines (for example a quiet "نعم" from the microphone and "How many days?" from the call). A colleague's 9-second English line, which the model had replaced with a recitation of the Names and terms list, is now decoded again without the list. Transcription time was unchanged within a few seconds.

Measured and rejected: a single loudness margin of 4 dB (merged room noise and a short reply into one 26-second clip the model called silence), splitting by each region's own loudest speech (cut the call track into 193 fragments), predicting speaker bleed from the call track (bleed sat at the microphone's noise floor), comparing text confidence across languages (forcing English on clear Arabic still scores higher) and favoring the speaker's previous language (mislabeled two short replies in real meetings).

Live transcription: the synthetic meeting was rewritten in real time as growing files while the worker followed it. Lines appeared during the replay; the final transcript was ready about 4 seconds after the files closed and scored the same as offline. A worker whose parent exits finishes the transcript and quits. After a code review, live mode tracks which audio it has transcribed instead of a single position, so speech that only becomes detectable as the noise floor settles is still transcribed; the replay scored the same afterwards (0.047, nothing missed).

### Call audio (build 6)

Every earlier `system.caf` had a run of about 45 zero samples every 557 samples. The output device (headphones) ran at 44.1 kHz while the file was written as 48 kHz, and the timeline padding filled the shortfall. After the fix, a recording made while a 1 kHz tone and a spoken sentence played through the headphones measured: tone at 1000.0 Hz (was about 1088 Hz), 0 zero gaps inside the signal, both tracks 32.9 s long within 0.1 s, and the sentence transcribed word for word.

### Used through the real interface (build 6)

Driven through Accessibility on the built app; test meeting "Test: audio quality check".

- Click a line: playback starts there and the line highlights. Double-click: the line becomes a field with the cursor at the end; typed text was appended and Return saved it to `meeting.json`. Esc and click-away paths are in code, not exercised.
- Scrubber: dragging to 80% moved the time to 00:27 without restarting audio; Resume played from 00:27.
- Audio files moved out of the folder: the transcript shows the missing-audio notice with Show in Finder, and clicking a line does nothing. A meeting with no transcript and no audio shows the notice instead of Transcribe.
- First run with an empty home folder (`CFFIXED_USER_HOME`): no models installed, sizes shown, Skip on optional steps, "Download and Continue" on the speech step; the runtime installed and the 1 GB Fast model downloaded with live progress on the Ready page. Switch knobs centered (screenshot).

### Not verified

- On screen: live lines in the panel and meeting window, health hints, update states in Credits, update banner and menu item, menu-bar progress fill, the waveform filling a wide window after 40 seconds of recording (verified in code: 480 columns of history).
- Hearing playback: the level and limiter are measured in tests, not listened to.
- The global shortcut, notifications (permission prompt, click to open), and installing an update end to end (needs a newer signed release on GitHub).
- Live transcription with a real recording and microphone; only replayed files were tested.
- Typing into the panel note field by automation; Voice Isolation's effect on accuracy; notarized distribution.

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
