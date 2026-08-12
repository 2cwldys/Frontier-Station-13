"""
Converts plain (non-reverb, non-announcer) ship sound effects from
user-provided source recordings in D:\\Downloads straight to Vorbis OGG --
no reverb, no resampling, no fade processing. Sibling to
build_bookended_lines.py, which handles the announcer voice-line pipeline
(reverb + duration manifest) -- these are one-shot sound effects played
directly via sound(), not queued through play_announcer_sound(), so none
of that machinery applies here.

Requires ffmpeg on PATH.
"""

import pathlib
import subprocess

SOURCE_DIR = pathlib.Path(r"D:\Downloads")
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
# Matches the existing ship-combat sfx convention (e.g. locked_on.ogg).
OUTPUT_DIR = REPO_ROOT / "sound" / "effects" / "ship_weapons"

LINES = [
    "shields_struck_1",
    "shields_struck_2",
    "shields_powered_on_vfx",
    "shields_powered_off_vfx",
]


def encode_ogg(src: pathlib.Path, dst: pathlib.Path) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "10", str(dst)],
        check=True, capture_output=True,
    )


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for name in LINES:
        src_mp3 = SOURCE_DIR / f"{name}.mp3"
        if not src_mp3.exists():
            raise SystemExit(f"Missing source recording: {src_mp3}")

        final_ogg = OUTPUT_DIR / f"{name}.ogg"
        print(f"Processing: {name}")
        encode_ogg(src_mp3, final_ogg)
        print(f"  wrote {final_ogg}")

    print("Done.")


if __name__ == "__main__":
    main()
