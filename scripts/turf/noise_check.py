"""Judges the wear the way it actually appears in game: a LARGE wall mass at
real size, tinted #304463, then multiplied by a coloured light -- which is what
exaggerated the noise in the reported screenshot. Colour-only vs baked."""

import struct
import zlib
from PIL import Image, ImageDraw

import os
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root, two levels up from scripts/turf/
TINT = (0x32, 0x40, 0x6B)      # current wall_colour #32406B
LIGHT = (0.45, 1.00, 0.85)   # green/teal cast, like the screenshot


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


def shade(im):
    o = im.copy(); p = o.load()
    for y in range(o.height):
        for x in range(o.width):
            r, g, b, a = p[x, y]
            r = int(r * TINT[0] // 255 * LIGHT[0])
            g = int(g * TINT[1] // 255 * LIGHT[1])
            b = int(b * TINT[2] // 255 * LIGHT[2])
            p[x, y] = (r, g, b, a)
    return o


def corner_states(N, S, E, W, NE, NW, SE, SW):
    nw = "1-f" if (N and W and NW) else ("1-nw" if (N and W) else ("1-n" if N else ("1-w" if W else "1-i")))
    ne = "2-f" if (N and E and NE) else ("2-ne" if (N and E) else ("2-n" if N else ("2-e" if E else "2-i")))
    sw = "3-f" if (S and W and SW) else ("3-sw" if (S and W) else ("3-s" if S else ("3-w" if W else "3-i")))
    se = "4-f" if (S and E and SE) else ("4-se" if (S and E) else ("4-s" if S else ("4-e" if E else "4-i")))
    return nw, ne, sw, se


GW, GH = 22, 14   # a big solid hull mass -- worst case for both noise and tiling


def render(cells, zoom):
    img = Image.new("RGBA", (GW * 32, GH * 32), (10, 10, 14, 255))
    for gy in range(GH):
        for gx in range(GW):
            def w(dx, dy):
                nx, ny = gx + dx, gy + dy
                return 0 <= nx < GW and 0 <= ny < GH
            nw, ne, sw, se = corner_states(w(0, -1), w(0, 1), w(1, 0), w(-1, 0),
                                           w(1, -1), w(-1, -1), w(1, 1), w(-1, 1))
            for st in (nw, ne, sw, se):
                if st in cells:
                    img.alpha_composite(shade(cells[st]), (gx * 32, gy * 32))
    return img.convert("RGB").resize((GW * 32 * zoom, GH * 32 * zoom), Image.NEAREST)


orig = cells_by_name(REPO + r"\icons\turf\smooth\composite_solid_color.dmi")
rust = cells_by_name(REPO + r"\icons\turf\smooth\composite_solid_color_rust.dmi")

W1, H1 = GW * 32, GH * 32
out = Image.new("RGB", (W1 * 2 + 30, H1 + 34), (24, 24, 28))
d = ImageDraw.Draw(out)
d.text((10, 6), "colour only, NO wear -- 1x actual size", fill=(230, 230, 120))
out.paste(render(orig, 1), (10, 22))
d.text((W1 + 20, 6), "with BAKED wear -- 1x actual size", fill=(230, 230, 120))
out.paste(render(rust, 1), (W1 + 20, 22))
out.save("noise_check.png")
print("noise_check.png  -- 22x14 solid wall mass, #304463 under a green light, 1x")
