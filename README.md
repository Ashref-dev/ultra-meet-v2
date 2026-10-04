<p align="center"><img src="docs/cover.png" alt="Ultra Transcribe" width="820"></p>

# Ultra Transcribe

**Meeting notes for the AI-native era.** Ultra Transcribe is a macOS menu-bar app for teams that meet often and need clear notes fast. Start a meeting in one click, get an accurate transcript that shows what you said and what your colleagues said, then turn it into a summary, decisions and action items when you need them.

- **One click from the menu bar.** Meetings start instantly and name themselves. No window to manage, no Dock icon.
- **Clear speaker labels.** Your microphone is recorded as **You** and your Mac's call audio as **Colleagues**, on separate tracks.
- **Transcribed on your Mac.** Qwen3-ASR runs locally on Apple Silicon. Audio is never uploaded.
- **Multilingual by design.** People can switch languages sentence by sentence; you choose which languages your meetings use.
- **AI notes on demand.** Click **Analyze with AI** to send the transcript text to the OpenRouter model you choose, with templates for different kinds of meetings.

Ultra Transcribe is built for consensual meetings. Let participants know when you record.

By [achraf.tn](https://achraf.tn) · [ultra.achraf.tn](https://ultra.achraf.tn)

## Install

Download the latest release from [Releases](https://github.com/Ashref-dev/ultra-meet-v2/releases), unzip it and move **Ultra Transcribe** to Applications. Requires an Apple Silicon Mac with macOS 15 or later.

This pre-release is signed for development and not yet notarized. On first launch, right-click the app and choose **Open**. macOS then asks for microphone and system-audio permission. Settings → Transcription downloads the speech model once.

## Use

- **Left-click** the menu-bar icon for the recorder: choose You and Colleagues, then **Start recording**. While recording you see the meeting name (click to rename), talk time per side, a live waveform and a note field.
- **Right-click** the icon for Start, Pause, Resume, Stop, Meeting Library, Settings and Quit.
- **Stop** saves the audio, transcribes it and opens the meeting. Transcripts are grouped into speaker turns, with right-to-left languages aligned correctly.
- **AI notes → Analyze with AI** produces a summary, discussion, decisions, action items for you and for your colleagues, and open questions. Automatically named meetings get a descriptive title.

| Shortcut | Action |
|---|---|
| ⌘N | Start recording |
| ⌘⇧P | Pause or resume |
| ⌘⇧S | Stop and transcribe |
| ⌘L | Meeting library |
| ⌃⌘S | Toggle sidebar |
| ⌘, | Settings |

## Speech models

Measured on Apple Silicon while transcribing two minutes of real meeting audio.

| Model | Peak memory | Speed | Recommended for |
|---|---|---|---|
| Fast · Qwen3-ASR 0.6B 8-bit | 1.9 GB | about 85× real time | 8 GB Macs |
| Balanced · Qwen3-ASR 1.7B 8-bit | 3.5 GB | about 40× | 12 to 16 GB |
| Best · Qwen3-ASR 1.7B BF16 | 5.0 GB | about 27× | 16 GB and up |

Memory is used only while a meeting is being transcribed. Settings shows these numbers and recommends a model for your Mac.

## How transcription works

`Sources/Resources/worker.py` runs in a private Python runtime:

1. Each track is decoded to mono 16 kHz and high-passed at 70 Hz.
2. Speech is split into utterances at natural pauses, so each one is usually in a single language.
3. Each utterance is lightly denoised and normalized, which lifts quiet voices by up to 30 dB.
4. Qwen3-ASR detects the language of each utterance, limited to the languages you chose in Settings.
5. Filler words, named sound events and microphone lines that repeat the call audio are removed.

On a 12-minute English and Saudi Arabic meeting, limiting detection to English and Arabic removed every misdetected language. Transcription runs after you stop, not live.

## Privacy

- Audio and transcripts stay in `~/Library/Application Support/UltraTranscribe`.
- Nothing is sent anywhere unless you click Analyze with AI, validate a key, open the model catalog or download a model.
- Your OpenRouter key is stored in the macOS Keychain.
- Audio of transcribed meetings is deleted after the retention period you choose; transcripts and notes are kept.

## Build from source

```sh
swift test
bash scripts/build.sh            # signed app in build/
bash scripts/icon/generate.sh    # app icon from Sources/Views/LogoGlyph.swift
bash scripts/cover/generate.sh   # docs/cover.png
```

Python checks: `basedpyright --project pyrightconfig.json` and `ruff check Sources/Resources/worker.py`. Contributor guidance is in [AGENTS.md](AGENTS.md), design decisions in [DESIGN.md](DESIGN.md), and release notes in [CHANGELOG.md](CHANGELOG.md).
