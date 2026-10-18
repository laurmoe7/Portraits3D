"""Draws Textures/DisconnectBolt6.tga: the red lightning bolt shown on an offline
player's portrait (in place of the game's small Disconnect-Icon).
Drawn smooth at about the size it is shown at, so its edges stay clean, in the style
of the game's icons: a painted crimson bolt with a hot glowing core, sharp angular
tips, a thin gold bevelled edge lit from the top left, a dark outline and a soft
black shadow around it, like the original.
Needs numpy only.   Usage: py tools/make_bolt.py [preview.png]"""
import struct, sys, zlib
import numpy as np

# 128 px: close to the size it is shown at, so the game does not have to shrink it
# much (shrinking a big picture a lot made its edges jagged)
SIZE, SS = 128, 8
OUT = "Textures/DisconnectBolt6.tga"  # a new name whenever it changes: the game caches textures

# The bolt's outline, in fractions of the picture (x right, y down), shaped like the
# game's Disconnect-Icon: a thin stroke leaning down to the right, a spur out to each
# side where it bends, and a long sharp point at each end (the same turned half
# round about the bend); centred.
_SHAPE = [(0.34, 0.04), (0.57, 0.43), (0.74, 0.40),
          (0.86, 0.96), (0.63, 0.57), (0.46, 0.60)]
_cx = (min(p[0] for p in _SHAPE) + max(p[0] for p in _SHAPE)) / 2
BOLT = [(x_ - _cx + 0.5, y_ - 0.005) for x_, y_ in _SHAPE]

n = SIZE * SS
c = (np.arange(n) + 0.5) / n
x, y = np.meshgrid(c, c)
px = 1.0 / 256   # unit for the widths below (drawn for a 256 px picture)
aa = 1.0 / SIZE  # one pixel of the final picture: the width of the smoothed edge
rng = np.random.default_rng(7)


def signed_distance(pts, x, y):
    """Distance to the polygon's edge: negative inside, positive outside."""
    d = np.full(x.shape, np.inf)
    inside = np.zeros(x.shape, dtype=bool)
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        ex, ey = bx - ax, by - ay
        t = np.clip(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey), 0, 1)
        d = np.minimum(d, np.hypot(x - ax - t * ex, y - ay - t * ey))
        crosses = (ay > y) != (by > y)
        with np.errstate(divide="ignore", invalid="ignore"):
            hit = x < ax + (y - ay) * ex / (ey if ey != 0 else 1e-12)
        inside ^= crosses & hit
    return np.where(inside, -d, d)


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def noise(cells):
    """Soft value noise at about `cells` blobs across, 0..1."""
    g = rng.random((cells + 2, cells + 2))
    gx = c * cells
    i = gx.astype(int)
    f = gx - i
    f = f * f * (3 - 2 * f)
    rows = g[i][:, i] * (1 - f)[None, :] + g[i][:, i + 1] * f[None, :]
    rows2 = g[i + 1][:, i] * (1 - f)[None, :] + g[i + 1][:, i + 1] * f[None, :]
    return rows * (1 - f)[:, None] + rows2 * f[:, None]


d = signed_distance(BOLT, x, y)

# Which way the edge faces: lit where it faces the top left.
gy, gx = np.gradient(d)
norm = np.hypot(gx, gy) + 1e-12
lit = np.clip(-(gx + gy) / norm / np.sqrt(2), 0, 1)

body = smooth(0.6 * aa, -0.6 * aa, d)              # the bolt (anti-aliased)
bevel = smooth(-5 * px, -2 * px, d) * body          # the gold edge band
outline = smooth(4 * px, 1 * px, d)                 # dark line around it
glow = np.exp(-np.maximum(d, 0) / (9 * px)) * 0.6   # soft black shadow around it
shadow = smooth(10 * px, -2 * px, signed_distance(BOLT, x - 0.014, y - 0.02)) * 0.6

# Painted crimson: deep at the edges and towards the point, with a hot core that
# runs down the middle of the strokes, and a brush-stroke grain.
paint = 0.75 + 0.35 * (noise(9) - 0.5) + 0.12 * (noise(40) - 0.5)
depth = np.clip((y - 0.05) / 0.9, 0, 1)
inner = smooth(-2 * px, -16 * px, d)               # 0 at the edge, 1 deep inside
base = np.stack([0.92 - 0.32 * depth, 0.06 + 0.02 * depth, 0.04 + 0.0 * depth], -1)
base = base * (0.65 + 0.35 * inner)[..., None] * paint[..., None]
core = (smooth(-9 * px, -20 * px, d) * (0.6 - 0.4 * depth))[..., None]
hot = np.array([1.0, 0.55, 0.25])                  # orange heat in the middle
fill = base * (1 - core) + hot * core * (0.8 + 0.4 * (noise(14) - 0.5))[..., None]

# Gold bevel, like the game's UI trim: bright gold where lit, dark bronze in shade.
gold_lit = np.array([1.0, 0.86, 0.45])
gold_dark = np.array([0.42, 0.24, 0.06])
gold = gold_lit * lit[..., None] + gold_dark * (1 - lit[..., None])
gold = gold * (0.85 + 0.3 * (noise(30) - 0.5))[..., None]
col = fill * (1 - bevel[..., None]) + gold * bevel[..., None]

# Composite (premultiplied): glow and shadow under the black outline, bolt on top.
glow_rgb = np.array([0.0, 0.0, 0.0])
under_a = np.clip(glow + shadow - glow * shadow, 0, 1)
under_rgb = glow_rgb * (glow * (1 - shadow))[..., None]
out_a = outline * 0.95
a = under_a * (1 - out_a) + out_a
rgb = under_rgb * (1 - out_a)[..., None]
rgb = rgb * (1 - body)[..., None] + col * body[..., None]
a = a * (1 - body) + body


def down(v):
    return v.reshape(SIZE, SS, SIZE, SS, *v.shape[2:]).mean(axis=(1, 3))


a = down(a)
rgb = down(rgb)
# straight (not premultiplied) colour, as the game expects
with np.errstate(divide="ignore", invalid="ignore"):
    straight = np.where(a[..., None] > 0, rgb / a[..., None], 0)
px8 = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
px8[..., :3] = (np.clip(straight, 0, 1) * 255 + 0.5).astype(np.uint8)
px8[..., 3] = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)

hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
open(OUT, "wb").write(hdr + px8[..., [2, 1, 0, 3]].tobytes())

if len(sys.argv) > 1:
    # preview on a mid grey background (the shadow shows on it)
    bgc = np.full((SIZE, SIZE, 3), 0.4)
    over = px8[..., :3] / 255 * (px8[..., 3:] / 255) + bgc * (1 - px8[..., 3:] / 255)
    img = (over * 255 + 0.5).astype(np.uint8)
    raw = b"".join(b"\x00" + img[r].tobytes() for r in range(SIZE))

    def chunk(t, data):
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(sys.argv[1], "wb").write(png)
