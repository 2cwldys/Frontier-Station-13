"""Renders a large wall mass using the SAME per-turf variant hash wall_icon.dm
uses, so the preview actually reflects what a mixed-variant hull looks like --
not just one field repeated."""

import os
import struct
import zlib
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TINT = (0x32, 0x40, 0x6B)  # current wall_colour


def read_dmi(path):
    data = open(path, "rb").read()
    desc, i = None, 8
    while i < len(data):
        ln = struct.unpack(">I", data[i:i + 4])[0]
        ct, ch = data[i + 4:i + 8], data[i + 8:i + 8 + ln]
        if ct == b"zTXt":
            _k, r = ch.split(b"\x00", 1)
            desc = zlib.decompress(r[1:]).decode("utf8")
        i += 12 + ln
    return desc, Image.open(path).convert("RGBA")


def cells_by_name(path):
    desc, img = read_dmi(path)
    cw = ch = 32
    states, cur, d, f = [], None, 1, 1
    for line in desc.splitlines():
        s = line.strip()
        if s.startswith("width ="): cw = int(s.split("=")[1])
        elif s.startswith("height ="): ch = int(s.split("=")[1])
        elif s.startswith("state ="):
            if cur is not None: states.append((cur, d * f))
            cur = s.split("=", 1)[1].strip().strip('"'); d = f = 1
        elif s.startswith("dirs ="): d = int(s.split("=")[1])
        elif s.startswith("frames ="): f = int(s.split("=")[1])
    if cur is not None: states.append((cur, d * f))
    cols = img.width // cw
    out, idx = {}, 0
    for name, cnt in states:
        for _ in range(cnt):
            c, r = idx % cols, idx // cols
            out.setdefault(name, img.crop((c * cw, r * ch, c * cw + cw, r * ch + ch)))
            idx += 1
    return out


def tint(im):
    o = im.copy(); p = o.load()
    for y in range(o.height):
        for x in range(o.width):
            r, g, b, a = p[x, y]
            p[x, y] = (r * TINT[0] // 255, g * TINT[1] // 255, b * TINT[2] // 255, a)
    return o


def corner_states(N, S, E, W, NE, NW, SE, SW):
    nw = "1-f" if (N and W and NW) else ("1-nw" if (N and W) else ("1-n" if N else ("1-w" if W else "1-i")))
    ne = "2-f" if (N and E and NE) else ("2-ne" if (N and E) else ("2-n" if N else ("2-e" if E else "2-i")))
    sw = "3-f" if (S and W and SW) else ("3-sw" if (S and W) else ("3-s" if S else ("3-w" if W else "3-i")))
    se = "4-f" if (S and E and SE) else ("4-se" if (S and E) else ("4-s" if S else ("4-e" if E else "4-i")))
    return nw, ne, sw, se


# Mirrors wall_icon.dm's DM code exactly: small multipliers (stay well under
# float32's 2**24 exact-integer range) then an xor-shift mix, masked to 32-bit
# signed to match BYOND's bitwise-op semantics, then abs() % N.
def _i32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def variant_index(x, y, z, n):
    h = _i32(x * 12 + y * 197 + z * 51)
    h = _i32(h ^ _i32(h << 5))
    h = _i32(h ^ (h >> 3))
    return abs(h) % n


VARIANTS = [cells_by_name(REPO + rf"\icons\turf\smooth\composite_solid_color_rust_{n}.dmi") for n in range(1, 5)]
VARIANTS.append(cells_by_name(REPO + r"\icons\turf\smooth\composite_solid_color.dmi"))  # clean, matches materials.dm's 5th entry

GW, GH = 30, 18  # big enough to show many repeats of any residual pattern
Z = 45  # SS13's real default zoom is far below 1 screen tile = 32px; use 1x


def render():
    img = Image.new("RGBA", (GW * 32, GH * 32), (10, 10, 14, 255))
    for gy in range(GH):
        for gx in range(GW):
            def w(dx, dy):
                nx, ny = gx + dx, gy + dy
                return 0 <= nx < GW and 0 <= ny < GH
            nw, ne, sw, se = corner_states(w(0, -1), w(0, 1), w(1, 0), w(-1, 0),
                                           w(1, -1), w(-1, -1), w(1, 1), w(-1, 1))
            cells = VARIANTS[variant_index(gx, gy, 1, len(VARIANTS))]
            for st in (nw, ne, sw, se):
                if st in cells:
                    img.alpha_composite(tint(cells[st]), (gx * 32, gy * 32))
    return img.convert("RGB")


render().save("variant_check.png")
print("variant_check.png -- 30x18 solid mass, per-turf variant picked via the same hash wall_icon.dm uses")
