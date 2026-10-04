# /// script
# requires-python = ">=3.12"
# dependencies = ["mlx-audio==0.5.7", "numpy", "soundfile", "scipy", "typer", "pydantic"]
# ///
# Run: uv run worker.py --help. The application uses its isolated installed runtime.
from __future__ import annotations

import os
import re
import struct
import time
import unicodedata
from collections.abc import Callable, Iterator
from difflib import SequenceMatcher
from enum import StrEnum
from math import exp, gcd
from pathlib import Path
from typing import Annotated, Final, NamedTuple, Protocol, cast
from uuid import uuid4

import numpy as np
import soundfile as sf
import typer
from huggingface_hub import snapshot_download
from numpy.typing import NDArray
from pydantic import BaseModel, ConfigDict
from scipy.ndimage import maximum_filter1d, uniform_filter1d
from scipy.signal import butter, istft, resample_poly, sosfilt, sosfilt_zi, stft

app = typer.Typer(no_args_is_help=True)
MODELS: Final = {
    "small": "mlx-community/Qwen3-ASR-0.6B-8bit",
    "large": "mlx-community/Qwen3-ASR-1.7B-8bit",
    "best": "mlx-community/Qwen3-ASR-1.7B-bf16",
}
AUDIO_SUFFIXES: Final = {".wav", ".caf", ".m4a", ".mp3", ".flac", ".aiff", ".ogg"}
RATE: Final = 16000
FRAME: Final = RATE // 50  # 20 ms analysis frames
QUIET_MARGIN: Final = 4.0  # dB above the track's own noise floor: anything quieter is silence
CLEAR_MARGIN: Final = 9.0  # dB above the noise floor where clear speech starts
SPEECH_RANGE: Final = 45.0  # dB below the track's own loudest speech that still counts as clear speech
MERGE_GAP: Final = 23  # frames (~0.45 s): shorter pauses stay inside one utterance
PAD: Final = 12  # frames (~0.25 s) of context around each utterance
MIN_SPEECH: Final = 10  # frames (0.2 s) above the floor; shorter bursts are clicks
MAX_UTTERANCE: Final = 28 * 50  # frames: long monologues are split at their quietest moment
MAX_QUIET: Final = 10 * 50  # frames: quiet stretches are heard in short clips so a few words aren't lost in noise
TARGET_RMS: Final = 0.1  # -20 dBFS speech level fed to the recognizer
MAX_GAIN: Final = 100.0  # +40 dB, enough to bring a whisper up to speaking level
FFT: Final = 512
FFT_OVERLAP: Final = 384
NOISE_FLOOR: Final = 0.2  # spectral gating never removes more than -14 dB, which keeps speech artifacts low
CONFIDENT: Final = 0.8  # below this "no speech" probability, the likeliest language is decoded as well
ACCEPT: Final = 0.6  # text confidence needed to keep that reading (noise forced into English scores about 0.45)
POLL: Final = 1.5  # seconds between reads of a recording that is still growing
FINISH: Final = ".finish"  # created by the app once a followed recording's files are closed
FILLERS: Final = frozenset({
    "um", "uh", "hmm", "hm", "mm", "mhm", "oh", "ah", "eh", "er", "so", "euh", "heu", "hein", "bah", "ben",
    "اه", "ام", "امم", "ممم", "ها",
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
    confidence: float | None = None


class Transcript(BaseModel):
    model_config = ConfigDict(frozen=True)
    segments: list[Segment]


class Progress(BaseModel):
    model_config = ConfigDict(frozen=True)
    message: str
    fraction: float


class Heard(NamedTuple):
    language: str | None
    text: str
    confidence: float  # geometric-mean probability of the text tokens


class Layout(NamedTuple):
    offset: int
    size: int | None  # audio bytes, once the recorder has written the final size
    rate: int
    channels: int
    dtype: str
    scale: float


def publish(path: Path, text: str) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text)
    temporary.replace(path)


def progress(folder: Path, message: str, fraction: float) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    publish(folder / "progress.json", Progress(message=message, fraction=fraction).model_dump_json())


def pcm(offset: int, size: int | None, tag: int, channels: int, rate: int, bits: int, order: str = "<") -> Layout | None:
    kind = {(1, 16): ("i2", 1 / 32768), (1, 32): ("i4", 1 / 2**31), (3, 32): ("f4", 1.0)}.get((tag, bits))
    return Layout(offset, size, rate, channels, order + kind[0], kind[1]) if kind and channels > 0 and rate > 0 else None


def layout(head: bytes) -> Layout | None:
    """Where the samples of a WAV or CAF recording start, or None while its header is still incomplete."""
    fmt: tuple[int, int, int, int, str] | None = None
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        position = 12
        while position + 8 <= len(head):
            kind, size, body = head[position : position + 4], struct.unpack_from("<I", head, position + 4)[0], position + 8
            if kind == b"fmt " and body + 16 <= len(head):
                tag, channels, rate = struct.unpack_from("<HHI", head, body)
                if tag == 0xFFFE and body + 26 <= len(head):
                    tag = struct.unpack_from("<H", head, body + 24)[0]
                fmt = (tag, channels, rate, struct.unpack_from("<H", head, body + 14)[0], "<")
            elif kind == b"data" and fmt:
                return pcm(body, size or None, *fmt)
            position = body + size + (size & 1)
    elif head[:4] == b"caff":
        position = 8
        while position + 12 <= len(head):
            kind, size, body = head[position : position + 4], struct.unpack_from(">q", head, position + 4)[0], position + 12
            if kind == b"desc" and body + 32 <= len(head):
                rate, format_id, flags, _, _, channels, bits = struct.unpack_from(">d4sIIIII", head, body)
                if format_id == b"lpcm":
                    fmt = (3 if flags & 1 else 1, channels, int(rate), bits, "<" if flags & 2 else ">")
            elif kind == b"data" and fmt:
                return pcm(body + 4, size - 4 if size >= 4 else None, *fmt)  # data starts after a 4-byte edit count
            if size < 0:
                break
            position = body + size
    return None


class Growing:
    """Samples appended to a WAV or CAF file that is still being recorded.

    Headers are written first, so the data offset is known early. The declared size is zero or unknown until the
    recorder closes the file, so reads go to the end of the file until a real size appears.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self.position = 0
        self.layout: Layout | None = None

    def read(self) -> Audio:
        with self.path.open("rb") as file:
            self.layout = layout(file.read(65536)) or self.layout
            if self.layout is None:
                return np.zeros(0, dtype=np.float32)
            file.seek(self.layout.offset + self.position)
            data = file.read() if self.layout.size is None else file.read(max(0, self.layout.size - self.position))
        frame = np.dtype(self.layout.dtype).itemsize * self.layout.channels
        usable = len(data) - len(data) % frame
        self.position += usable
        samples = np.frombuffer(data[:usable], dtype=self.layout.dtype).astype(np.float32) * np.float32(self.layout.scale)
        return samples.reshape(-1, self.layout.channels).mean(axis=1).astype(np.float32)


def frame_levels(wave: Audio) -> NDArray[np.float64]:
    count = len(wave) // FRAME
    frames = wave[: count * FRAME].reshape(count, FRAME).astype(np.float64)
    return 10 * np.log10(np.mean(frames * frames, axis=1) + 1e-12)


class Track:
    """One source as mono 16 kHz, high-passed at 70 Hz, appended as audio arrives.

    Blocks are resampled with context on both sides, so the result is identical whether a file is read at once or
    while it is still being recorded.
    """

    def __init__(self, source: str, rate: int) -> None:
        self.source = source
        divisor = gcd(RATE, rate)
        self.up, self.down = RATE // divisor, rate // divisor
        self.context = self.down * -(-(rate // 50) // self.down)  # >= 20 ms of native audio, in whole resampling periods
        self.pending = np.zeros(0, dtype=np.float32)  # native audio from `context` before the next sample to emit
        self.lead = 0
        self.highpass = butter(2, 70, "highpass", fs=RATE, output="sos")
        self.state = sosfilt_zi(self.highpass) * 0.0
        self.buffer = np.zeros(RATE * 60, dtype=np.float32)
        self.size = 0
        self.levels = np.zeros(0)
        self.threshold = 0.0
        self.noise: NDArray[np.float64] | None = None
        self.covered: list[tuple[int, int]] = []  # frame ranges already transcribed

    @property
    def wave(self) -> Audio:
        return self.buffer[: self.size]

    def feed(self, audio: Audio, final: bool) -> None:
        self.pending = np.concatenate([self.pending, audio.astype(np.float32)])
        end = len(self.pending) if final else (len(self.pending) - self.context) // self.down * self.down
        if end <= self.lead:
            return
        resampled = self.pending if self.up == self.down else resample_poly(self.pending, self.up, self.down)
        block = np.asarray(resampled[self.lead * self.up // self.down : -(-end * self.up // self.down)], dtype=np.float64)
        filtered, self.state = sosfilt(self.highpass, block, zi=self.state)
        self.append(np.asarray(filtered, dtype=np.float32))
        keep = max(0, end - self.context)
        self.pending, self.lead = self.pending[keep:], end - keep

    def append(self, samples: Audio) -> None:
        end = self.size + len(samples)
        if end > len(self.buffer):
            grown = np.zeros(max(end, 2 * len(self.buffer)), dtype=np.float32)
            grown[: self.size] = self.buffer[: self.size]
            self.buffer = grown
        self.buffer[self.size : end] = samples
        self.size = end
        complete = self.size // FRAME
        self.levels = np.concatenate([self.levels, frame_levels(self.buffer[len(self.levels) * FRAME : complete * FRAME])])

    def ready(self, finishing: bool) -> list[tuple[int, int]]:
        """Utterances not transcribed yet whose end is known; all of them once the recording is finished.

        Regions are found again from all audio each time, because the noise floor settles as a recording grows and
        speech that was below it earlier can qualify later. Anything not yet covered is returned, so nothing is
        skipped; leftovers of a shifted region shorter than a whole utterance are only padding and are dropped.
        """
        regions, self.threshold = utterances(self.levels)
        found = [
            (start, end)
            for first, last, closed in regions
            if closed or finishing
            for start, end in uncovered(first, last, self.covered)
            if (start, end) == (first, last) or end - start >= MIN_SPEECH + 2 * PAD
        ]
        if found:
            self.noise = noise_profile(self.wave, self.levels, self.threshold)
        return found

    def clip(self, first: int, last: int) -> Audio:
        return conditioned(denoise(self.wave[first * FRAME : last * FRAME], self.noise), self.levels[first:last], self.threshold)


class Source:
    """A track file: read once when finished, or followed while the recorder is still writing it."""

    def __init__(self, path: Path, growing: bool) -> None:
        self.path = path
        self.reader = Growing(path) if growing and path.suffix.lower() in {".wav", ".caf"} else None
        self.track: Track | None = None

    def pull(self, final: bool) -> Track | None:
        if self.reader:
            audio = self.reader.read()
            if self.reader.layout is None:
                return None
            self.track = self.track or Track(self.path.stem, self.reader.layout.rate)
            self.track.feed(audio, final)
        elif self.track is None:
            with sf.SoundFile(self.path) as audio:
                track = Track(self.path.stem, audio.samplerate)
                for block in audio.blocks(blocksize=audio.samplerate * 30, dtype="float32", always_2d=True):
                    track.feed(np.asarray(block, dtype=np.float32).mean(axis=1), final=False)
            track.feed(np.zeros(0, dtype=np.float32), final=True)
            self.track = track
        return self.track


def uncovered(first: int, last: int, covered: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The parts of [first, last) outside every covered range."""
    pieces = [(first, last)]
    for start, end in covered:
        pieces = [piece for left, right in pieces for piece in ((left, min(right, start)), (max(left, end), right)) if piece[1] > piece[0]]
    return pieces


def spans(mask: NDArray[np.bool_]) -> list[tuple[int, int, bool]]:
    """Runs of true frames joined across pauses up to MERGE_GAP; a run still going at the end is not closed."""
    runs: list[tuple[int, int, bool]] = []
    start: int | None = None
    silence = 0
    for index, voiced in enumerate(mask):
        if voiced:
            if start is None:
                start = index
            silence = 0
        elif start is not None:
            silence += 1
            if silence > MERGE_GAP:
                runs.append((start, index - silence + 1, True))
                start, silence = None, 0
    if start is not None:
        runs.append((start, len(mask) - silence, False))
    return runs


def utterances(levels: NDArray[np.float64]) -> tuple[list[tuple[int, int, bool]], float]:
    """Spoken regions in frames, with whether each one has ended, and the silence threshold.

    There is no fixed loudness bar. Clear speech stands well above the track's own noise floor, or within reach
    of its own loudest speech (call codecs fill pauses with faint noise); splitting it at natural pauses keeps each
    clip in one language, which lets the recognizer follow code-switching. Anything else above the floor, such as
    a whisper or someone far from the microphone, becomes a short clip of its own and is transcribed too; the
    recognizer answers "no speech" for noise.
    """
    if len(levels) == 0:
        return [], 0.0
    floor = float(np.percentile(levels, 10))
    above = levels[levels > floor + QUIET_MARGIN]
    clear = levels > max(floor + CLEAR_MARGIN, float(np.percentile(above, 90)) - SPEECH_RANGE if len(above) >= MIN_SPEECH else -np.inf)
    quiet = (levels > floor + QUIET_MARGIN) & ~(maximum_filter1d(clear.astype(np.uint8), 2 * MERGE_GAP + 1) > 0)
    bounded: list[tuple[int, int, bool]] = []
    for mask, longest in ((clear, MAX_UTTERANCE), (quiet, MAX_QUIET)):
        for first, last, closed in spans(mask):
            if int(mask[first:last].sum()) < MIN_SPEECH:
                continue
            first, last = max(0, first - PAD), min(len(levels), last + PAD)
            while last - first > longest:
                window = levels[first + longest // 2 : first + longest]
                cut = first + longest // 2 + int(np.argmin(window))
                bounded.append((first, cut, True))
                first = cut
            bounded.append((first, last, closed))
    return sorted(bounded), floor + QUIET_MARGIN


def conditioned(wave: Audio, levels: NDArray[np.float64], threshold: float) -> Audio:
    """Raise quiet speech to a consistent level without clipping its peaks."""
    voiced = levels > threshold
    energy = 10 ** (levels[voiced] / 10) if voiced.any() else 10 ** (levels / 10)
    rms = float(np.sqrt(np.mean(energy))) + 1e-9
    peak = float(np.max(np.abs(wave))) + 1e-9 if len(wave) else 1.0
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
    if noise is None or len(clip) < FFT:
        return clip
    _, _, spectrum = stft(clip, fs=RATE, nperseg=FFT, noverlap=FFT_OVERLAP)
    gain = np.clip(1 - 1.5 * noise / (np.abs(spectrum) + 1e-9), NOISE_FLOOR, 1)
    gain = uniform_filter1d(uniform_filter1d(gain, 3, axis=0), 5, axis=1)
    _, cleaned = istft(spectrum * gain, fs=RATE, nperseg=FFT, noverlap=FFT_OVERLAP)
    return np.asarray(cleaned[: len(clip)], dtype=np.float32)


class LanguageGate:
    """Let the model detect the language, but only among the ones people speak, plus "None" for no speech.

    Qwen3-ASR starts its answer with `language <Name><asr_text>`. Masking those first tokens to the allowed names
    stops short or noisy utterances from being read as Chinese or Hindi. The probabilities where the names differ
    are kept, so an unsure "no speech" can be checked against the likeliest language. Giving the speaker's previous
    language a head start was measured and rejected: in meetings that switch language every turn it mislabeled
    short replies.
    """

    def __init__(self, tokenizer: Tokenizer, languages: list[str]) -> None:
        self.prefixes = {name: tokenizer.encode(f"language {name}<asr_text>") for name in [*languages, "None"]}
        self.odds: dict[str, float] = {}
        self.step = 0

    def __call__(self, tokens: object, logits: object) -> object:
        import mlx.core as mx

        assert isinstance(tokens, mx.array) and isinstance(logits, mx.array)
        index = self.step
        self.step += 1
        written = [int(token) for token in np.array(tokens[len(tokens) - index :])] if index else []
        live = {name: prefix for name, prefix in self.prefixes.items() if len(prefix) > index and prefix[:index] == written}
        if not live:
            return logits
        choices = {prefix[index] for prefix in live.values()}
        mask = np.full(logits.shape[-1], -np.inf, dtype=np.float32)
        mask[list(choices)] = 0
        gated = logits + mx.array(mask)
        if len(choices) > 1:
            chances = np.array(mx.softmax(gated.reshape(-1).astype(mx.float32)))
            self.odds = {name: float(chances[prefix[index]]) for name, prefix in live.items()}
        return gated


def decode(speech: Speech, clip: Audio, context: str, *, forced: str | None = None, gate: LanguageGate | None = None) -> tuple[str, list[float]]:
    """The model's raw answer and the log-probability of each generated token."""
    import mlx.core as mx

    ids: list[int] = []
    scores: list[float] = []
    for token, logprobs in speech.stream_generate(clip, max_tokens=512, language=forced, system_prompt=context or None, logits_processors=[gate] if gate else None):
        assert isinstance(logprobs, mx.array)
        ids.append(int(str(token)))
        scores.append(float(np.array(logprobs.reshape(-1)[ids[-1]].astype(mx.float32))))
    return speech._tokenizer.decode(ids, skip_special_tokens=True), scores


def certainty(scores: list[float]) -> float:
    return exp(sum(scores) / len(scores)) if scores else 0.0


def recognize(speech: Speech, clip: Audio, languages: list[str], context: str, forced: str | None = None) -> Heard:
    """Transcribe one utterance.

    An answer that only recites the names and terms prompt is decoded again without it. Quiet speech the model is
    unsure about calling silence is decoded again as the likeliest language and kept if the model reads it
    clearly; on real noise "None" is certain, so this never runs there. Text confidence is not compared across
    languages: forcing English on clear Arabic still returns confident Arabic, and one-word utterances read
    confidently as the wrong language.
    """
    if forced:
        raw, scores = decode(speech, clip, context, forced=forced)
        heard = Heard(forced, tidy(raw), certainty(scores))
        return recognize(speech, clip, languages, "", forced) if context and recited(heard.text, context) else heard
    gate = LanguageGate(speech._tokenizer, languages) if languages else None
    raw, scores = decode(speech, clip, context, gate=gate)
    detected, text = speech.extract_language(raw)
    language = None if detected in ("", "None") else detected
    answer = len(gate.prefixes.get(detected or "None", [])) if gate else 0
    heard = Heard(language, tidy(text), certainty(scores[answer:]))
    if context and recited(heard.text, context):
        return recognize(speech, clip, languages, "")
    if gate is None or language is not None or gate.odds.get("None", 1.0) >= CONFIDENT:
        return heard
    likeliest = max((chance, name) for name, chance in gate.odds.items() if name != "None")[1]
    other = recognize(speech, clip, languages, context, forced=likeliest)
    return other if other.confidence >= ACCEPT and meaningful(other.text, context) else heard


def tidy(text: str) -> str:
    """Arabic punctuation after Arabic words, no tatweel, single spaces."""
    text = re.sub(r"(?<=[\u0600-\u06FF])\s*([?,;])", lambda match: {"?": "؟", ",": "،", ";": "؛"}[match.group(1)], text.replace("\u0640", ""))
    return " ".join(text.split())


def meaningful(text: str, context: str) -> bool:
    """Reject filler-only lines and the model reciting its names and terms prompt back."""
    spoken = words(text)
    return bool(spoken) and not all(word in FILLERS for word in spoken) and not recited(text, context)


def recited(text: str, context: str) -> bool:
    spoken, hint = words(text), set(words(context))
    return len(spoken) >= 3 and sum(word in hint for word in spoken) / len(spoken) >= 0.8


def words(text: str) -> list[str]:
    """Lowercase words without accents, Arabic diacritics or hamza seats, so two readings of one sentence match."""
    plain = unicodedata.normalize("NFKD", text)
    return "".join("" if unicodedata.combining(character) else character.lower() if character.isalnum() else " " for character in plain).split()


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


def load_speech(models: Path, model: ASRSize) -> Speech:
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    from mlx_audio.stt import load

    return cast(Speech, load(str(models / model)))


def tracks_in(folder: Path) -> list[Path]:
    return sorted(path for path in folder.iterdir() if path.suffix.lower() in AUDIO_SUFFIXES)


def spoken_languages(languages: str) -> list[str]:
    return [name.strip() for name in languages.split(",") if name.strip()]


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
    follow: Annotated[bool, typer.Option(help="Transcribe while the meeting records, until the app creates .finish.")] = False,
) -> None:
    """Transcribe every track utterance by utterance, in time order across speakers, keeping who said what."""
    parent = os.getppid()
    progress(folder, "Finding speech…", 0.02)
    (folder / "transcript.partial.json").unlink(missing_ok=True)
    finish = folder / FINISH
    spoken = spoken_languages(languages)
    sources: dict[Path, Source] = {}
    speech = load_speech(models, model) if follow else None
    segments: list[Segment] = []
    while True:
        # If the app quits or crashes mid-recording, finish what was recorded instead of waiting forever.
        finishing = not follow or finish.exists() or os.getppid() != parent
        for path in tracks_in(folder):
            sources.setdefault(path, Source(path, growing=follow))
        tracks = [track for source in sources.values() if (track := source.pull(final=finishing))]
        if finishing and not tracks:
            raise typer.BadParameter("No retained audio was found for this meeting.")
        work = sorted(((first, last, track) for track in tracks for first, last in track.ready(finishing)), key=lambda item: item[0])
        if work and speech is None:
            progress(folder, "Loading the local speech model…", 0.05)
            speech = load_speech(models, model)
        for index, (first, last, track) in enumerate(work):
            assert speech is not None
            offset = first * FRAME / RATE
            progress(folder, f"Transcribing · {int(offset // 60):02d}:{int(offset % 60):02d}", 0.05 + 0.95 * index / len(work))
            heard = recognize(speech, track.clip(first, last), spoken, vocabulary)
            track.covered.append((first, last))
            if meaningful(heard.text, vocabulary):
                segments.append(Segment(id=str(uuid4()), start=offset, end=last * FRAME / RATE, text=heard.text, source=track.source, language=heard.language, confidence=round(heard.confidence, 3)))
                publish(folder / "transcript.partial.json", Transcript(segments=without_echo(sorted(segments, key=lambda item: item.start))).model_dump_json())
        if finishing:
            break
        time.sleep(POLL)
    publish(folder / "transcript.json", Transcript(segments=without_echo(sorted(segments, key=lambda item: item.start))).model_dump_json())
    finish.unlink(missing_ok=True)
    progress(folder, "Transcript saved locally", 1)


@app.command()
def line(
    folder: Path,
    models: Path,
    source: Annotated[str, typer.Option()],
    start: Annotated[float, typer.Option()],
    end: Annotated[float, typer.Option()],
    model: Annotated[ASRSize, typer.Option()] = ASRSize.best,
    language: Annotated[str, typer.Option(help="Force this language; empty detects among --languages.")] = "",
    languages: Annotated[str, typer.Option()] = "",
    vocabulary: Annotated[str, typer.Option()] = "",
) -> None:
    """Transcribe one line again, for example as another language, and save the result to line.json."""
    path = next((path for path in tracks_in(folder) if path.stem == source), None)
    if path is None:
        raise typer.BadParameter("The audio for this line is no longer on this Mac.")
    track = Source(path, growing=False).pull(final=True)
    assert track is not None
    track.ready(finishing=True)
    first, last = max(0, int(start * 50)), min(len(track.levels), int(end * 50) + 1)
    if last - first < 5:
        raise typer.BadParameter("This line is too short to transcribe again.")
    heard = recognize(load_speech(models, model), track.clip(first, last), spoken_languages(languages), vocabulary, forced=language or None)
    publish(folder / "line.json", Segment(id=str(uuid4()), start=start, end=end, text=heard.text, source=source, language=heard.language, confidence=round(heard.confidence, 3)).model_dump_json())


if __name__ == "__main__":
    try:
        app()
    except (OSError, RuntimeError, ValueError) as error:
        typer.echo(f"Local processing error: {error}", err=True)
        raise SystemExit(1) from error
