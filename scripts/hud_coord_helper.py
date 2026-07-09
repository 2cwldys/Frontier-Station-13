#!/usr/bin/env python3
"""
BYOND screen_loc coordinate helper for Aurora HUD layout.
Click anywhere on the canvas to get anchor coordinates.
Resize the window to match your in-game resolution.

Anchor math (tile = 32px):
  EAST-N:px  →  x = W - N*32 + px  (px offsets EAST, toward screen edge)
  SOUTH+M:py →  y = H - M*32 - py  (py offsets NORTH, away from bottom)
  NORTH-N:px →  y_from_top = N*32 - px
  CENTER:py  →  y_from_top = H/2 - py  (positive py = north of center)
"""
import sys
import math

try:
    import pygame
except ImportError:
    sys.exit("Install pygame first:  pip install pygame")

try:
    import pyperclip
    HAS_CLIP = True
except ImportError:
    HAS_CLIP = False

TILE = 32
DEFAULT_W, DEFAULT_H = 480, 480

BG          = (20,  24,  35)
GRID        = (40,  48,  65)
GRID_MAJOR  = (65,  80, 110)
HOVER_FILL  = (255, 255, 100, 50)
CROSS       = (100, 255, 160)
TXT         = (220, 220, 220)
TXT_DIM     = (130, 140, 160)
TXT_ACCENT  = (100, 210, 255)
PANEL_BG    = (10,  12,  20, 210)


# ── coordinate math ──────────────────────────────────────────────────────────

def _east(x, w):
    dist = w - x          # pixels from right edge
    if dist <= 0:
        return "EAST:0"
    n  = math.ceil(dist / TILE)
    px = n * TILE - dist
    return f"EAST-{n}:{px}"

def _south(y, h):
    dist = h - y          # pixels from bottom edge
    m  = dist // TILE
    py = dist % TILE
    return f"SOUTH:{py}" if m == 0 else f"SOUTH+{m}:{py}"

def _north(y, _h):
    dist = y              # pixels from top edge
    if dist <= 0:
        return "NORTH:0"
    n  = math.ceil(dist / TILE)
    px = n * TILE - dist
    return f"NORTH-{n}:{px}"

def _center_x(x, w):
    offset = x - w // 2  # positive = east of center
    if offset >= 0:
        n  = offset // TILE
        px = offset % TILE
        return f"CENTER:{px}" if n == 0 else f"CENTER+{n}:{px}"
    west = -offset
    n  = west // TILE
    px = west % TILE
    return f"CENTER:{-px}" if n == 0 else f"CENTER-{n}:{px}"

def _center_y(y, h):
    offset = h // 2 - y  # positive = north of center (smaller y)
    if offset >= 0:
        n  = offset // TILE
        py = offset % TILE
        return f"CENTER:{py}" if n == 0 else f"CENTER-{n}:{py}"
    south = -offset
    n  = south // TILE
    py = south % TILE
    return f"CENTER+{n}:{py}"

def best_coords(x, y, w, h):
    """Return the most-useful screen_loc string for this position."""
    x_east   = _east(x, w)
    x_center = _center_x(x, w)
    y_south  = _south(y, h)
    y_north  = _north(y, h)
    y_center = _center_y(y, h)
    return {
        "EAST + SOUTH  (right-bottom HUD)": f'"{x_east},{y_south}"',
        "EAST + NORTH  (right-top HUD)":    f'"{x_east},{y_north}"',
        "EAST + CENTER (right-middle HUD)": f'"{x_east},{y_center}"',
        "CENTER + SOUTH":                   f'"{x_center},{y_south}"',
        "CENTER + NORTH":                   f'"{x_center},{y_north}"',
    }

PRIMARY_KEY = "EAST + SOUTH  (right-bottom HUD)"


# ── drawing helpers ───────────────────────────────────────────────────────────

def draw_grid(surf, w, h):
    for tx in range(0, w + 1, TILE):
        col = GRID_MAJOR if (tx // TILE) % 4 == 0 else GRID
        pygame.draw.line(surf, col, (tx, 0), (tx, h))
    for ty in range(0, h + 1, TILE):
        col = GRID_MAJOR if (ty // TILE) % 4 == 0 else GRID
        pygame.draw.line(surf, col, (0, ty), (w, ty))


def draw_panel(surf, lines, topleft, font_small, font_big=None, padding=6):
    widths  = []
    heights = []
    for text, big, _ in lines:
        f = (font_big if big and font_big else font_small)
        s = f.render(text, True, TXT)
        widths.append(s.get_width())
        heights.append(s.get_height())

    pw = max(widths) + padding * 2
    ph = sum(heights) + padding * 2 + max(0, len(lines) - 1) * 2

    x, y = topleft
    sw, sh = surf.get_size()
    x = min(x, sw - pw - 2)
    y = min(y, sh - ph - 2)
    x = max(x, 2)
    y = max(y, 2)

    panel = pygame.Surface((pw, ph), pygame.SRCALPHA)
    panel.fill(PANEL_BG)
    surf.blit(panel, (x, y))

    cy = y + padding
    for text, big, accent in lines:
        f   = (font_big if big and font_big else font_small)
        col = TXT_ACCENT if accent else (TXT if big else TXT_DIM)
        s   = f.render(text, True, col)
        surf.blit(s, (x + padding, cy))
        cy += s.get_height() + 2

    return pygame.Rect(x, y, pw, ph)


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    pygame.init()
    w, h = DEFAULT_W, DEFAULT_H
    flags = pygame.RESIZABLE
    screen = pygame.display.set_mode((w, h), flags)
    pygame.display.set_caption("Aurora HUD coord helper — click to copy screen_loc")

    font_sm  = pygame.font.SysFont("Consolas", 13)
    font_med = pygame.font.SysFont("Consolas", 15, bold=True)

    mouse   = (0, 0)
    clicked = None
    clock   = pygame.time.Clock()

    while True:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                pygame.quit()
                sys.exit()

            elif ev.type == pygame.VIDEORESIZE:
                w, h = ev.w, ev.h
                screen = pygame.display.set_mode((w, h), flags)

            elif ev.type == pygame.MOUSEMOTION:
                mouse = ev.pos

            elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
                clicked = ev.pos
                coords  = best_coords(*clicked, w, h)
                primary = coords[PRIMARY_KEY]
                print(f"\n=== click ({clicked[0]}, {clicked[1]})  screen {w}×{h} ===")
                for label, val in coords.items():
                    print(f"  {label}: {val}")
                if HAS_CLIP:
                    pyperclip.copy(primary)
                    print(f"  [copied] {primary}")

        # ── background + grid
        screen.fill(BG)
        draw_grid(screen, w, h)

        # ── hover tile highlight
        mx, my = mouse
        tx = (mx // TILE) * TILE
        ty = (my // TILE) * TILE
        tile_surf = pygame.Surface((TILE, TILE), pygame.SRCALPHA)
        tile_surf.fill(HOVER_FILL)
        screen.blit(tile_surf, (tx, ty))

        # ── hover info panel
        coords = best_coords(mx, my, w, h)
        hover_lines = [
            (f"({mx}, {my})  —  {w}×{h} screen", True, False),
        ]
        for label, val in coords.items():
            is_primary = (label == PRIMARY_KEY)
            hover_lines.append((f"  {val}  [{label}]", False, is_primary))

        draw_panel(screen, hover_lines, (mx + 14, my + 14), font_sm, font_med)

        # ── clicked crosshair + panel
        if clicked:
            cx, cy = clicked
            pygame.draw.circle(screen, CROSS, (cx, cy), 5, 1)
            pygame.draw.line(screen, CROSS, (cx - 10, cy), (cx + 10, cy), 1)
            pygame.draw.line(screen, CROSS, (cx, cy - 10), (cx, cy + 10), 1)

            c2 = best_coords(*clicked, w, h)
            clip_note = "  (copied to clipboard)" if HAS_CLIP else ""
            fixed_lines = [
                (f"LAST CLICK  ({cx}, {cy}){clip_note}", True, False),
            ]
            for label, val in c2.items():
                is_primary = (label == PRIMARY_KEY)
                fixed_lines.append((f"  {val}", False, is_primary))
            draw_panel(screen, fixed_lines, (4, h - 160), font_sm, font_med)

        # ── instructions bar
        tip = "Left-click = get coords"
        if HAS_CLIP:
            tip += "  |  primary (EAST+SOUTH) auto-copied"
        tip += "  |  resize window to match game resolution"
        draw_panel(screen, [(tip, False, False)], (4, 4), font_sm)

        pygame.display.flip()
        clock.tick(60)


if __name__ == "__main__":
    main()
