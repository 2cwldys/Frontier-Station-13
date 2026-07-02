"""
Recolor Aurora-Persistence HUD icons.

screen/dark.dmi    : orange → blue  (R↔B channel swap)  [already done, kept for reference]
screen/silver.dmi  : orange → silver/white, preserve green (health OK) and red (danger)
puppet_new.dmi     : body → silver/white (desaturate + brighten)
"""

import struct
import zlib
import io
import shutil
from pathlib import Path
from PIL import Image

AURORA = Path(r"D:\GIT Storage\Aurora-Persistence\icons\hud\mob")


def read_png_chunks(data: bytes):
    sig = data[:8]
    assert sig == b'\x89PNG\r\n\x1a\n', "Not a PNG"
    chunks, pos = [], 8
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos+4])[0]
        ctype = data[pos+4:pos+8]
        cdata = data[pos+8:pos+8+length]
        pos += 12 + length
        chunks.append((ctype, cdata))
    return sig, chunks


def write_png_chunks(sig, chunks):
    out = bytearray(sig)
    for ctype, cdata in chunks:
        out += struct.pack('>I', len(cdata))
        out += ctype + cdata
        out += struct.pack('>I', zlib.crc32(ctype + cdata) & 0xFFFFFFFF)
    return bytes(out)


def save_recolored(src_path: Path, dst_path: Path, result_img: Image.Image):
    """Save recolored image while preserving DMI metadata chunks."""
    raw = src_path.read_bytes()
    sig, chunks = read_png_chunks(raw)
    byond_chunks = [(t, d) for t, d in chunks if t in (b'zTXt', b'tEXt') and b'Description' in d]

    buf = io.BytesIO()
    result_img.save(buf, format='PNG', optimize=False)
    buf.seek(0)
    new_sig, new_chunks = read_png_chunks(buf.read())

    ihdr = [(t, d) for t, d in new_chunks if t == b'IHDR']
    iend = [(t, d) for t, d in new_chunks if t == b'IEND']
    img_data = [(t, d) for t, d in new_chunks if t not in (b'IHDR', b'IEND')]

    dst_path.write_bytes(write_png_chunks(new_sig, ihdr + byond_chunks + img_data + iend))
    print(f"  -> {dst_path}")


def frame_grayscale_recolor(src_path: Path, dst_path: Path):
    """
    Keep blue/cool pixels (already converted by R<->B swap), convert warm/neutral
    frame pixels to grayscale. This removes the orange frame tint while keeping
    the blue indicator icons inside slots intact.
    """
    img = Image.open(src_path).convert('RGBA')
    pixels = img.load()
    w, h = img.size
    result = Image.new('RGBA', (w, h))
    out = result.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                out[x, y] = (0, 0, 0, 0)
            elif b > r + 30:  # clearly blue pixel — keep as-is
                out[x, y] = (r, g, b, a)
            else:             # warm/neutral frame pixel — convert to grayscale
                lum = int(0.299 * r + 0.587 * g + 0.114 * b)
                out[x, y] = (lum, lum, lum, a)
    save_recolored(src_path, dst_path, result)


def blue_recolor(src_path: Path, dst_path: Path):
    """R↔B swap: orange→blue, white stays white, green stays green."""
    img = Image.open(src_path).convert('RGBA')
    r, g, b, a = img.split()
    result = Image.merge('RGBA', (b, g, r, a))
    save_recolored(src_path, dst_path, result)


def silver_recolor(src_path: Path, dst_path: Path):
    """
    Convert orange/amber → metallic silver/white.
    Preserves:
      - Green pixels (health OK indicators, vitals green states) → kept green
      - High-saturation red pixels (danger/warning states) → kept red
    Everything else → desaturated bright silver with a slight cool tint.
    """
    img = Image.open(src_path).convert('RGBA')
    pixels = img.load()
    w, h = img.size
    result = Image.new('RGBA', (w, h))
    out_px = result.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                out_px[x, y] = (0, 0, 0, 0)
                continue

            # Classify pixel by dominant channel
            max_c = max(r, g, b)
            if max_c == 0:
                out_px[x, y] = (r, g, b, a)
                continue

            # NOTE: Green pixels (health figure, etc.) are NOT preserved —
            # user wants the health figure blue, so green → silver like everything else.

            # Preserve clearly RED pixels (danger/warning indicators)
            red_dominance = r / max_c if max_c > 0 else 0
            saturation = (max_c - min(r, g, b)) / max_c if max_c > 0 else 0
            if r > 120 and red_dominance > 0.60 and saturation > 0.45 and r > g * 1.5:
                out_px[x, y] = (r, g, b, a)
                continue

            # Everything else → cool silver/white
            lum = int(0.299*r + 0.587*g + 0.114*b)
            # Boost toward white
            bright = min(255, int(lum * 1.5 + 55))
            # Cool metallic tint: very slightly blue-white
            sr = int(bright * 0.88)
            sg = int(bright * 0.93)
            sb = bright
            out_px[x, y] = (min(255, sr), min(255, sg), min(255, sb), a)

    save_recolored(src_path, dst_path, result)


if __name__ == '__main__':
    # ── screen/dark.dmi ──────────────────────────────────────────────────────
    orig_dark   = AURORA / 'screen' / 'dark_original.dmi'
    blue_dark   = AURORA / 'screen' / 'dark.dmi'
    silver_dark = AURORA / 'screen' / 'silver.dmi'

    if not orig_dark.exists():
        # First run — save original before blue recolor
        shutil.copy2(blue_dark, orig_dark)
        print(f"Backed up: {orig_dark}")

    print("Creating blue screen/dark.dmi ...")
    blue_recolor(orig_dark, blue_dark)

    print("Applying frame grayscale to screen/dark.dmi (keeps blue icons, grays frames) ...")
    frame_grayscale_recolor(blue_dark, blue_dark)

    print("Creating silver screen/silver.dmi ...")
    silver_recolor(orig_dark, silver_dark)

    # ── puppet_new.dmi ────────────────────────────────────────────────────────
    orig_puppet   = AURORA / 'puppet_new_original.dmi'
    silver_puppet = AURORA / 'puppet_new.dmi'

    if not orig_puppet.exists():
        shutil.copy2(silver_puppet, orig_puppet)
        print(f"Backed up: {orig_puppet}")

    print("Creating blue puppet_new.dmi (R<->B swap to match UI) ...")
    blue_recolor(orig_puppet, silver_puppet)

    # ── generic.dmi → blue gun mode buttons ───────────────────────────────────
    gen_orig = AURORA / 'generic_original.dmi'
    gen_dst  = AURORA / 'generic.dmi'

    if not gen_orig.exists():
        shutil.copy2(gen_dst, gen_orig)
        print(f"Backed up: {gen_orig}")

    print("Creating blue generic.dmi (gun mode buttons blue) ...")
    blue_recolor(gen_orig, gen_dst)

    print("\nDone.")
    print("  screen/dark.dmi   = blue UI buttons")
    print("  screen/silver.dmi = silver status icons")
    print("  puppet_new.dmi    = blue character doll")
    print("  generic.dmi       = blue gun mode buttons")
