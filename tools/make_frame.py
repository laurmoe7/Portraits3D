"""Draws the addon's small textures: Textures/RoundedGlow.tga (the resting / combat
glow around the custom frame), BadgeDisc.tga and BadgeRing.tga (the level badge),
PlateFill.tga (the plate's brown end panel) and Blank.tga. The custom frame itself is drawn by tools/make_blend_frame.py.
Needs numpy only.   Usage: py tools/make_frame.py"""
import struct
import numpy as np

SIZE, SS = 256, 4
R_OUT = 0.30           # corner radius of the rounded square the glow goes around

def rrect_sdf(x, y, half, r):
    qx = np.abs(x) - half + r
    qy = np.abs(y) - half + r
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

n = SIZE * SS
c = (np.arange(n) + 0.5) / n * 2 - 1
x, y = np.meshgrid(c, c)

def down(a):
    return a.reshape(SIZE, SS, SIZE, SS, *a.shape[2:]).mean(axis=(1, 3))
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)

# ---- Textures/RoundedGlow.tga: a soft white halo around a rounded square that
# fills GLOW_RATIO of the picture. Tinted yellow/red in game (resting/combat).
GLOW_RATIO = 0.80    # keep in sync with Portraits3D.lua
d_g = rrect_sdf(x, y, GLOW_RATIO, R_OUT * GLOW_RATIO)
halo = np.where(d_g > 0, np.clip(1 - d_g / (1 - GLOW_RATIO), 0, 1) ** 2.2, 0.0) * 0.95
ga = down(halo)
gpx = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
gpx[..., :3] = 255
gpx[..., 3] = (np.clip(ga, 0, 1) * 255 + 0.5).astype(np.uint8)
gb = gpx[..., [2, 1, 0, 3]]
open("Textures/RoundedGlow.tga", "wb").write(hdr + gb.tobytes())

# ---- Textures/BadgeDisc.tga: the level circle's centre. A round disc, dark brown
# with a black vignette towards its edge and a little grain.
BS = 64
bn = BS * SS
bc = (np.arange(bn) + 0.5) / bn * 2 - 1
bx, by = np.meshgrid(bc, bc)
rad = np.hypot(bx, by)
inside = np.clip((1 - rad) * bn / 2, 0, 1)                 # antialiased circle edge
vig = np.clip((rad - 0.35) / 0.65, 0, 1) ** 1.6            # 0 in the middle, 1 at the rim
centre = np.array((0.22, 0.155, 0.095)) * (1.12 - 0.22 * (by + 1) / 2)[..., None]
edge = np.array((0.03, 0.02, 0.012))
brng = np.random.default_rng(3)
grain = 1 + 0.16 * (brng.random((bn, bn)) - 0.5)
bcol = (centre * (1 - vig[..., None]) + edge * vig[..., None]) * grain[..., None]
bdown = lambda a: a.reshape(BS, SS, BS, SS, *a.shape[2:]).mean(axis=(1, 3))
ba = bdown(inside)
brgb = bdown(bcol * inside[..., None]) / np.maximum(ba[..., None], 1e-6)
bpx = (np.dstack([np.clip(brgb, 0, 1), ba]) * 255 + 0.5).astype(np.uint8)
bhdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, BS, BS, 32, 0x28)
open("Textures/BadgeDisc.tga", "wb").write(bhdr + bpx[..., [2, 1, 0, 3]].tobytes())

# ---- Textures/BadgeRing.tga: the level circle's ring, a full round disc (the
# centre picture covers its middle). Tan bronze, lighter at the top, with the
# official circle's highlight on the upper left and a shadow on the lower right.
ang = np.arctan2(-by, bx)                                   # 0 = right, up positive
light = np.cos(ang - np.radians(135))                       # 1 towards the upper left
vert = ((by + 1) / 2)[..., None]                            # 0 top .. 1 bottom
base = np.array((0.74, 0.62, 0.46)) * (1 - vert) + np.array((0.50, 0.39, 0.27)) * vert
glint = np.clip((light - 0.55) / 0.45, 0, 1) ** 1.5 * np.clip((rad - 0.7) / 0.3, 0, 1)
shade = np.clip((-light - 0.2) / 0.8, 0, 1)
rcol = base * (1 + 0.38 * glint[..., None] - 0.22 * shade[..., None])
rcol = np.clip(rcol, 0, 1)
rrgb = bdown(rcol * inside[..., None]) / np.maximum(ba[..., None], 1e-6)
rpx = (np.dstack([np.clip(rrgb, 0, 1), ba]) * 255 + 0.5).astype(np.uint8)
open("Textures/BadgeRing.tga", "wb").write(bhdr + rpx[..., [2, 1, 0, 3]].tobytes())

# ---- Textures/Blank.tga: fully see-through. Used as a mask it hides whatever it is
# put on, however the game sets that texture's alpha.
blank = np.zeros((16, 16, 4), dtype=np.uint8)
bl_hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 16, 16, 32, 0x28)
open("Textures/Blank.tga", "wb").write(bl_hdr + blank.tobytes())

# ---- Textures/PlateFill.tga: the dark brown panel at the end of the bar plate, between
# the ring and the plate's first line. On the game's picture it lies under the ring,
# so it goes when the ring is cut out; this one is drawn under the game's picture to
# fill that strip again. Mottled olive brown with faint vertical streaks, in shadow
# under the plate's top line and above its bottom line. Stretched to the strip in game.
PW, PH = 32, 128
prng = np.random.default_rng(5)
def smooth(cells_x, cells_y, w, h):    # smooth noise (0..1) over a w x h picture
    g = prng.random((cells_y + 1, cells_x + 1))
    iy = np.linspace(0, cells_y, h, endpoint=False); ix = np.linspace(0, cells_x, w, endpoint=False)
    y0, x0 = iy.astype(int), ix.astype(int)
    fy, fx = iy - y0, ix - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    rows = g[y0] * (1 - fy)[:, None] + g[y0 + 1] * fy[:, None]
    return rows[:, x0] * (1 - fx)[None, :] + rows[:, x0 + 1] * fx[None, :]
py_ = (np.arange(PH) + 0.5) / PH
shade = np.clip(np.minimum(py_, 1 - py_) / 0.1, 0, 1) ** 0.7   # dark under / above the plate lines
shade = (0.4 + 0.6 * shade)[:, None]
mottle = 0.7 + 0.6 * smooth(3, 10, PW, PH)
streaks = 1 + 0.4 * (smooth(10, 3, PW, PH) - 0.5)
grain = 1 + 0.18 * (prng.random((PH, PW)) - 0.5)
v = shade * mottle * streaks * grain
pcol = np.array((96, 66, 26)) * v[..., None] * np.dstack([np.ones_like(v), np.ones_like(v), 0.85 + 0.3 * smooth(4, 6, PW, PH)])
ppx = np.zeros((PH, PW, 4), dtype=np.uint8)
ppx[..., :3] = np.clip(pcol + 0.5, 0, 255).astype(np.uint8)
ppx[..., 3] = 255
p_hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, PW, PH, 32, 0x28)
open("Textures/PlateFill.tga", "wb").write(p_hdr + ppx[..., [2, 1, 0, 3]].tobytes())
