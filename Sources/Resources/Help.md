# Ultra Transcribe

Ultra Transcribe lives in the menu bar. Click the dot-matrix icon for the recorder; right-click it for Start, Pause, Stop, Meeting Library, Settings and Quit. It never appears in the Dock or the app switcher.

**Record.** Choose who gets recorded with the You (microphone, green) and Colleagues (Mac audio, orange) toggles, then Start recording. The meeting is created and named automatically; rename it any time by clicking its name. While recording, the panel shows talk time per side and a note field; Return starts a new line and everything you write is saved to the meeting. Get everyone’s consent before recording.

**Microphone.** Settings → Recording → Records You chooses the microphone. Automatic uses your default input, except a Bluetooth headset: opening its microphone switches it to call quality and makes everything you hear through it muffled, so your Mac's microphone records you instead. Switching speakers, headphones or microphones during a meeting is fine; recording moves to the new device.

**Transcribe.** With Transcribe while recording on (Settings → Transcription), lines appear in the panel during the meeting and Stop only finishes the last moments. Stop opens the transcript, grouped by You and Colleagues. Quiet voices and whispers are picked up; only silence is skipped. Audio never leaves the Mac. Settings → Transcription sets the model and the languages people speak; choosing only those (for example English and Arabic) prevents short sounds from being read as other languages.

**Speech models.** Settings → Transcription lists every local model with its download size, memory and speed. Download or delete any of them there; the selected one transcribes new meetings. Qwen3-ASR and Whisper recognize each sentence as one of your languages, Cohere transcribes one language you choose, and Parakeet, Granite and Voxtral detect the language themselves. A meeting keeps the model it was transcribed with while that model is installed.

**Analyze with AI.** In a meeting’s AI notes tab, pick a template and click Analyze with AI. The transcript text, never audio, goes to the OpenRouter model you chose in Settings → AI Analysis. You get a summary, decisions and action items for you and your colleagues, and automatically named meetings get a descriptive title. Templates are editable system prompts. Settings → AI Analysis → Analyze after transcription writes notes automatically when a meeting is transcribed.

**Transcript.** The conversation map shows when each side spoke; click it, a timestamp or a line to play both sides from there, at up to 2×. Double-click a line to fix a typo; Return or clicking away saves, Esc cancels. Underlined lines were hard to hear. Right-click a line to copy it or transcribe it again as another language; new names in a correction can be added to Names and terms. If a meeting's audio was deleted, the transcript says so and stays readable.

**Trim.** Drag the orange handles at the ends of the conversation map, or right-click a line and choose Start Meeting Here or End Meeting Here, to leave out the start or the end of a meeting, such as small talk after the call. The cut part isn't shown, played, analyzed, exported or copied, and nothing is deleted: Restore, under the map, brings it back.

**Library.** Search titles, transcripts and notes; accents and Arabic spelling variants are ignored. Swipe left on a row to reveal its round Trash button, then click and confirm to move the meeting and its audio to the Finder Trash. Recording and processing meetings cannot be trashed. Drop an audio file on the library window to import and transcribe it. Copy copies the open tab; Export saves everything as Markdown. A meeting's header names the speech model that transcribed it. Once a meeting is transcribed, its audio is stored as lossless FLAC, about a ninth of the recorded size. Audio of transcribed meetings is deleted after the retention period in Settings → Storage; transcripts and notes are kept.

**Appearance.** Settings → General offers System, Light and Dark; macOS settings for reduced transparency, increased contrast and reduced motion are followed. ⌃⌘S or the toolbar button shows and hides the library sidebar.

**Updates.** Settings → Credits checks GitHub for new versions and installs them after verifying the signature; the app also checks daily and notifies you. Settings → General → Run Again reopens the first-run setup.

Shortcuts: ⌃⌥⌘R start or stop from any app, ⌘N start recording, ⌘⇧P pause/resume, ⌘⇧S stop, ⌘L library, ⌘F search, ↑ and ↓ move between meetings, ⌫ moves one to the Trash after confirming, Space plays or pauses a meeting's audio, ⌘1 to ⌘3 switch tabs, ⌘⇧C copy the open tab, ⌘⇧E export, ⌃⌘S toggle sidebar, ⌘O import audio, ⌘, settings.
