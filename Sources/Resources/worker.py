# /// script
# requires-python = ">=3.12"
# dependencies = ["mlx-audio==0.5.7", "numpy", "soundfile", "scipy", "typer", "pydantic"]
# ///
# Run: uv run worker.py --help. The application uses its isolated installed runtime.
from __future__ import annotations

import os
from collections.abc import Callable, Iterator
from difflib import SequenceMatcher
from enum import StrEnum
from pathlib import Path
from typing import Annotated, Final, Protocol, cast
from uuid import uuid4

import numpy as np
import soundfile as sf
import typer
from huggingface_hub import snapshot_download
from numpy.typing import NDArray
from pydantic import BaseModel, ConfigDict
from scipy.ndimage import uniform_filter1d
from scipy.signal import butter, istft, resample_poly, sosfilt, stft

app = typer.Typer(no_args_is_help=True)
MODELS: Final = {
    "small": "mlx-community/Qwen3-ASR-0.6B-8bit",
    "large": "mlx-community/Qwen3-ASR-1.7B-8bit",
    "best": "mlx-community/Qwen3-ASR-1.7B-bf16",
}
AUDIO_SUFFIXES: Final = {".wav", ".caf", ".m4a", ".mp3", ".flac", ".aiff", ".ogg"}
RATE: Final = 16000
FRAME: Final = RATE // 50  # 20 ms analysis frames
MERGE_GAP: Final = 23  # frames (~0.45 s): shorter pauses stay inside one utterance
PAD: Final = 12  # frames (~0.25 s) of context around each utterance
MIN_SPEECH: Final = 15  # frames (~0.3 s): shorter bursts are clicks or breaths
MAX_UTTERANCE: Final = 28 * 50  # frames: long monologues are split at their quietest moment
TARGET_RMS: Final = 0.1  # -20 dBFS speech level fed to the recognizer
MAX_GAIN: Final = 31.6  # +30 dB, enough for a quiet voice without amplifying silence
FFT: Final = 512
FFT_OVERLAP: Final = 384
NOISE_FLOOR: Final = 0.2  # spectral gating never removes more than -14 dB, which keeps speech artifacts low
FILLERS: Final = frozenset({
    "um", "uh", "hmm", "hm", "mm", "mhm", "oh", "ah", "eh", "er", "so",
    "cough", "coughing", "sniff", "sniffing", "sigh", "laughter", "laughing", "laughs", "breathing", "music", "applause", "clapping", "noise", "silence",
})  # fillers, and sound events the model names instead of transcribing

Audio = NDArray[np.float32]


class ASRSize(StrEnum):
    small = "small"
    large = "large"
    best = "best"


class Tokenizer(Protocol):
    def encode(self, text: str) -> list[int]: ...
    def decode(self, ids: list[int], skip_special_tokens: bool) -> str: ...


class Speech(Protocol):
    _tokenizer: Tokenizer

    def stream_generate(self, audio: Audio, *, max_tokens: int, language: str | None, system_prompt: str | None, logits_processors: list[Callable[[object, object], object]] | None) -> Iterator[tuple[object, object]]: ...
    def extract_language(self, text: str) -> tuple[str, str]: ...


class Segment(BaseModel):
    model_config = ConfigDict(frozen=True)
    id: str
    start: float
    end: float
    text: str
    source: str
    language: str | None = None


class Transcript(BaseModel):
    model_config = ConfigDict(frozen=True)
    segments: list[Segment]


class Progress(BaseModel):
    model_config = ConfigDict(frozen=True)
    message: str
    fraction: float


def publish(path: Path, text: str) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text)
    temporary.replace(path)


def progress(folder: Path, message: str, fraction: float) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    publish(folder / "progress.json", Progress(message=message, fraction=fraction).model_dump_json())


def load_track(path: Path) -> Audio:
    """Mono 16 kHz audio, high-passed to remove rumble and DC before analysis."""
    parts: list[Audio] = []
    with sf.SoundFile(path) as audio:
        rate = audio.samplerate
        for block in audio.blocks(blocksize=rate * 30, dtype="float32", always_2d=True):
            parts.append(resample_poly(block.mean(axis=1), RATE, rate).astype(np.float32))
    if not parts:
        return np.zeros(0, dtype=np.float32)
    highpass = butter(2, 70, "highpass", fs=RATE, output="sos")
    return np.asarray(sosfilt(highpass, np.concatenate(parts)), dtype=np.float32)


def frame_levels(wave: Audio) -> NDArray[np.float64]:
    count = len(wave) // FRAME
    frames = wave[: count * FRAME].reshape(count, FRAME).astype(np.float64)
    return 10 * np.log10(np.mean(frames * frames, axis=1) + 1e-12)


def utterances(levels: NDArray[np.float64]) -> tuple[list[tuple[int, int]], float]:
    """Find spoken regions (in frames) using a noise-floor-relative energy gate.

    Splitting at natural pauses keeps each utterance in one language, which lets the
    recognizer follow code-switching (English → Arabic → French) instead of forcing
    the first detected language onto a long chunk.
    """
    if len(levels) == 0:
        return [], 0.0
    threshold = float(np.clip(np.percentile(levels, 10) + 9, -62, -30))
    speech = levels > threshold
    regions: list[tuple[int, int]] = []
    start: int | None = None
    silence = 0
    for index, voiced in enumerate(speech):
        if voiced:
            if start is None:
                start = index
            silence = 0
        elif start is not None:
            silence += 1
            if silence > MERGE_GAP:
                regions.append((start, index - silence + 1))
                start, silence = None, 0
    if start is not None:
        regions.append((start, len(speech) - silence))
    bounded: list[tuple[int, int]] = []
    for first, last in regions:
        if int(speech[first:last].sum()) < MIN_SPEECH:
            continue
        first, last = max(0, first - PAD), min(len(levels), last + PAD)
        while last - first > MAX_UTTERANCE:
            window = levels[first + MAX_UTTERANCE // 2 : first + MAX_UTTERANCE]
            cut = first + MAX_UTTERANCE // 2 + int(np.argmin(window))
            bounded.append((first, cut))
            first = cut
        bounded.append((first, last))
    return bounded, threshold


def conditioned(wave: Audio, levels: NDArray[np.float64], threshold: float) -> Audio:
    """Raise quiet speech to a consistent level without clipping its peaks."""
    voiced = levels > threshold
    energy = 10 ** (levels[voiced] / 10) if voiced.any() else 10 ** (levels / 10)
    rms = float(np.sqrt(np.mean(energy))) + 1e-9
    peak = float(np.max(np.abs(wave))) + 1e-9
    gain = min(MAX_GAIN, TARGET_RMS / rms, 0.98 / peak)
    return (wave * max(1.0, gain)).astype(np.float32)


def noise_profile(wave: Audio, levels: NDArray[np.float64], threshold: float) -> NDArray[np.float64] | None:
    """Median spectrum of up to ~30 s of the track's own pauses: the room or line noise to subtract."""
    quiet = np.flatnonzero(levels <= threshold)
    if len(quiet) < 50:
        return None
    quiet = quiet[:: max(1, len(quiet) // 1500)]
    sample = np.concatenate([wave[index * FRAME : (index + 1) * FRAME] for index in quiet])
    _, _, spectrum = stft(sample, fs=RATE, nperseg=FFT, noverlap=FFT_OVERLAP)
    return np.median(np.abs(spectrum), axis=1, keepdims=True)


def denoise(clip: Audio, noise: NDArray[np.float64] | None) -> Audio:
    """Mild spectral gating: attenuate bins near the noise floor, smoothed to avoid musical noise."""
    if noise is None:
        return clip
    _, _, spectrum = stft(clip, fs=RATE, nperseg=FFT, noverlap=FFT_OVERLAP)
    gain = np.clip(1 - 1.5 * noise / (np.abs(spectrum) + 1e-9), NOISE_FLOOR, 1)
    gain = uniform_filter1d(uniform_filter1d(gain, 3, axis=0), 5, axis=1)
    _, cleaned = istft(spectrum * gain, fs=RATE, nperseg=FFT, noverlap=FFT_OVERLAP)
    return np.asarray(cleaned[: len(clip)], dtype=np.float32)


def language_constraint(tokenizer: Tokenizer, languages: list[str]) -> Callable[[object, object], object]:
    """Let the model detect the language, but only among the ones the user speaks.

    Qwen3-ASR starts its answer with `language <Name><asr_text>`. Masking those first tokens
    to the allowed names stops short or noisy utterances from being read as Chinese or Hindi.
    """
    import mlx.core as mx

    prefixes = [tokenizer.encode(f"language {name}<asr_text>") for name in [*languages, "None"]]  # "None" = no speech
    step = 0

    def constrain(tokens: object, logits: object) -> object:
        nonlocal step
        index = step
        step += 1
        assert isinstance(tokens, mx.array) and isinstance(logits, mx.array)
        written = [int(token) for token in np.array(tokens[len(tokens) - index :])] if index else []
        allowed = {prefix[index] for prefix in prefixes if len(prefix) > index and prefix[:index] == written}
        if not allowed:
            return logits
        mask = np.full(logits.shape[-1], -np.inf, dtype=np.float32)
        mask[list(allowed)] = 0
        return logits + mx.array(mask)

    return constrain


def recognize(speech: Speech, clip: Audio, languages: list[str], context: str) -> tuple[str | None, str]:
    forced = languages[0] if len(languages) == 1 else None
    constraint = [language_constraint(speech._tokenizer, languages)] if len(languages) > 1 else None
    ids = [int(str(token)) for token, _ in speech.stream_generate(clip, max_tokens=512, language=forced, system_prompt=context or None, logits_processors=constraint)]
    raw = speech._tokenizer.decode(ids, skip_special_tokens=True)
    if forced:
        return forced, raw.strip()
    detected, text = speech.extract_language(raw)
    return (None if detected in ("", "None") else detected), text.strip()


def meaningful(text: str, context: str) -> bool:
    """Reject filler-only lines and the model reciting its context prompt back on near-silence."""
    spoken = words(text)
    if not spoken or all(word in FILLERS for word in spoken):
        return False
    hint = set(words(context))
    return not (len(spoken) >= 3 and sum(word in hint for word in spoken) / len(spoken) >= 0.8)


def words(text: str) -> list[str]:
    return [word for word in "".join(character.lower() if character.isalnum() else " " for character in text).split() if word]


def without_echo(segments: list[Segment]) -> list[Segment]:
    """Drop microphone lines that merely repeat Mac audio picked up from the speakers."""
    others = [segment for segment in segments if segment.source != "microphone"]
    kept: list[Segment] = []
    for segment in segments:
        spoken = words(segment.text)
        if segment.source == "microphone" and spoken:
            heard = [word for other in others if other.start < segment.end + 2 and other.end > segment.start - 2 for word in words(other.text)]
            matched = sum(block.size for block in SequenceMatcher(None, spoken, heard, autojunk=False).get_matching_blocks())
            if heard and matched / len(spoken) >= 0.7:
                continue
        kept.append(segment)
    return kept


@app.command()
def download(models: Path, model: Annotated[ASRSize, typer.Option()] = ASRSize.best) -> None:
    """Download public speech-model weights once; recording and inference never upload data."""
    progress(models, f"Downloading {MODELS[model]}. This can take several minutes…", 0.05)
    snapshot_download(
        MODELS[model],
        local_dir=models / model,
        allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "*.tiktoken", "*.jinja"],
    )
    (models / model / ".ready").write_text(MODELS[model])
    progress(models, "Speech model ready for offline use", 1)


@app.command()
def transcribe(
    folder: Path,
    models: Path,
    model: Annotated[ASRSize, typer.Option()] = ASRSize.best,
    languages: Annotated[str, typer.Option(help="Comma-separated languages people speak; empty detects any.")] = "",
    vocabulary: Annotated[str, typer.Option()] = "",
) -> None:
    """Transcribe each source track utterance by utterance, keeping speaker provenance."""
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    from mlx_audio.stt import load

    progress(folder, "Finding speech…", 0.02)
    (folder / "transcript.partial.json").unlink(missing_ok=True)
    tracks = sorted(path for path in folder.iterdir() if path.suffix.lower() in AUDIO_SUFFIXES)
    if not tracks:
        raise typer.BadParameter("No retained audio was found for this meeting.")
    work: list[tuple[str, Audio, NDArray[np.float64], float, list[tuple[int, int]], NDArray[np.float64] | None]] = []
    for track in tracks:
        wave = load_track(track)
        levels = frame_levels(wave)
        regions, threshold = utterances(levels)
        work.append((track.stem, wave, levels, threshold, regions, noise_profile(wave, levels, threshold)))
    total = sum(len(item[4]) for item in work)
    segments: list[Segment] = []
    if total:
        progress(folder, "Loading the local speech model…", 0.05)
        speech = cast(Speech, load(str(models / model)))
        spoken = [name.strip() for name in languages.split(",") if name.strip()]
        done = 0
        for source, wave, levels, threshold, regions, noise in work:
            for first, last in regions:
                done += 1
                offset = first * FRAME / RATE
                progress(folder, f"Transcribing · {int(offset // 60):02d}:{int(offset % 60):02d}", 0.05 + 0.95 * done / total)
                clip = conditioned(denoise(wave[first * FRAME : last * FRAME], noise), levels[first:last], threshold)
                language, text = recognize(speech, clip, spoken, vocabulary)
                if meaningful(text, vocabulary):
                    segments.append(Segment(id=str(uuid4()), start=offset, end=last * FRAME / RATE, text=text, source=source, language=language))
                    publish(folder / "transcript.partial.json", Transcript(segments=sorted(segments, key=lambda item: item.start)).model_dump_json())
    final = without_echo(sorted(segments, key=lambda item: item.start))
    publish(folder / "transcript.json", Transcript(segments=final).model_dump_json())
    progress(folder, "Transcript saved locally", 1)


if __name__ == "__main__":
    try:
        app()
    except (OSError, RuntimeError, ValueError) as error:
        typer.echo(f"Local processing error: {error}", err=True)
        raise SystemExit(1) from error
