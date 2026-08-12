"""Renders the two things needed to judge this before any .dm edit:

  compare_sheets.png -- every wall sheet side by side, aligned BY STATE NAME
                        (what actually matters at render time), so any layout
                        mismatch is visible directly.
  wall_preview.png   -- a real wall mass smoothed with the same corner logic
                        cardinal_smooth() uses, tinted #304463, original vs baked,
                        plus a mixed steel/dark-shuttle border.
"""

import struct
import zlib
from PIL import Image, ImageDraw

import os
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root, two levels up from scripts/turf/
TINT = (0x32, 0x40, 0x6B)      # current wall_colour #32406B
FLOOR = (58, 58, 62, 255)
SPACE = (10, 10, 18, 255)


def read_dmi(path):
    data = open(path, "rb").read()
    desc, i = None, 8
    while i < len(data):
        ln = struct.unpack(">I", data[i:i + 4])[0]
        ct, ch = data[i + 4:i + 8], data[i + 8:i + 8 + ln]
        if ct == b"zTXt":
            _k, r = ch.split(b"\x00", 1)
            desc = zlib.decompress(r[1:]).decode("utf8")
        elif ct == b"tEXt":
            _k, r = ch.split(b"\x00", 1)
            desc = r.decode("utf8")
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


def tint(im, colour=TINT):
    o = im.copy(); p = o.load()
    for y in range(o.height):
        for x in range(o.width):
            r, g, b, a = p[x, y]
            p[x, y] = (r * colour[0] // 255, g * colour[1] // 255, b * colour[2] // 255, a)
    return o


# ---------------------------------------------------------------- comparison
SHEETS = [
    ("composite_metal",       r"\icons\turf\smooth\composite_metal.dmi"),
    ("composite_reinf",       r"\icons\turf\smooth\composite_reinf.dmi"),
    ("composite_solid",       r"\icons\turf\smooth\composite_solid.dmi"),
    ("composite_solid_color", r"\icons\turf\smooth\composite_solid_color.dmi"),
    ("BAKED steel",           r"\icons\turf\smooth\composite_solid_color_rust.dmi"),
    ("shuttle_wall_dark",     r"\icons\turf\smooth\shuttle_wall_dark.dmi"),
    ("BAKED darkshuttle",     r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi"),
]
loaded = [(n, cells_by_name(REPO + p)) for n, p in SHEETS]

ROWS = ["1-i", "2-i", "3-i", "4-i", "1-n", "2-n", "3-s", "4-s",
        "1-w", "2-e", "3-w", "4-e", "1-nw", "2-ne", "3-sw", "4-se",
        "1-f", "2-f", "3-f", "4-f"]

Z, LBL, HDR = 5, 62, 20
cw = 32 * Z
W = LBL + len(loaded) * (cw + 8)
H = HDR + len(ROWS) * (cw + 4)
cmp_img = Image.new("RGB", (W, H), (24, 24, 28))
d = ImageDraw.Draw(cmp_img)
for j, (name, _) in enumerate(loaded):
    d.text((LBL + j * (cw + 8), 5), name[:22], fill=(230, 230, 120))
for i, st in enumerate(ROWS):
    y = HDR + i * (cw + 4)
    d.text((4, y + cw // 2 - 4), st, fill=(255, 255, 255))
    for j, (_n, cells) in enumerate(loaded):
        x = LBL + j * (cw + 8)
        if st in cells:
            bg = Image.new("RGBA", (32, 32), (255, 0, 255, 255))
            bg.alpha_composite(cells[st])
            cmp_img.paste(bg.convert("RGB").resize((cw, cw), Image.NEAREST), (x, y))
        else:
            d.rectangle([x, y, x + cw, y + cw], fill=(50, 20, 20))
            d.text((x + 6, y + cw // 2 - 4), "absent", fill=(255, 90, 90))
cmp_img.save("compare_sheets.png")
print("compare_sheets.png  (magenta = transparent; rows aligned by state name)")


# ------------------------------------------------------------- wall preview
def corner_states(N, S, E, W, NE, NW, SE, SW):
    nw = "1-f" if (N and W and NW) else ("1-nw" if (N and W) else ("1-n" if N else ("1-w" if W else "1-i")))
    ne = "2-f" if (N and E and NE) else ("2-ne" if (N and E) else ("2-n" if N else ("2-e" if E else "2-i")))
    sw = "3-f" if (S and W and SW) else ("3-sw" if (S and W) else ("3-s" if S else ("3-w" if W else "3-i")))
    se = "4-f" if (S and E and SE) else ("4-se" if (S and E) else ("4-s" if S else ("4-e" if E else "4-i")))
    return nw, ne, sw, se


# '#' = steel wall, 'D' = dark shuttle wall (so the shared border is visible),
# '.' = open. Includes a solid mass, a corridor, a notch and an isolated pillar.
MAP = [
    "..............",
    ".####....DD...",
    ".######..DD...",
    ".######..DD...",
    ".##..##..DD...",
    ".##..###DDDD..",
    ".##..###DDDD..",
    ".########.....",
    ".########..#..",
    "..............",
]
GH, GW = len(MAP), len(MAP[0])


def render(steel_cells, dark_cells, zoom, ground, wear):
    img = Image.new("RGBA", (GW * 32, GH * 32), ground)
    for gy in range(GH):
        for gx in range(GW):
            here = MAP[gy][gx]
            if here == ".":
                continue

            def w(dx, dy):
                nx, ny = gx + dx, gy + dy
                return 0 <= nx < GW and 0 <= ny < GH and MAP[ny][nx] != "."
            nw, ne, sw, se = corner_states(w(0, -1), w(0, 1), w(1, 0), w(-1, 0),
                                           w(1, -1), w(-1, -1), w(1, 1), w(-1, 1))
            cells = dark_cells if here == "D" else steel_cells
            for st in (nw, ne, sw, se):
                if st in cells:
                    img.alpha_composite(tint(cells[st]), (gx * 32, gy * 32))
    return img.convert("RGB").resize((GW * 32 * zoom, GH * 32 * zoom), Image.NEAREST)


steel_o = cells_by_name(REPO + r"\icons\turf\smooth\composite_solid_color.dmi")
steel_r = cells_by_name(REPO + r"\icons\turf\smooth\composite_solid_color_rust.dmi")
dark_o = cells_by_name(REPO + r"\icons\turf\smooth\shuttle_wall_dark.dmi")
dark_r = cells_by_name(REPO + r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi")

panels = [("#304463, NO wear", steel_o, dark_o), ("#304463 + BAKED wear", steel_r, dark_r)]
z1, z4 = 1, 4
w1, h1 = GW * 32 * z1, GH * 32 * z1
w4, h4 = GW * 32 * z4, GH * 32 * z4
out = Image.new("RGB", (max(w4 * 2 + 30, 600), 24 + h4 + 24 + h1 + 20), (24, 24, 28))
dd = ImageDraw.Draw(out)
for i, (label, sc, dc) in enumerate(panels):
    dd.text((10 + i * (w4 + 20), 6), f"{label}  --  4x", fill=(230, 230, 120))
    out.paste(render(sc, dc, z4, FLOOR, i == 1), (10 + i * (w4 + 20), 22))
    dd.text((10 + i * (w1 + 20), 30 + h4), f"{label}  --  1x (actual size)", fill=(230, 230, 120))
    out.paste(render(sc, dc, z1, SPACE, i == 1), (10 + i * (w1 + 20), 46 + h4))
out.save("wall_preview.png")
print("wall_preview.png    (left = colour only, right = colour + wear; steel mass + dark-shuttle block)")
