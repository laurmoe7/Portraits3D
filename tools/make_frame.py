"""Draws Textures/RoundedFrame.tga: a rounded-square portrait border with a
rounded-square hole (HOLE of the width) and a soft inner shadow in the hole.
Needs numpy only.   Usage: py tools/make_frame.py [preview.png]"""
import struct, sys, zlib
import numpy as np

SIZE, SS = 256, 4
HOLE = 0.86          # hole width as a fraction of the picture; keep in sync with Portraits3D.lua
R_OUT, R_IN = 0.30, 0.20
LIGHT = np.array([-0.6, -0.8])   # direction towards the light (top left; y grows downward)

def rrect_sdf(x, y, half, r):
    qx = np.abs(x) - half + r
    qy = np.abs(y) - half + r
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

def normal(d):
    gy, gx = np.gradient(d)
    m = np.maximum(np.hypot(gx, gy), 1e-9)
    return gx / m, gy / m

n = SIZE * SS
c = (np.arange(n) + 0.5) / n * 2 - 1
x, y = np.meshgrid(c, c)
d_out = rrect_sdf(x, y, 1.0, R_OUT)      # < 0 inside the picture shape
d_hole = rrect_sdf(x, y, HOLE, R_IN)     # < 0 inside the hole
t = -d_out                                # depth from the outer edge
u = d_hole                                # distance from the hole edge, outside it

nx, ny = normal(d_out)                    # faces away from the ring at its outer edge
s_out = nx * LIGHT[0] + ny * LIGHT[1]
hx, hy = normal(-d_hole)                  # faces into the hole at its inner edge
s_in = hx * LIGHT[0] + hy * LIGHT[1]

def lerp(a, b, f):
    f = np.clip(f, 0, 1)[..., None]
    return np.array(a) * (1 - f) + np.array(b) * f

GOLD = np.array((0.80, 0.62, 0.24))
def lit(s):                                # gold shaded by the light
    return GOLD * np.clip(0.80 + 0.55 * s, 0.35, 1.45)[..., None]

# bronze body: lighter towards the top, with a little of the edge lighting
body = lerp((0.36, 0.27, 0.13), (0.20, 0.14, 0.07), (y + 1) / 2) * np.clip(0.9 + 0.15 * s_out, 0.8, 1.1)[..., None]
col = body
col = np.where(((t >= 0.007) & (t < 0.030))[..., None], lit(s_out), col)
col = np.where((t < 0.007)[..., None], np.array((0.05, 0.04, 0.02)), col)
col = np.where(((u >= 0.004) & (u < 0.017))[..., None], lit(s_in), col)
col = np.where((u < 0.004)[..., None], np.array((0.03, 0.02, 0.01)), col)
col = np.clip(col, 0, 1)

ring = (d_out < 0) & (d_hole > 0)
w = -d_hole                                # depth inside the hole
shadow = 0.55 * np.clip(1 - w / 0.06, 0, 1) ** 2
alpha = np.where(ring, 1.0, np.where(d_hole < 0, shadow, 0.0))
col = np.where(ring[..., None], col, 0.0)   # the shadow is black
pre = col * alpha[..., None]

def down(a):
    return a.reshape(SIZE, SS, SIZE, SS, *a.shape[2:]).mean(axis=(1, 3))
a = down(alpha)
rgb = np.where(a[..., None] > 0, down(pre) / np.maximum(a[..., None], 1e-6), 0)
img = np.dstack([np.clip(rgb, 0, 1), a])
px = (img * 255 + 0.5).astype(np.uint8)

bgra = px[..., [2, 1, 0, 3]]
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
open("Textures/RoundedFrame.tga", "wb").write(hdr + bgra.tobytes())

if len(sys.argv) > 1:   # optional preview on a grey-blue background
    bg = np.array([60, 80, 70], dtype=float)
    pf = px.astype(float)
    out = (pf[..., :3] * pf[..., 3:4] / 255 + bg * (1 - pf[..., 3:4] / 255)).astype(np.uint8)
    raw = b"".join(b"\x00" + out[r].tobytes() for r in range(SIZE))
    def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    open(sys.argv[1], "wb").write(png)

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

# ---- Textures/RingCutEdge.tga (+ Mirror): the "keep" mask for Blizzard's frame
# picture. Opaque (kept) everywhere except: a see-through column at the very left
# (the game extends it leftwards, hiding everything left of the line) and two
# see-through rounded corners at top-left and bottom-left. In game the picture is
# placed so its top and bottom edges sit on the name plate's top and the mana
# bar's bottom; that rounds the plate's and the bars' left corners.
EDGE_R = 0.12        # corner radius as a fraction of the picture size; keep in sync with Portraits3D.lua
EDGE_COL = 3         # width of the see-through column, in pixels
px_ = (np.arange(n) + 0.5) / SS      # pixel coordinates at the high resolution
gx, gy = np.meshgrid(px_, px_)
R = EDGE_R * SIZE
keep = np.ones((n, n))
keep[gx < EDGE_COL] = 0
for cy in (R, SIZE - R):             # top-left and bottom-left corner circles
    corner = (gx < R) & ((gy < R) if cy == R else (gy > SIZE - R))
    keep[corner & (np.hypot(gx - R, gy - cy) > R)] = 0
ea = down(keep)
ep = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
ep[..., :3] = 255
ep[..., 3] = (np.clip(ea, 0, 1) * 255 + 0.5).astype(np.uint8)
open("Textures/RingCutEdge.tga", "wb").write(hdr + ep[..., [2, 1, 0, 3]].tobytes())
em = ep[:, ::-1, :]
open("Textures/RingCutEdgeMirror.tga", "wb").write(hdr + em[..., [2, 1, 0, 3]].tobytes())
