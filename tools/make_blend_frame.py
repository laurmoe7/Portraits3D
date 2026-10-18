"""Draws the custom frame's textures:

  Textures/RoundedFrameBlend.tga  a rounded-square border shaded like Blizzard's
                                  portrait ring: two thin gold lines with a dark
                                  groove between them and a black inner edge. In game it
                                  takes the place of the ring, at the ring's own size,
                                  so the name plate and bars tuck under it the way
                                  they tuck under the ring.
  Textures/RingHole.tga           mask for Blizzard's frame picture: kept everywhere
                                  except a round hole that removes the ring.
  Textures/RingHoleCut.tga        the same with a straight side towards the bars
  (+ Mirror)                      (used in game), so the plate's edge line is kept.
  Textures/FrameShadow.tga        a soft dark shadow drawn under the frame.

The colours and band widths were measured from the game's unit frame picture
(the player ring is 34 px in radius; this band is about 5 px wide).
Needs numpy only.   Usage: py tools/make_blend_frame.py [preview.png]"""
import struct, sys, zlib
import numpy as np

SIZE, SS = 256, 4
RING_R = 34.0          # Blizzard's player ring radius in its picture's pixels; one pixel = 1 / RING_R
HOLE = 0.85            # hole width as a fraction of the picture; keep in sync with HOLE in Portraits3D.lua
R_OUT = 0.28           # corner radius of the outer edge (fraction of the half width)
HOLE_DISC = 0.84       # RingHole.tga: the hole's diameter as a fraction of the picture; keep in sync with Portraits3D.lua

def rrect_sdf(x, y, half, r):
    qx = np.abs(x) - half + r
    qy = np.abs(y) - half + r
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

n = SIZE * SS
c = (np.arange(n) + 0.5) / n * 2 - 1
x, y = np.meshgrid(c, c)
d_out = rrect_sdf(x, y, 1.0, R_OUT)
d_hole = rrect_sdf(x, y, HOLE, max(R_OUT - (1 - HOLE), 0.06))

# ---- wear: the game's ring is far from clean. Along its length the brightness jumps
# by about 15% from one pixel to the next and drifts over longer stretches, the lines
# are not quite even, and there are dark pits, nicks and the odd bright glint. All of
# it is sized in Blizzard pixels, so it survives being shrunk to the frame's size.
rng = np.random.default_rng(11)
PERIM = 8 * RING_R                     # length around the edge, roughly, in Blizzard pixels
u = (np.arctan2(y, x) / (2 * np.pi) % 1) * PERIM   # position along the edge

def along(cell):                       # smooth noise along the edge (0..1), wraps around
    N = max(int(round(PERIM / cell)), 4)
    g = rng.random(N)
    t = u / PERIM * N
    i0 = np.floor(t).astype(int); fr = t - i0
    fr = fr * fr * (3 - 2 * fr)
    return g[i0 % N] * (1 - fr) + g[(i0 + 1) % N] * fr

def blotch(cells):                     # smooth noise over the picture (0..1)
    g = rng.random((cells + 1, cells + 1))
    idx = np.linspace(0, cells, n, endpoint=False)
    i0 = idx.astype(int); fr = idx - i0
    fr = fr * fr * (3 - 2 * fr)
    rows = g[i0] * (1 - fr)[:, None] + g[i0 + 1] * fr[:, None]
    return rows[:, i0] * (1 - fr)[None, :] + rows[:, i0 + 1] * fr[None, :]

d_out = d_out + (along(5) - 0.5) * 0.3 / RING_R   # a slightly uneven outer edge
px = -d_out * RING_R                   # depth from the outer edge, in Blizzard pixels
pl = px + (along(11) - 0.5) * 0.28      # the lines and groove wander a little

# The game's ring is two thin gold lines with a dark groove between them, lit from
# above and a little from the left: the outer line shines on the top and is in
# shadow on the bottom, the inner line the other way round. Widths in Blizzard
# pixels, from the outer edge inwards.
OUTER = (0.0, 2.0)     # outer gold line
INNER = (2.9, 3.8)     # inner gold line (the groove is between the two)
DARK_END = 4.5         # dark bronze lip, then a black edge up to the hole
gy, gx = np.gradient(rrect_sdf(x, y, 1.0, R_OUT))
m = np.maximum(np.hypot(gx, gy), 1e-9)
nx, ny = gx / m, gy / m                # outward normal of the edge; y grows downward
L = np.array((-0.35, -0.94)); L = L / np.linalg.norm(L)
f = nx * L[0] + ny * L[1]              # 1 where the edge faces the light (top), -1 bottom

# colour ramp measured from the ring: shadow, body, lit, highlight
STOPS = [(0.0, (45, 25, 5)), (0.35, (110, 75, 30)), (0.6, (172, 138, 94)),
         (0.85, (224, 189, 137)), (1.0, (250, 226, 176))]
def ramp(v):
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for (a0, c0), (a1, c1) in zip(STOPS, STOPS[1:]):
        t = np.clip((v - a0) / (a1 - a0), 0, 1)[..., None]
        sel = ((v >= a0) & (v <= a1))[..., None]
        out = np.where(sel, np.array(c0, float) * (1 - t) + np.array(c1, float) * t, out)
    return out
def across(lo, hi, d):                 # rounded profile across a line: 1 in its middle
    t = np.clip((d - lo) / (hi - lo), 0, 1)
    return np.sin(np.pi * t) ** 0.6

# brightness streaks along the lines: pixel-sized jumps plus slower drift
streak = 1 + 0.18 * (along(1.8) - 0.5) + 0.20 * (along(10) - 0.5)
outer = ramp((0.62 + 0.38 * f) * (0.72 + 0.28 * across(*OUTER, px)) * streak)
inner = ramp((0.50 - 0.40 * f) * (0.75 + 0.25 * across(*INNER, pl)) * (1 + 0.3 * (along(2) - 0.5)))
dirt = (0.65 + 0.7 * along(4))[..., None]          # the groove is dirtier in places
groove = np.array((62, 38, 9), float) * dirt
lip = np.array((40, 25, 6), float) * (0.8 + 0.4 * along(3))[..., None]
col = np.where((px < OUTER[1])[..., None], outer, groove)
col = np.where(((pl >= INNER[0]) & (pl < INNER[1]))[..., None], inner, col)
col = np.where((pl >= INNER[1])[..., None], lip, col)
col = np.where((pl >= DARK_END)[..., None], np.array((16, 10, 4), float), col)

# pits and nicks (dark), and a few glints on the lit outer line, placed along the edge
spots = np.zeros((n, n)); glint = np.zeros((n, n))
for _ in range(16):
    su, sd = rng.random() * PERIM, rng.random() * 4.4
    r = rng.choice([0.5, 0.7, 0.9], p=[0.45, 0.4, 0.15])
    du = (u - su + PERIM / 2) % PERIM - PERIM / 2
    spots = np.maximum(spots, np.clip(1.3 - np.hypot(du, px - sd) / r, 0, 1) * rng.uniform(0.3, 0.55))
for _ in range(5):                     # short scratches along the outer line
    su, sd, ln = rng.random() * PERIM, rng.uniform(0.4, 1.7), rng.uniform(2.5, 6)
    du = (u - su + PERIM / 2) % PERIM - PERIM / 2
    spots = np.maximum(spots, ((np.abs(du) < ln / 2) & (np.abs(px - sd) < 0.22)) * 0.35)
for _ in range(9):
    su, sd = rng.random() * PERIM, rng.uniform(0.5, 1.5)
    du = (u - su + PERIM / 2) % PERIM - PERIM / 2
    glint = np.maximum(glint, np.clip(1 - np.hypot(du / 1.4, px - sd) / 0.55, 0, 1))
glint *= np.clip(f + 0.2, 0, 1)        # glints only where the light reaches
col = col * (1 - spots)[..., None]
col = col * (1 - glint[..., None] * 0.55) + np.array((255, 240, 205), float) * glint[..., None] * 0.55

# pixel-sized grain, a slight warm / cool drift in colour, and blotchy tarnish
grain = 1 + 0.06 * (blotch(int(2 * RING_R)) - 0.5) + 0.03 * (rng.random((n, n)) - 0.5)
tarnish = 1 - 0.18 * np.clip(blotch(9) - 0.55, 0, 1) * 2
hue = blotch(11) - 0.5
col = col * (grain * tarnish)[..., None] * np.dstack([1 + 0.05 * hue, np.ones_like(hue), 1 - 0.09 * hue])
col = np.clip(col / 255, 0, 1)

band = (d_out < 0) & (d_hole > 0)
w = -d_hole * RING_R                   # depth inside the hole, in Blizzard pixels
shadow = 0.6 * np.clip(1 - w / 2.5, 0, 1) ** 2
alpha = np.where(band, 1.0, np.where(d_hole < 0, shadow, 0.0))
col = np.where(band[..., None], col, 0.0)

def down_(a, size=SIZE):
    return a.reshape(size, SS, size, SS, *a.shape[2:]).mean(axis=(1, 3))
a = down_(alpha)
rgb = np.where(a[..., None] > 0, down_(col * alpha[..., None]) / np.maximum(a[..., None], 1e-6), 0)
frame_px = (np.dstack([np.clip(rgb, 0, 1), a]) * 255 + 0.5).astype(np.uint8)

def tga(path, img):
    h, w_ = img.shape[:2]
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w_, h, 32, 0x28)
    open(path, "wb").write(hdr + img[..., [2, 1, 0, 3]].tobytes())

tga("Textures/RoundedFrameBlend.tga", frame_px)

# ---- RingHole.tga: opaque (kept) with a round see-through hole of HOLE_DISC of the
# picture. Used with CLAMP, so everything outside the picture is kept as well.
HS = 128
hn = HS * SS
hc = (np.arange(hn) + 0.5) / hn * 2 - 1
hx, hy = np.meshgrid(hc, hc)
keep = (np.hypot(hx, hy) > HOLE_DISC).astype(float)
hk = keep.reshape(HS, SS, HS, SS).mean(axis=(1, 3))
hole_px = np.zeros((HS, HS, 4), dtype=np.uint8)
hole_px[..., :3] = 255
hole_px[..., 3] = (hk * 255 + 0.5).astype(np.uint8)
tga("Textures/RingHole.tga", hole_px)

# ---- RingHoleCut.tga (+ Mirror): the same hole with a straight side towards the
# bars (right; left in the mirror), at FLAT_CUT of the half width. The plate's edge
# line sits right against the ring, so a round hole big enough for the ring also
# clipped that line and the joints of the bar lines; the flat side stops short of it.
FLAT_CUT = 0.714       # = HOLE_DISC * 0.85; keep in sync with Portraits3D.lua
# (The game keeps a texture it has loaded until it is restarted, even across /reload;
# when one of these pictures changes, save it under a new name so the change shows.)
keep = ((np.hypot(hx, hy) > HOLE_DISC) | (hx > FLAT_CUT)).astype(float)
hk = keep.reshape(HS, SS, HS, SS).mean(axis=(1, 3))
flat_px = hole_px.copy()
flat_px[..., 3] = (hk * 255 + 0.5).astype(np.uint8)
tga("Textures/RingHoleCut.tga", flat_px)
tga("Textures/RingHoleCutMirror.tga", np.ascontiguousarray(flat_px[:, ::-1]))

# ---- FrameShadow.tga: a soft dark shadow around the frame, like the game's frame parts
# have (a dark fringe about 2 px wide, strongest under them). The frame fills
# SHADOW_RATIO of the picture; the shadow is dark under the frame's band and fades out
# over about 3 Blizzard px beyond its edge, and is clear inside the frame's hole so it
# never darkens the portrait. Drawn a little lower than the frame in game.
SHADOW_RATIO = 0.86    # keep in sync with Portraits3D.lua
SW = 3.0 / RING_R      # fade width, as a fraction of the frame's half width
sd = rrect_sdf(x, y, SHADOW_RATIO, R_OUT * SHADOW_RATIO) / SHADOW_RATIO   # in frame half widths
inner = rrect_sdf(x, y, SHADOW_RATIO * HOLE, max(R_OUT - (1 - HOLE), 0.06) * SHADOW_RATIO) / SHADOW_RATIO
sh = np.where(sd > 0, 0.62 * np.clip(1 - sd / SW, 0, 1) ** 2, 0.62)
sh = np.where(inner < 0, 0.0, sh)
sa = down_(sh)
shadow_px = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
shadow_px[..., 3] = (np.clip(sa, 0, 1) * 255 + 0.5).astype(np.uint8)
tga("Textures/FrameShadow.tga", shadow_px)

if len(sys.argv) > 1:   # optional preview on a dark background
    bg = np.array([20, 20, 20], float)
    pf = frame_px.astype(float)
    out = (pf[..., :3] * pf[..., 3:4] / 255 + bg * (1 - pf[..., 3:4] / 255)).astype(np.uint8)
    raw = b"".join(b"\x00" + out[r].tobytes() for r in range(SIZE))
    def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    open(sys.argv[1], "wb").write(png)
