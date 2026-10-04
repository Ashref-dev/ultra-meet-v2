# Recognition regression set: synthetic two-track meetings with known text, language and speaker.
#
#   PY=~/Library/Application\ Support/UltraTranscribe/Runtime/bin/python
#   $PY scripts/eval/eval.py make /tmp/set                 # You on microphone.wav, Colleagues on system.caf
#   $PY Sources/Resources/worker.py transcribe /tmp/set ~/Library/Application\ Support/UltraTranscribe/Models --languages English,Arabic,French
#   $PY scripts/eval/eval.py score /tmp/set
#   $PY scripts/eval/eval.py replay /tmp/set /tmp/live     # rewrite the tracks in real time, to test --follow
#
# Voices are macOS text-to-speech, mixed at the levels of a real quiet laptop microphone (speech around -45 dBFS,
# room noise at -72 dBFS) with colleagues leaking into the microphone. It complements, never replaces, real meetings.
from __future__ import annotations

import json
import subprocess
import tempfile
import time
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import Final, NamedTuple

import numpy as np
import soundfile as sf
import typer
from numpy.typing import NDArray
from scipy.signal import resample_poly

app = typer.Typer(no_args_is_help=True)
RATE: Final = 48000


class Line(NamedTuple):
    source: str  # microphone (You) or system (Colleagues)
    voice: str
    language: str
    level: float  # speech RMS in dBFS
    text: str


SCRIPT: Final = [
    Line("system", "Samantha", "English", -22, "Good morning everyone, let's start with the launch plan for next week."),
    Line("microphone", "Daniel", "English", -45, "Sure. The landing page is ready, but the pricing section still needs a review."),
    Line("system", "Majed", "Arabic", -22, "ممتاز، سنراجع قسم الأسعار غدا صباحا مع فريق التسويق."),
    Line("microphone", "Thomas", "French", -45, "D'accord, je vais préparer la présentation pour jeudi après-midi."),
    Line("system", "Amélie", "French", -22, "Parfait. Est-ce que le budget est validé?"),
    Line("microphone", "Majed", "Arabic", -52, "نعم، الميزانية تمت الموافقة عليها أمس."),
    Line("system", "Samantha", "English", -22, "Okay."),
    Line("microphone", "Majed", "Arabic", -48, "تمام."),
    Line("microphone", "Whisper", "English", -56, "I think we should delay the email campaign by two days."),
    Line("system", "Samantha", "English", -22, "That works for me. Can you send the updated timeline tonight?"),
    Line("microphone", "Daniel", "English", -57, "Yes, I will send it tonight."),
    Line("microphone", "Thomas", "French", -46, "Oui."),
    Line("system", "Majed", "Arabic", -22, "شكرا للجميع، نلتقي يوم الخميس."),
]
NOISE: Final = -72.0  # microphone room noise, dBFS
BLEED: Final = -40.0  # colleagues reach the microphone this many dB below their level on the call


def speak(line: Line) -> NDArray[np.float32]:
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "line.aiff"
        subprocess.run(["say", "-v", line.voice, "-o", str(path), line.text], check=True)
        audio, rate = sf.read(path, dtype="float32", always_2d=True)
    voice = resample_poly(audio.mean(axis=1), RATE, rate).astype(np.float32)
    active = voice[np.abs(voice) > 0.01 * np.max(np.abs(voice))]
    return (voice * (10 ** (line.level / 20) / (np.sqrt(np.mean(active**2)) + 1e-9))).astype(np.float32)


@app.command()
def make(folder: Path) -> None:
    """Write microphone.wav, system.caf and truth.json for the scripted meeting."""
    folder.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)
    clips = [speak(line) for line in SCRIPT]
    starts = np.cumsum([1.0] + [len(clip) / RATE + rng.uniform(0.8, 1.6) for clip in clips[:-1]])
    length = int((starts[-1] + len(clips[-1]) / RATE + 1.5) * RATE)
    tracks = {"microphone": np.zeros(length, np.float32), "system": np.zeros(length, np.float32)}
    tracks["microphone"] += (rng.normal(0, 1, length) * 10 ** (NOISE / 20)).astype(np.float32)
    truth = []
    for line, clip, start in zip(SCRIPT, clips, starts, strict=True):
        index = int(start * RATE)
        tracks[line.source][index : index + len(clip)] += clip
        if line.source == "system":
            tracks["microphone"][index : index + len(clip)] += clip * 10 ** (BLEED / 20)
        truth.append({"source": line.source, "start": float(start), "end": float(start + len(clip) / RATE), "language": line.language, "text": line.text, "level": line.level, "voice": line.voice})
    sf.write(folder / "microphone.wav", np.clip(tracks["microphone"], -1, 1), RATE, subtype="PCM_16")
    sf.write(folder / "system.caf", tracks["system"], RATE, format="CAF", subtype="FLOAT")
    (folder / "truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=1))
    typer.echo(f"{len(SCRIPT)} lines, {length / RATE:.0f} s, in {folder}")


def normalized(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(character for character in text if not unicodedata.combining(character))
    for variants, plain in (("أإآٱ", "ا"), ("ة", "ه"), ("ى", "ي")):
        for variant in variants:
            text = text.replace(variant, plain)
    return "".join(character for character in text if character.isalnum())


def error_rate(reference: str, hypothesis: str) -> float:
    """Character error rate (edit operations over reference length)."""
    reference, hypothesis = normalized(reference), normalized(hypothesis)
    matched = sum(block.size for block in SequenceMatcher(None, reference, hypothesis, autojunk=False).get_matching_blocks())
    return (max(len(reference), len(hypothesis)) - matched) / max(1, len(reference))


@app.command()
def score(folder: Path, transcript: str = "transcript.json") -> None:
    """Per-line error rate, language and speaker against truth.json, plus lines heard where nobody spoke."""
    truth = json.loads((folder / "truth.json").read_text())
    segments = json.loads((folder / transcript).read_text())["segments"]
    used: set[int] = set()
    rates: list[float] = []
    wrong_language = missed = 0
    for line in truth:
        hits = [index for index, segment in enumerate(segments) if segment["source"] == line["source"] and segment["start"] < line["end"] + 0.4 and segment["end"] > line["start"] - 0.4]
        used.update(hits)
        hypothesis = " ".join(segments[index]["text"] for index in hits)
        languages = {segments[index].get("language") for index in hits}
        rate = error_rate(line["text"], hypothesis)
        rates.append(rate)
        missed += not hits
        wrong_language += bool(hits) and languages != {line["language"]}
        flag = "MISSED" if not hits else "" if languages == {line["language"]} else f"LANG {sorted(map(str, languages))}"
        typer.echo(f"{line['source'][:3]} {line['level']:>4} {line['voice']:<8} cer {rate:4.2f} {flag:<14} {hypothesis[:70]}")
    extra = [segment for index, segment in enumerate(segments) if index not in used]
    for segment in extra:
        typer.echo(f"EXTRA {segment['source'][:3]} {segment['start']:6.1f} {segment.get('language')}: {segment['text'][:70]}")
    typer.echo(f"\nmean CER {np.mean(rates):.3f} · missed {missed}/{len(truth)} · wrong language {wrong_language} · extra lines {len(extra)}")


@app.command()
def replay(source: Path, destination: Path, speed: float = 4.0) -> None:
    """Rewrite a folder's tracks in timed blocks, like the recorder, then create .finish once they are closed."""
    destination.mkdir(parents=True, exist_ok=True)
    readers = {path.name: sf.SoundFile(path) for path in source.iterdir() if path.suffix in {".wav", ".caf"}}
    writers = {name: sf.SoundFile(destination / name, "w", reader.samplerate, reader.channels, format=reader.format, subtype=reader.subtype) for name, reader in readers.items()}
    block = RATE // 2
    while any(reader.tell() < reader.frames for reader in readers.values()):
        for name, reader in readers.items():
            writers[name].write(reader.read(block, dtype="float32"))
            writers[name].flush()
        time.sleep(0.5 / speed)
    for handle in [*readers.values(), *writers.values()]:
        handle.close()
    (destination / ".finish").touch()
    typer.echo("replay finished")


if __name__ == "__main__":
    app()
