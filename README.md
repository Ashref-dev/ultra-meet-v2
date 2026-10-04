# Ultra Transcribe

A menu-bar meeting recorder for macOS. One click records your microphone (**You**) and your Mac’s audio (**Colleagues**) on separate tracks, transcribes them locally with Qwen3-ASR, and, only when you ask, turns the transcript into meeting notes with an OpenRouter model.

Requires Apple Silicon and macOS 15 or later. This build is signed with an Apple Development certificate, not notarized.

## Use

- **Left-click** the menu-bar icon: recorder panel. Toggle You / Colleagues, then **Start recording**. The meeting is created and named instantly; the panel gets out of the way.
- **Right-click** the icon: native menu with Start, Pause/Resume, Stop, Meeting Library, Settings, Quit.
- The icon is the whole status: while recording its dots move with the conversation, paused fades it, and a ripple runs while transcribing. No timer in the menu bar; the panel has it.
- While recording, the panel shows the editable meeting name, talk time per side, and a multi-line note field (Return for new lines, scrolls with soft fades) that writes straight into the meeting’s notes.
- The library sidebar collapses with the toolbar button or ⌃⌘S.
- **Stop** finalizes audio, queues local transcription and opens the meeting. Transcripts are grouped into speaker turns: You (green) and Colleagues (orange). Arabic and other right-to-left lines are right-aligned.
- **AI notes → Analyze with AI** sends the transcript text (never audio) to your OpenRouter model with the selected template. The result has a summary, discussion, decisions, action items for You and for Colleagues, and open questions. Auto-named meetings get a descriptive title; names you typed are kept.

The app is an agent (`LSUIElement`): no Dock icon, no ⌘-Tab entry.

## Settings

| Pane | What |
|---|---|
| General | Appearance, open at login, shortcuts |
| Recording | Default sources, microphone, Voice Isolation mic mode, permissions |
| Transcription | Model with measured memory and a recommendation for this Mac, languages spoken, names and terms |
| AI Analysis | OpenRouter key (validated, stored in Keychain), model picker over the live OpenRouter catalog, analysis templates |
| Storage | Audio retention, library location |

## Speech models

Measured on Apple Silicon: memory footprint (Activity Monitor “Memory”) while transcribing 2 minutes of real meeting audio.

| Model | Loaded | Peak while transcribing | Speed | Recommended for |
|---|---|---|---|---|
| Fast · Qwen3-ASR 0.6B 8-bit | 1.2 GB | 1.9 GB | ~85× real time | 8 GB Macs |
| Balanced · Qwen3-ASR 1.7B 8-bit | 2.5 GB | 3.5 GB | ~40× | 12–16 GB |
| Best · Qwen3-ASR 1.7B BF16 | 4.0 GB | 5.0 GB | ~27× | 16 GB and up |

Memory is used only while a meeting is being transcribed; the worker process exits afterwards. Long meetings add about 0.25 GB per hour per track for decoded audio.

## Transcription pipeline

`Sources/Resources/worker.py`, run in a private runtime under `~/Library/Application Support/UltraTranscribe/Runtime`:

1. Each track is decoded to mono 16 kHz and high-passed at 70 Hz.
2. A noise-floor-relative energy gate splits speech into utterances at natural pauses (≥0.45 s), so people can switch languages between sentences.
3. Each utterance gets mild spectral denoising (noise profile from the track’s own pauses) and gain normalization to −20 dBFS, up to +30 dB for quiet voices.
4. Qwen3-ASR picks the language per utterance. With **Languages spoken** set, a logits constraint limits that choice to your languages (plus “no speech”). On a real 12-minute English/Saudi-Arabic meeting this removed every Chinese, Hindi, Persian, Dutch and Russian misdetection.
5. Filler-only lines, named sound events (“Cough.”) and microphone lines that repeat Mac audio are dropped.

Transcription runs after Stop, not live. The best model transcribed that 12-minute meeting in about 70 seconds on this Mac.

## Data

```text
~/Library/Application Support/UltraTranscribe/
  Meetings/<UUID>/meeting.json, microphone.wav, system.caf, transcript.json
  Models/{best,large,small}/
  Runtime/
  preferences.json
```

Files are not encrypted by the app; use FileVault. The OpenRouter key lives in the Keychain.

## Build

```sh
swift test
bash scripts/build.sh   # builds, bundles uv and resources, signs with your Apple Development identity if present
```

Python checks: `basedpyright --project pyrightconfig.json` and `ruff check Sources/Resources/worker.py`.
