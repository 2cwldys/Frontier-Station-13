"""
Boosts the alpha channel of the FOV cone's "combat" state (icons/mob/hide.dmi),
used by /atom/movable/screen/fov (vision_cone.dm) to darken the area behind a
player's facing.

Measured directly: the state averages alpha 22/255, maxing at 89/255 -- under
35% opacity even at its darkest point. fov.alpha is already 255 (fully "on")
in code (show_cone()), so that ceiling is baked into the art itself; no code-
side alpha/color change can push past it.

Fix: a straight per-pixel alpha SCALE (multiply, clamp at 255) on just this one
state -- preserves the exact silhouette/vignette shape (every pixel keeps its
relative darkness), just makes the whole thing more opaque. RGB is left alone
(already pure black in the source, and /atom/movable/screen/fov tints with
color = "#000000" regardless, so RGB is inert here).

Writes a NEW minimal single-state, multi-frame .dmi (hide.dmi has ~200 states
belonging to other screen objects -- fov_mask, fov_mask_two, behind_ping, etc.
-- editing the whole sheet would affect all of them). Only
/atom/movable/screen/fov's own icon path changes to point at it.
"""

import io
import os
import struct
import zlib
from PIL import Image, PngImagePlugin

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

STATE_NAME = "combat"
ALPHA_SCALE = 2.0  # 89 -> 178 (no clamping, keeps the gradient smooth), 22.2 avg -> ~44 avg


def read_dmi(path):
    data = open(path, "rb").read()
    desc = None
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        ctype = data[i + 4:i + 8]
        chunk = data[i + 8:i + 8 + length]
        if ctype == b"zTXt":
            _k, rest = chunk.split(b"\x00", 1)
            desc = zlib.decompress(rest[1:]).decode("utf8")
        elif ctype == b"tEXt":
            _k, rest = chunk.split(b"\x00", 1)
            desc = rest.decode("utf8")
        i += 12 + length
    return desc, Image.open(path).convert("RGBA")


def parse_states(desc):
    cell_w = cell_h = 32
    states, cur, dirs, frames, delay = [], None, 1, 1, None
    for line in desc.splitlines():
        s = line.strip()
        if s.startswith("width ="):
            cell_w = int(s.split("=")[1])
        elif s.startswith("height ="):
            cell_h = int(s.split("=")[1])
        elif s.startswith("state ="):
            if cur is not None:
                states.append((cur, dirs, frames, delay))
            cur = s.split("=", 1)[1].strip().strip('"')
            dirs, frames, delay = 1, 1, None
        elif s.startswith("dirs ="):
            dirs = int(s.split("=")[1])
        elif s.startswith("frames ="):
            frames = int(s.split("=")[1])
        elif s.startswith("delay ="):
            delay = s.split("=", 1)[1].strip()
    if cur is not None:
        states.append((cur, dirs, frames, delay))
    return cell_w, cell_h, states


def locate_state(states, name):
    index = 0
    for state_name, dirs, frames, delay in states:
        count = dirs * frames
        if state_name == name:
            return index, dirs, frames, delay
        index += count
    raise ValueError(f"state {name!r} not found")


def boost_alpha_state(src_path, state_name, scale, out_path):
    desc, src = read_dmi(src_path)
    cell_w, cell_h, states = parse_states(desc)
    cols = src.width // cell_w

    start_index, dirs, frames, delay = locate_state(states, state_name)
    count = dirs * frames
    sp = src.load()

    sheet = Image.new("RGBA", (cell_w * count, cell_h))
    out = sheet.load()

    before_alphas = []
    after_alphas = []
    for n in range(count):
        idx = start_index + n
        col, row = idx % cols, idx // cols
        ox, oy = col * cell_w, row * cell_h
        for y in range(cell_h):
            for x in range(cell_w):
                r, g, b, a = sp[ox + x, oy + y]
                before_alphas.append(a)
                new_a = min(255, round(a * scale))
                after_alphas.append(new_a)
                out[n * cell_w + x, y] = (r, g, b, new_a)

    print(f"  {state_name!r}: {count} frame(s), {cell_w}x{cell_h} each")
    print(f"    alpha before: avg={sum(before_alphas)/len(before_alphas):.1f} "
          f"max={max(before_alphas)}")
    print(f"    alpha after:  avg={sum(after_alphas)/len(after_alphas):.1f} "
          f"max={max(after_alphas)}")

    # dirs/frames must match the SOURCE exactly, not be assumed -- 'combat' is
    # dirs=4/frames=1 (one cell per facing), not an animation. Declaring the
    # wrong shape here would make BYOND misread which cells belong to which
    # direction, or silently only use the first one for every facing.
    single_desc = (
        f'# BEGIN DMI\nversion = 4.0\n\twidth = {cell_w}\n\theight = {cell_h}\n'
        f'state = "{state_name}"\n\tdirs = {dirs}\n\tframes = {frames}\n'
    )
    if delay:
        single_desc += f'\tdelay = {delay}\n'
    single_desc += '# END DMI\n'

    meta = PngImagePlugin.PngInfo()
    meta.add_text("Description", single_desc, zip=True)
    sheet.save(out_path, format="PNG", pnginfo=meta)
    print(f"  wrote {out_path}")


def verify_chunk_order(out_path):
    data = open(out_path, "rb").read()
    order, i = [], 8
    while i < len(data):
        ln = struct.unpack(">I", data[i:i + 4])[0]
        order.append(data[i + 4:i + 8].decode("ascii", "replace"))
        i += 12 + ln
    text_at = next((n for n, c in enumerate(order) if c in ("zTXt", "tEXt")), None)
    idat_at = next((n for n, c in enumerate(order) if c == "IDAT"), None)
    ok = text_at is not None and idat_at is not None and text_at < idat_at
    print(f"  chunk order: {' -> '.join(order)}")
    print(f"  metadata precedes IDAT: {'YES' if ok else '*** NO -- BYOND WILL IGNORE IT ***'}")
    return ok


def verify_silhouette_preserved(src_path, state_name, out_path):
    """Every pixel that was transparent before must still be transparent after,
    and every pixel that was opaque before must still be opaque after -- a pure
    scale must never change WHERE the cone shape is, only how solid it looks."""
    desc, src = read_dmi(src_path)
    cell_w, cell_h, states = parse_states(desc)
    cols = src.width // cell_w
    start_index, dirs, frames, _delay = locate_state(states, state_name)
    count = dirs * frames
    sp = src.load()

    _d, out_img = read_dmi(out_path)
    op = out_img.load()

    mismatches = 0
    for n in range(count):
        idx = start_index + n
        col, row = idx % cols, idx // cols
        ox, oy = col * cell_w, row * cell_h
        for y in range(cell_h):
            for x in range(cell_w):
                before_zero = sp[ox + x, oy + y][3] == 0
                after_zero = op[n * cell_w + x, y][3] == 0
                if before_zero != after_zero:
                    mismatches += 1
    print(f"  silhouette check: {mismatches} pixel(s) changed transparent<->opaque")
    return mismatches


print("=== FOV cone 'combat' state -- alpha boost ===")
src_path = REPO + r"\icons\mob\hide.dmi"
out_path = REPO + r"\icons\mob\hide_fov_darker.dmi"
boost_alpha_state(src_path, STATE_NAME, ALPHA_SCALE, out_path)
ok1 = verify_chunk_order(out_path)
mism = verify_silhouette_preserved(src_path, STATE_NAME, out_path)
print("\nRESULT:", "SAFE TO SHIP" if (ok1 and mism == 0) else "*** DO NOT SHIP ***")
