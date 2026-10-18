"""Draws the addon's small textures: Textures/RoundedGlow.tga (the resting / combat
glow around the custom frame), BadgeDisc.tga and BadgeRing.tga (the level badge) and
Blank.tga. The custom frame itself is drawn by tools/make_blend_frame.py.
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
