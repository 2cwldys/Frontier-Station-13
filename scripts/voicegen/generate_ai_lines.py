"""
One-time offline generator for new AI announcement voice lines (autosave in
progress, zone security tier changes).

This is an interim substitute for the documented ElevenLabs "Rachel" +
Audacity pipeline in sound/AI/Voice how-to.txt, which every other AI line in
the game was built with. It uses pyttsx3 (local SAPI5 voice on Windows) for
synthesis and approximates the same reverb chain with the `pedalboard`
library, since pedalboard's Reverb is a simpler Freeverb port with no
separate Room Size/Reverberance, Pre-delay, or Tone controls -- the mapping
below is best-effort, not a sample-accurate match. Replace these files with a
real Rachel/ElevenLabs pass when one is available.

Requires: pip install pyttsx3 pedalboard
Also requires ffmpeg on PATH.
"""

import pathlib
import subprocess
import tempfile

import pyttsx3
from pedalboard import Pedalboard, Reverb
from pedalboard.io import AudioFile

OUTPUT_DIR = pathlib.Path(__file__).resolve().parents[2] / "sound" / "AI" / "announcements"
TARGET_SAMPLE_RATE = 16000

LINES = {
    "autosave_in_progress": "AUTOSAVE IN PROGRESS.",
    "zone_highsec": "ENTERING HIGHSEC ZONE.",
    "zone_medsec": "ENTERING MEDSEC ZONE.",
    "zone_nullsec": "ENTERING NULLSEC ZONE.",
}

# Approximates sound/AI/Voice how-to.txt's Audacity chain (Room Size 40,
# Pre-delay 48, Reverberance 70, Damping 57, Tone Low 84, Tone High 85, Wet
# Gain 3dB, Dry Gain -3dB, Stereo Width 32%, Wet Only: no).
REVERB = Reverb(
    room_size=0.70,   # closest analog to Audacity's Reverberance (70)
    damping=0.57,     # Damping (57)
    wet_level=0.33,   # Wet Gain +3dB, blended (not Wet Only)
    dry_level=0.70,   # Dry Gain -3dB
    width=0.32,       # Stereo Width (32%)
)


def synth_to_wav(text: str, wav_path: pathlib.Path) -> None:
    engine = pyttsx3.init()
    engine.save_to_file(text, str(wav_path))
    engine.runAndWait()
    engine.stop()


def resample(src: pathlib.Path, dst: pathlib.Path, rate: int) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-ac", "1", "-ar", str(rate), str(dst)],
        check=True, capture_output=True,
    )


def apply_reverb(src: pathlib.Path, dst: pathlib.Path) -> None:
    board = Pedalboard([REVERB])
    with AudioFile(str(src)) as f:
        audio = f.read(f.frames)
        samplerate = f.samplerate
    processed = board(audio, samplerate)
    with AudioFile(str(dst), "w", samplerate, processed.shape[0]) as f:
        f.write(processed)


def encode_ogg(src: pathlib.Path, dst: pathlib.Path) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "10", str(dst)],
        check=True, capture_output=True,
    )


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = pathlib.Path(tmp)
        for name, text in LINES.items():
            raw_wav = tmp_dir / f"{name}_raw.wav"
            resampled_wav = tmp_dir / f"{name}_resampled.wav"
            reverb_wav = tmp_dir / f"{name}_reverb.wav"
            final_ogg = OUTPUT_DIR / f"{name}.ogg"

            print(f"Synthesizing: {name} -> \"{text}\"")
            synth_to_wav(text, raw_wav)
            resample(raw_wav, resampled_wav, TARGET_SAMPLE_RATE)
            apply_reverb(resampled_wav, reverb_wav)
            encode_ogg(reverb_wav, final_ogg)
            print(f"  wrote {final_ogg}")

    print("Done.")


if __name__ == "__main__":
    main()
