# QA

What was verified for the current release, and how. Update this file with every release; say plainly what was not verified.

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
