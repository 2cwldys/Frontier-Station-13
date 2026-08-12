"""
Bakes a wear/grime pass into a COPY of a wall sheet.

Why baked rather than overlaid: /material/New() already blends the colour tint
straight into its own copy of the sheet (materials.dm:211-214). Wear belongs in
the same place. Multiplying a fully-opaque greyscale field leaves
base.alpha x 255 = base.alpha, so the alpha channel is preserved byte for byte
and it is structurally impossible to draw outside the artwork.

Why ONE coherent field: the four corner states of a tile are one picture. In the
solid-family sheets the split is 8/24, not 16/16 -- '1-i' is a 16x8 strip and
'3-i' is a 16x24 block. Generating noise per cell puts unrelated patterns either
side of the x=16 and y=8 seams, which is exactly the "sprites don't line up"
artefact. Here a single 32x32 field is sampled by every cell at its own local
(x, y), so any four quadrants reassemble into the same continuous pattern.

The field necessarily repeats on every tile -- a state has one appearance. That
is why it is kept fine-grained and shallow: fine grain reads as surface grime,
where large blobs would read as an obvious repeating stamp.
"""

import io
import math
import struct
import zlib
import random
from PIL import Image, PngImagePlugin

import os
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root, two levels up from scripts/turf/

# The main knob: the fraction of brightness the wear removes at full field
# value. 1.00 drives the deepest wear to pure black. 0.49 keeps real contrast
# without crushing the darkest patches flat.
WEAR_STRENGTH = 0.49

# Per-channel multipliers on that strength. Taking less out of red and more out
# of blue shifts worn pixels warm, so they read as rust rather than as grey
# dirt. Set all three to 1.0 for a purely neutral darkening.
CHANNEL_BIAS = (1.00, 1.00, 1.00)  # R, G, B -- neutral: wear darkens toward black


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
    states, cur, dirs, frames = [], None, 1, 1
    for line in desc.splitlines():
        s = line.strip()
        if s.startswith("width ="):
            cell_w = int(s.split("=")[1])
        elif s.startswith("height ="):
            cell_h = int(s.split("=")[1])
        elif s.startswith("state ="):
            if cur is not None:
                states.append((cur, dirs * frames))
            cur = s.split("=", 1)[1].strip().strip('"')
            dirs = frames = 1
        elif s.startswith("dirs ="):
            dirs = int(s.split("=")[1])
        elif s.startswith("frames ="):
            frames = int(s.split("=")[1])
    if cur is not None:
        states.append((cur, dirs * frames))
    return cell_w, cell_h, states


def coherent_field(w, h, seed):
    """One 32x32 wear field, values 0.0 (clean) .. 1.0 (max wear).

    A single static field is necessarily identical everywhere it's used --
    that's the nature of a baked sprite sheet, not something a filter pass can
    get around. What IS achievable within that constraint, and what this does:

    1. Each "patch" is a small CLUSTER of 2-4 overlapping circles at jittered
       offsets, rather than one circle. This deliberately avoids any single
       shape with rotational symmetry -- an earlier version tried bending one
       circle's radius with sine harmonics, and at this pixel count that
       produced a very recognizable flower/star silhouette, which repeated
       even more obviously than a plain circle. Overlapping offset circles
       have no symmetry to lock onto, so they read as an irregular smudge.
    2. Three separate size classes (few-large / some-medium / many-small)
       layered together, at DIFFERENT depths, instead of one uniform blob
       size -- so the field has real regional contrast: some areas end up
       nearly clean, others heavily worn. Since each corner state (1-i, 3-s,
       etc.) samples a different fixed region of this same 32x32 field, that
       regional contrast is what gives different wall faces visibly different
       wear -- the closest a static sheet can get to "not every wall looks
       equally worn," short of a genuinely different, per-turf mechanism.

    Wraps toroidally on both axes so tiles placed next to each other never
    show a seam where one tile's field meets the next.
    """
    rng = random.Random(seed)
    f = [[0.0] * w for _ in range(h)]

    # (cluster count, sub-circle radius range, depth range, sub-circles per cluster, offset spread)
    PATCH_LAYERS = [
        (3, (4.5, 7.5), (0.55, 0.95), (3, 4), 0.65),   # few large clusters, strong stains
        (6, (2.5, 4.5), (0.40, 0.75), (2, 3), 0.60),   # medium clusters
        (11, (1.0, 2.2), (0.30, 0.60), (2, 3), 0.55),  # many small clusters, roughest edges
    ]
    for cluster_count, (rmin, rmax), (dmin, dmax), (nmin, nmax), spread in PATCH_LAYERS:
        for _ in range(cluster_count):
            ccx, ccy = rng.randrange(w), rng.randrange(h)
            depth = rng.uniform(dmin, dmax)
            n_circles = rng.randint(nmin, nmax)
            for _ in range(n_circles):
                base_r = rng.uniform(rmin, rmax)
                # Offset within `spread` radii of the cluster centre -- close
                # enough that the circles overlap into one connected shape,
                # far enough that the union isn't just a bigger circle.
                off_r = rng.uniform(0, base_r * spread)
                off_a = rng.uniform(0, 2 * math.pi)
                cx = ccx + off_r * math.cos(off_a)
                cy = ccy + off_r * math.sin(off_a)
                r = base_r * rng.uniform(0.7, 1.0)
                span = int(math.ceil(r)) + 2
                icx, icy = int(round(cx)), int(round(cy))
                for dy in range(-span, span + 1):
                    y = (icy + dy) % h
                    for dx in range(-span, span + 1):
                        x = (icx + dx) % w
                        ddx = (icx + dx) - cx
                        ddy = (icy + dy) - cy
                        d = (ddx * ddx + ddy * ddy) ** 0.5
                        if d < r:
                            fall = 1.0 - d / r
                            f[y][x] = min(1.0, f[y][x] + depth * fall * fall)

    # Vertical run-off streaks, wrapped vertically. Gives the staining a
    # direction so it looks like corrosion running down a panel rather than
    # random blotching. Widened slightly (occasional 2px-wide step) so streaks
    # don't all read as identical hairlines.
    for _ in range(11):
        x = rng.randrange(w)
        y = rng.randrange(h)
        length = rng.randint(4, 16)
        depth = rng.uniform(0.40, 0.80)
        wide = rng.random() < 0.35
        for step in range(length):
            yy = (y + step) % h
            if rng.random() < 0.3:
                x = (x + rng.choice((-1, 1))) % w
            fade = 1.0 - (step / length)
            f[yy][x] = min(1.0, f[yy][x] + depth * fade)
            if wide:
                f[yy][(x + 1) % w] = min(1.0, f[yy][(x + 1) % w] + depth * fade * 0.5)

    # Sparse pitting. Density is the single most dangerous number in this file:
    # at 0.30 roughly a third of every pixel in every tile gets a pit, which
    # stops reading as weathering and becomes dither noise -- tiled across a
    # whole hull it looks like static, especially under coloured lighting.
    # Kept at 0.06, and shallow, so it reads as surface grain.
    for _ in range(int(w * h * 0.06)):
        x, y = rng.randrange(w), rng.randrange(h)
        f[y][x] = min(1.0, f[y][x] + rng.uniform(0.15, 0.55))

    return f


def bake(src_path, out_path, seed):
    desc, src = read_dmi(src_path)
    cell_w, cell_h, states = parse_states(desc)
    cols = src.width // cell_w
    field = coherent_field(cell_w, cell_h, seed)

    out = src.copy()
    sp, op = src.load(), out.load()

    total_cells = sum(c for _, c in states)
    for index in range(total_cells):
        col, row = index % cols, index // cols
        ox, oy = col * cell_w, row * cell_h
        for y in range(cell_h):
            for x in range(cell_w):
                r, g, b, a = sp[ox + x, oy + y]
                # Alpha is copied through untouched -- this is the property that
                # makes drawing outside the artwork impossible.
                if not a:
                    continue
                w = field[y][x]
                mr = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[0] * w
                mg = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[1] * w
                mb = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[2] * w
                op[ox + x, oy + y] = (int(r * mr), int(g * mg), int(b * mb), a)

    # Hand-splicing the metadata chunk in before IEND is what broke the last
    # attempt: a real .dmi is IHDR -> PLTE -> tRNS -> zTXt -> IDAT -> IEND, and
    # BYOND stops looking for the Description once it reaches IDAT. Appending
    # after IDAT means the state table is never read, the file loads as one
    # plain image, and every wall draws the WHOLE 192x160 sheet -- which is
    # exactly the "walls everywhere, off grid" symptom.
    #
    # So: let PIL write the text chunk. PngInfo chunks are emitted before IDAT
    # by construction, with no offset arithmetic on our side.
    meta = PngImagePlugin.PngInfo()
    meta.add_text("Description", desc, zip=True)
    out.save(out_path, format="PNG", pnginfo=meta)
    print(f"baked {out_path}\n      {src.width}x{src.height}  {total_cells} cells")
    return field


def bake_single_state(src_path, state_name, out_path, seed):
    """Crops ONE named state out of a larger multi-state sheet, applies the
    same wear pass, and writes a minimal single-state .dmi containing just
    that state.

    Needed for reinf_over specifically: wall_masks.dmi holds ~200 unrelated
    states belonging to other materials (reinf_stone*, reinf_metal,
    reinf_cult, fake-wall states, construction stages...) -- running the
    whole-sheet bake() against it would put an unwanted wear pass on all of
    those too. This touches only the one state's own pixels.

    Same safety property as bake(): alpha is copied through untouched, so
    wear cannot be drawn outside the state's own artwork.
    """
    desc, src = read_dmi(src_path)
    cell_w, cell_h, states = parse_states(desc)
    cols = src.width // cell_w

    index = 0
    found = None
    for name, count in states:
        for _ in range(count):
            if name == state_name:
                found = index
            index += 1
    if found is None:
        raise ValueError(f"state {state_name!r} not found in {src_path}")

    col, row = found % cols, found // cols
    ox, oy = col * cell_w, row * cell_h
    field = coherent_field(cell_w, cell_h, seed)

    cell = Image.new("RGBA", (cell_w, cell_h))
    sp, cp = src.load(), cell.load()
    for y in range(cell_h):
        for x in range(cell_w):
            r, g, b, a = sp[ox + x, oy + y]
            if not a:
                continue
            w = field[y][x]
            mr = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[0] * w
            mg = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[1] * w
            mb = 1.0 - WEAR_STRENGTH * CHANNEL_BIAS[2] * w
            cp[x, y] = (int(r * mr), int(g * mg), int(b * mb), a)

    # Minimal Description -- same "# BEGIN DMI ... # END DMI" format measured
    # directly out of wall_masks.dmi's own metadata, just for one state.
    single_desc = (
        f'# BEGIN DMI\nversion = 4.0\n\twidth = {cell_w}\n\theight = {cell_h}\n'
        f'state = "{state_name}"\n\tdirs = 1\n\tframes = 1\n# END DMI\n'
    )
    meta = PngImagePlugin.PngInfo()
    meta.add_text("Description", single_desc, zip=True)
    cell.save(out_path, format="PNG", pnginfo=meta)
    print(f"baked {out_path}\n      single state {state_name!r} ({cell_w}x{cell_h})")
    return field


def verify_chunk_order(out_path):
    """Hard gate: the Description chunk MUST precede IDAT or BYOND ignores it.

    This is the check whose absence let a broken sheet ship twice.
    """
    data = open(out_path, "rb").read()
    order, i = [], 8
    while i < len(data):
        ln = struct.unpack(">I", data[i:i + 4])[0]
        order.append(data[i + 4:i + 8].decode("ascii", "replace"))
        i += 12 + ln
    text_at = next((n for n, c in enumerate(order) if c in ("zTXt", "tEXt")), None)
    idat_at = next((n for n, c in enumerate(order) if c == "IDAT"), None)
    ok = text_at is not None and idat_at is not None and text_at < idat_at
    print(f"      chunk order: {' -> '.join(order[:6])}{' ...' if len(order) > 6 else ''}")
    print(f"      metadata precedes IDAT: {'YES' if ok else '*** NO -- BYOND WILL IGNORE IT ***'}")
    return ok


def verify_states_roundtrip(src_path, out_path):
    """The generated file must parse back to the SAME state list as its source.

    Reads the output the way a consumer would, rather than trusting that what
    was written is what was intended.
    """
    d1, _ = read_dmi(src_path)
    d2, _ = read_dmi(out_path)
    if d2 is None:
        print("      state roundtrip: *** NO METADATA READ BACK ***")
        return False
    s1 = parse_states(d1)[2]
    s2 = parse_states(d2)[2]
    same = s1 == s2
    print(f"      state roundtrip: {'YES' if same else '*** MISMATCH ***'} "
          f"({len(s2)} states, cells {sum(c for _, c in s2)})")
    return same


def verify_alpha(src_path, out_path):
    _d, s = read_dmi(src_path)
    _d, o = read_dmi(out_path)
    sp, op = s.load(), o.load()
    bad = sum(1 for y in range(s.height) for x in range(s.width)
              if sp[x, y][3] != op[x, y][3])
    print(f"      alpha identical to source: {'YES' if bad == 0 else f'NO ({bad} px differ)'}")
    return bad


def verify_seams(src_path, out_path, field, quad_states):
    """Assemble a tile from its four quadrant states and confirm the wear ratio
    at every pixel matches the single field -- i.e. no discontinuity at x=16 or
    the 8/24 line."""
    desc, s = read_dmi(src_path)
    _d, o = read_dmi(out_path)
    cell_w, cell_h, states = parse_states(desc)
    cols = s.width // cell_w
    pos, idx = {}, 0
    for name, cnt in states:
        for _ in range(cnt):
            pos.setdefault(name, (idx % cols, idx // cols))
            idx += 1
    sp, op = s.load(), o.load()

    worst = 0.0
    checked = 0
    for st in quad_states:
        if st not in pos:
            continue
        c, r = pos[st]
        ox, oy = c * cell_w, r * cell_h
        for y in range(cell_h):
            for x in range(cell_w):
                sr, sg, sb, sa = sp[ox + x, oy + y]
                if not sa or max(sr, sg, sb) < 8:
                    continue  # too dark to measure a ratio reliably
                orr = op[ox + x, oy + y][0]
                expected = (1.0 - WEAR_STRENGTH * CHANNEL_BIAS[0] * field[y][x])
                actual = orr / sr if sr else 1.0
                worst = max(worst, abs(actual - expected))
                checked += 1
    print(f"      seam check: {checked} px, worst deviation from the single "
          f"field = {worst:.4f} (rounding only if < 0.01)")
    return worst


print("=== steel wall sheet -- variant pool ===")
# Several independently-seeded bakes of the SAME source sheet. wall_icon.dm
# picks one per-turf from a stable hash of that turf's own coordinates, so
# neighbouring walls of the same material don't all show byte-identical wear.
# Each variant individually goes through the exact same alpha/seam checks as
# the single-sheet case -- there's nothing structurally different about a
# variant, there's just more than one of them.
STEEL_VARIANT_SEEDS = [20260811, 20260901, 20261015, 20261130]
steel_variant_paths = []
for n, seed in enumerate(STEEL_VARIANT_SEEDS, start=1):
    out_path = REPO + rf"\icons\turf\smooth\composite_solid_color_rust_{n}.dmi"
    f = bake(REPO + r"\icons\turf\smooth\composite_solid_color.dmi", out_path, seed=seed)
    verify_alpha(REPO + r"\icons\turf\smooth\composite_solid_color.dmi", out_path)
    verify_seams(REPO + r"\icons\turf\smooth\composite_solid_color.dmi", out_path, f,
                 ["1-i", "2-i", "3-i", "4-i", "1-f", "2-f", "3-f", "4-f"])
    steel_variant_paths.append(out_path)
f1 = None  # no longer a single field; each variant carries its own

print("=== plasteel reinforcement sheet -- variant pool ===")
# r_wall (Initialize(mapload, "plasteel", "plasteel")) uses plasteel as BOTH
# its base material and its reinf_material -- so plasteel's own wall_icon is
# what actually needs the wear pass, not steel's. Different source sheet
# (composite_reinf.dmi: 160x160, 25 cells, its own geometry), same pipeline,
# own seeds so it isn't a copy of the steel field.
PLASTEEL_VARIANT_SEEDS = [20270201, 20270305, 20270418, 20270522]
plasteel_variant_paths = []
for n, seed in enumerate(PLASTEEL_VARIANT_SEEDS, start=1):
    out_path = REPO + rf"\icons\turf\smooth\composite_reinf_rust_{n}.dmi"
    f = bake(REPO + r"\icons\turf\smooth\composite_reinf.dmi", out_path, seed=seed)
    verify_alpha(REPO + r"\icons\turf\smooth\composite_reinf.dmi", out_path)
    verify_seams(REPO + r"\icons\turf\smooth\composite_reinf.dmi", out_path, f,
                 ["1-i", "2-i", "3-i", "4-i", "1-f", "2-f", "3-f", "4-f"])
    plasteel_variant_paths.append(out_path)

print("=== window frame sheet ===")
f2 = bake(REPO + r"\icons\obj\smooth\window\full_window_frame_color.dmi",
          REPO + r"\icons\obj\smooth\window\full_window_frame_rust.dmi", seed=20260811)
verify_alpha(REPO + r"\icons\obj\smooth\window\full_window_frame_color.dmi",
             REPO + r"\icons\obj\smooth\window\full_window_frame_rust.dmi")
verify_seams(REPO + r"\icons\obj\smooth\window\full_window_frame_color.dmi",
             REPO + r"\icons\obj\smooth\window\full_window_frame_rust.dmi", f2,
             ["1-i", "2-i", "3-i", "4-i", "1-f", "2-f", "3-f", "4-f"])

# /turf/unsimulated/wall/darkshuttlewall stays single-sheet -- it's not a
# /material/steel wall (it's a separate unsimulated turf type entirely, see
# walls.dm), so it has no variant pool of its own and the per-turf picker in
# wall_icon.dm never runs for it. Seeded to match steel variant 1 specifically
# (the first entry in STEEL_VARIANT_SEEDS), so where a dark shuttle wall
# borders a steel wall showing variant 1, the wear still lines up -- borders
# against steel showing variant 2/3/4 will simply be two different (still
# individually seamless, still correctly masked) wear patterns meeting, the
# same as any two different materials meeting always looks today.
print("=== dark shuttle wall sheet ===")
f3 = bake(REPO + r"\icons\turf\smooth\shuttle_wall_dark.dmi",
          REPO + r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi", seed=STEEL_VARIANT_SEEDS[0])
verify_alpha(REPO + r"\icons\turf\smooth\shuttle_wall_dark.dmi",
             REPO + r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi")
verify_seams(REPO + r"\icons\turf\smooth\shuttle_wall_dark.dmi",
             REPO + r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi", f3,
             ["1-i", "2-i", "3-i", "4-i", "1-f", "2-f", "3-f", "4-f"])

# The gate that was missing. A sheet whose Description chunk lands after IDAT
# still compiles and still looks like a valid PNG -- BYOND simply ignores the
# state table and draws the whole sheet on every turf. Nothing downstream
# catches that, so it is checked here and the run fails loudly.
print("\n=== DMI STRUCTURE GATE ===")
PAIRS = [
    (r"\icons\turf\smooth\composite_solid_color.dmi", p.replace(REPO, ""))
    for p in steel_variant_paths
] + [
    (r"\icons\turf\smooth\composite_reinf.dmi", p.replace(REPO, ""))
    for p in plasteel_variant_paths
] + [
    (r"\icons\obj\smooth\window\full_window_frame_color.dmi",
     r"\icons\obj\smooth\window\full_window_frame_rust.dmi"),
    (r"\icons\turf\smooth\shuttle_wall_dark.dmi",
     r"\icons\turf\smooth\shuttle_wall_dark_rust.dmi"),
]
all_ok = True
for s, o in PAIRS:
    print(f"  {o.rsplit(chr(92), 1)[-1]}")
    ok1 = verify_chunk_order(REPO + o)
    ok2 = verify_states_roundtrip(REPO + s, REPO + o)
    all_ok = all_ok and ok1 and ok2

print("\nRESULT:", "SAFE TO SHIP" if all_ok else "*** DO NOT SHIP -- structure gate failed ***")
