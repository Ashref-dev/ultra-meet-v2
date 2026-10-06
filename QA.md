# QA

What was verified for the current release, and how. Update this file with every release; say plainly what was not verified.

## 0.6.3

Environment: Apple Silicon, macOS 27, full Xcode, version 0.6.3 build 9.

- Release build and strict signature verification passed.
- Ran the built app under a separate QA bundle identifier and temporary home with one disposable meeting. Opened the library and exercised native horizontal scroll input without recording.
- Inspected the actual AppKit trailing action: its non-template image is 36 × 36 pt, up from 28 × 28 pt; its background remains transparent. Captured and inspected its red circular image with the proportionally enlarged white Trash glyph.
- The synthetic gesture did not leave the row fully revealed, so final on-row positioning was not visually reverified in this pass. Swipe tracking and deletion behavior are unchanged from 0.6.2.
- README and in-app Help remain unchanged because usage is unchanged. No tests were added or rerun for this size-only adjustment.
- Installed 0.6.3 (9) in Desktop and Applications, with old copies moved to the Finder Trash. Both installed signatures passed strict verification. The normal app reopened Meeting Library and reported Ready; temporary observation helpers were removed.

## 0.6.2

Environment: Apple Silicon, macOS 27, full Xcode, version 0.6.2 build 8. The built app ran under a separate QA bundle identifier and temporary home with disposable meetings. A failed recording setup entry appeared during the session and was retained in that isolated home; it has no audio or notes and reports that microphone access is off.

Delivery: installed 0.6.2 (8) in `~/Desktop` and `~/Applications`, moving the previous copies to the Finder Trash. Both installed signatures passed strict verification. The normal app relaunched, opened Meeting Library and reported Ready. Temporary inspection helpers were removed.

### Build and interface

- Release compilation and `codesign --verify --deep --strict` passed.
- Runtime inspection confirmed a native `SwiftUIOutlineListView` and trailing AppKit row action. The final action uses a non-template 28 pt circular image and a transparent background.
- The settled, revealed action was captured in the real library window: a small red circle with a white Trash glyph, no rectangular red fill. Native action visibility was true and the button had its full, unclipped frame.
- The visible circular button was activated through Accessibility and opened the existing confirmation dialog. Cancel retained the row and the meeting JSON's SHA-256 digest.
- Confirming another disposable meeting removed only that row. Finder located its folder in the Trash, and the moved JSON retained its SHA-256 digest. The remaining meeting's digest was unchanged.
- Real-window screenshots used a temporary in-process ScreenCaptureKit helper restricted to this app. No production screenshot or automation hook was added.
- No Python changes or new tests. This UI change was exercised in the running app; the Swift test suite was not rerun.

### Limits

- Synthetic scroll events did not reliably complete a native swipe. The settled circular control was observed after a physical swipe, and its actual button and confirmation flow were then exercised through Accessibility.
- Accessibility presses on the confirmation buttons returned an error while still applying the action. The resulting UI and file state were checked; a later Cancel check used an Accessibility-derived pointer target.
- The QA app exited cleanly during the typed-search check, so search filtering was not verified in this pass.
- macOS 15, accessibility motion/contrast overrides, live recording/transcription protection transitions, and large-library scrolling were not exercised. Recording, transcription and persistence formats are unchanged.

## 0.6.1

Environment: Apple Silicon, macOS 27, full Xcode selected through `DEVELOPER_DIR`. Interface smoke checks used the built app with `CFFIXED_USER_HOME` and a temporary library containing an English/Arabic transcript. Automation did not start recording or invoke a permission prompt.

### Build

- Release compilation and `codesign --verify --deep --strict` passed.
- The first integration build exposed an incorrect `NSToolbar.Identifier` assumption; it is a String. The corrected native toolbar compiled.
- Repeat bundling exposed Homebrew's read-only `uv` permissions. `install -m 755` now replaces the bundled runtime; the next bundle and signature check passed.
- No new tests or Python changes. This visual update was exercised through the running app, not screenshot assertions or source-text tests.

### Used through the real interface

- Recorder popover: native glass actions, source pills, idle waveform, model-install action and recent meeting row.
- Settings: General in Light and Dark, segmented appearance selection, selected navigation, grouped cards and switches. A loaded model catalog sheet was also captured.
- Library: native toolbar sidebar button hides and restores the meeting list. Transcript, AI notes empty state and My notes were opened. English and right-aligned Arabic stayed on an opaque reading surface; the missing-audio notice remained visible.
- Setup: reopened the Welcome page through Run Again. The card, title, footer controls and shared icon fit the window; no permission action was invoked.
- Real-window screenshots were captured with a temporary in-process ScreenCaptureKit helper restricted to the app's own windows. Ordinary external screenshot capture had no Screen Recording access. No system privacy setting was changed.
- Initial screenshots caught a wrapped Colleagues label and a system-blue model-install link. The rebuilt app's final recorder screenshot confirmed the full label and orange link. Turning off You and then attempting to turn off Colleagues kept the last source enabled (`source: system`); You was then restored.
- A recording created manually during the preview was copied to the normal library before leaving the temporary session. Both its audio and metadata were byte-compared after copying.

### Not verified

- macOS 15 fallback appearance and runtime accessibility overrides for Reduce Transparency, Increase Contrast and Reduce Motion.
- Live recording, pause, start/save transitions, waveform activity, playback and transcription after this visual update. Audio behavior was not changed or re-measured.
- Every setup permission/download step, analysis submission, update installation, and template editing.

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
