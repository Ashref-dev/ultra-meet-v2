# Review and polish ledger

> This ledger covers the 1.0 review. 2.0 (menu-bar redesign, OpenRouter analysis, recognition changes) is documented in QA.md.

## Scope and model restriction

Native SwiftUI/AppKit macOS meeting recorder, Apple Silicon, macOS 15+. User requires fully local recording and transcription, English notes from English/French/Spanish conversation, optional explicitly confirmed OpenRouter cleanup, menu-bar-only or full-window operation, searchable history and recordings, adjustable retention, and Qwen small/large choices. The user additionally requires comprehensive GPT-only deep-agent review and a creative production-quality UI/UX and micro-interaction polish phase.

Verified routing: `deep` and `oracle` use `openai/gpt-6.1-sol` in the active OMO configuration. Other category defaults are not uniformly GPT, so they are not authorized for this review. Reviewers are leaf agents: no further delegation, no edits, no paid API requests, and no changes to the real meeting library or Keychain. Actual child model metadata must be recorded with results.

## Architecture

- `Sources/Core`: meeting metadata, preferences, local storage, recovery, capture lifecycle, processing orchestration and Keychain access.
- `Sources/Recording`: AVAudioRecorder microphone capture, Core Audio private global tap for audio-only system capture, monotonic pause-aware clock, audio import and playback.
- `Sources/Services`: isolated local subprocess engine and explicit OpenRouter transcript-only cleanup.
- `Sources/Resources/worker.py`: MLX Qwen ASR in bounded, silence-aware chunks; atomic partial/final transcript publication; local Qwen English notes with bounded map/reduce.
- `Sources/Views`: warm paper/orange/dot-matrix native library, compact menu-bar recorder, consent sheet and five settings sections.
- `packaging` and `scripts`: optimized ad-hoc-signed application bundle with resources, original icon and bundled uv installer.

## Verification already observed

- Optimized build and installed copy at `~/Applications/Ultra Transcribe.app` launch successfully.
- Swift tests: 14 passed. Python worker: basedpyright and Ruff passed.
- SourceKit diagnostics have been clean on application sources; one transient diagnostic timeout cleared on retry.
- Both local ASR sizes and the local English text model are installed and executed.
- A synthetic English/French/Spanish audio import produced a source transcript and correct English decisions/action notes.
- Actual Core Audio system capture recorded synthesized speech from another process and produced correct local transcripts and English notes.
- Microphone capture produced a valid local PCM file; the quiet input/no-speech path was exercised. A live human microphone/remote-call check is still required.
- Consent, microphone/system-audio permission prompts, pause/resume, stop/transcribe and menu-bar-only launch across restart have been exercised.
- Runtime dependency setup was repaired through the normal Settings action after introducing the completion-marker check.
- A final silence-gap recording produced 14.84 seconds of meeting time, 15.69 seconds of system audio and 14.69 seconds of microphone audio. The source startup offset is under one second; the deliberate four-second silent interval was retained.
- Transcript timestamp playback, replay, pause, seek, copy and Markdown export were exercised through the UI. Export was written under `.qa/` and contained notes and source transcript.
- Worker CLI help and invalid model input were exercised in tmux.
- The installed copy operates from its own resource bundle, not a development executable. Further clean-environment/checkout-unavailable verification remains in the final gate.

## Known validation limits

- No OpenRouter key was supplied; genuine paid cloud completion is not verified. The path must remain explicitly opt-in and audio must never be uploaded.
- No multi-hour real teammate meeting, physical headset switching, or Intel Mac test has been performed. Intel is not a supported target.
- The application is ad-hoc signed, not Developer ID notarized. External distribution needs signing/notarization credentials.
- Some draft screenshot captures were obscured by other native windows. Those are invalid evidence and must be replaced rather than reviewed as product screenshots.

## Review lanes

| Lane | Model | State | Evidence/report |
|---|---|---|---|
| Goal and constraint verification | openai/gpt-6.1-sol | PASS | Original blockers resolved; runtime limits explicit |
| Code quality and lifecycle integrity | openai/gpt-6.1-sol | PASS at bounded integrity scope | Final obsolete-checkpoint ordering fix independently confirmed |
| Privacy and security boundaries | openai/gpt-6.1-sol | PASS for first-party scope | Zero confirmed blockers; network-denied inference passed; broader certification excluded |
| Isolated hands-on QA | openai/gpt-6.1-sol | PASS | Independent 22-test run; parent final 23-test run includes last ordering regression |
| Context, docs and requirement consistency | openai/gpt-6.1-sol | Implementation passes; two final doc corrections applied | Available/partial transcript wording and pinned-model retry semantics corrected |
| My complete source/behavior review | openai/gpt-6.1-sol parent | Completed | Confirmed blockers fixed without broad refactor; all application files remain small |
| Native visual, accessibility and interaction review | openai/gpt-6.1-sol Oracle ×2 | PASS at final fix-verification scope | Compact copy fully wraps; selected-tab/icon semantics explicit; reference adaptation approved |

## Polish direction

Preserve the supplied warm-white/orange/dot-matrix identity. Improve craft through precise hierarchy, optical alignment, intentional density, legible transcript reading, trustworthy state feedback and native Mac behavior, not decorative web-style effects. Motion should communicate recording energy, pause/resume, processing, selection and successful actions, with a Reduce Motion path. Inspect small and default window sizes, light/dark, long titles, empty/error/loading/success states, keyboard navigation and the compact recorder. The reference is available at `~/Downloads/image.png`; current design decisions are in `DESIGN.md`.

## Completion gate

All confirmed blocking review findings fixed with focused behavioral coverage; native workflow personally used on the current build; independent GPT code and visual verdicts collected; final build, diagnostics, tests and packaged resource checks pass; reviewed screenshots and limits documented in `QA.md`; no debug-only source or temporary production content shipped.

## Bounded remediation

1. Bind capture errors to their originating recorder/session and retain incomplete startup/import provenance.
2. Exclude all protected meeting IDs from automatic retention.
3. Own long-running work with a single cancellable task; check cancellation at phase boundaries and await owned work before quit, including cloud cleanup.
4. Keep previous generated notes explicitly stale when the transcript changes; publish/recover only current-run summary artifacts and retain provenance in exports.
5. Represent completed no-speech transcripts without requiring the English model.
6. Make repeated pause idempotent, reconcile login status, correct setup-network wording and publish the final QA record.

No new product features or speculative abstractions are authorized by this remediation list. Existing core behavior and original transcript/audio files are preserved.

## Final result

All confirmed blocking findings are closed. Final validation: 23 Swift tests passed, Python type/lint checks passed, optimized signed bundle built, changed-source diagnostics clean. Installed app: `~/Applications/Ultra Transcribe.app`; build copy and distributable zip are under `build/`. `QA.md` records actual checks and limits. Runtime VoiceOver, a real teammate call, multi-hour/device-switch stress, paid OpenRouter success and Developer ID notarization remain outside the verified scope. No additional polish cycle is requested by either visual gate.
