"""
gen_fx.py - small effect textures for Starfighter Defense (numpy + Pillow).
Run:  /opt/tools/venv/bin/python tools/textures/gen_fx.py
Output (assets/textures/fx/): smoke_puff.png, glow.png, spark.png, flare.png, shockwave.png, noise.png
White sprites keep RGB = white and put the shape into alpha (straight alpha), so they can be tinted
freely in Godot (modulate / albedo colour, additive or mix blending).
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import F32, Fractal3, TilePerlin2, smoothstep  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FX = os.path.join(ROOT, "assets", "textures", "fx")


def grid(w, h=None):
    h = h or w
    x = (np.arange(w, dtype=F32) + 0.5) / w * 2 - 1
    y = (np.arange(h, dtype=F32) + 0.5) / h * 2 - 1
    return np.meshgrid(x, y)


def save_white(path, alpha):
    a = np.clip(alpha, 0, 1)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255 + 0.5).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)


def glow():
    X, Y = grid(256)
    r = np.sqrt(X * X + Y * Y)
    a = 0.62 * np.exp(-(r / 0.16) ** 2) + 0.30 * np.exp(-(r / 0.42) ** 2) + 0.08 * np.exp(-(r / 0.8) ** 2)
    a *= smoothstep(1.0, 0.82, r)
    save_white(os.path.join(FX, "glow.png"), a / a.max())


def spark():
    X, Y = grid(128, 32)
    # bright head at +x, tapering tail toward -x
    along = np.clip(1.0 - np.abs(X) ** 1.6, 0, 1) * (0.55 + 0.45 * (X * 0.5 + 0.5))
    width = 0.10 + 0.35 * np.clip(1 - np.abs(X), 0, 1)
    a = along * np.exp(-(Y / width) ** 2 * 2.2)
    core = np.exp(-(Y / 0.16) ** 2 * 3) * along ** 2
    save_white(os.path.join(FX, "spark.png"), np.clip(a * 0.8 + core * 0.5, 0, 1))


def flare():
    X, Y = grid(512)
    r = np.sqrt(X * X + Y * Y)
    ang = np.arctan2(Y, X)
    a = 0.75 * np.exp(-(r / 0.07) ** 2) + 0.22 * np.exp(-(r / 0.22) ** 2)
    # 4 main rays
    for th in (0.0, np.pi / 2):
        along = np.abs(X * np.cos(th) + Y * np.sin(th))
        perp = np.abs(-X * np.sin(th) + Y * np.cos(th))
        a += 0.9 * np.exp(-perp / (0.006 + 0.012 * along)) * np.exp(-along / 0.38)
    # 4 thinner diagonal rays
    for th in (np.pi / 4, 3 * np.pi / 4):
        along = np.abs(X * np.cos(th) + Y * np.sin(th))
        perp = np.abs(-X * np.sin(th) + Y * np.cos(th))
        a += 0.35 * np.exp(-perp / (0.004 + 0.008 * along)) * np.exp(-along / 0.22)
    # faint ring
    a += 0.06 * np.exp(-((r - 0.55) / 0.02) ** 2) * (0.6 + 0.4 * np.cos(ang * 6))
    a *= smoothstep(1.0, 0.9, r)
    save_white(os.path.join(FX, "flare.png"), np.clip(a, 0, 1))


def shockwave():
    X, Y = grid(512)
    r = np.sqrt(X * X + Y * Y)
    p = np.stack([X * 2.0, Y * 2.0, np.zeros_like(X)], -1)
    n = Fractal3(5).fbm(p, 2.0, 4) * 0.5 + 0.5
    ring_r = 0.80 + 0.025 * (n - 0.5)
    a = np.exp(-((r - ring_r) / 0.035) ** 2) * (0.75 + 0.5 * n)
    a += 0.55 * np.exp(-((r - ring_r + 0.02) / 0.09) ** 2) * (0.5 + 0.5 * n)   # soft inner glow
    a += 0.10 * smoothstep(0.82, 0.3, r) * (r / 0.8)                          # faint fill
    a *= smoothstep(1.0, 0.93, r)
    save_white(os.path.join(FX, "shockwave.png"), np.clip(a, 0, 1))


def smoke_puff():
    X, Y = grid(256)
    r = np.sqrt(X * X + Y * Y)
    p = np.stack([X * 1.6, Y * 1.6, np.full_like(X, 0.37)], -1)
    fa, fb, fc = Fractal3(71), Fractal3(72), Fractal3(73)
    q = p + 0.35 * np.stack([fa.fbm(p, 1.5, 4), fb.fbm(p, 1.5, 4), np.zeros_like(X)], -1)
    n = fc.fbm(q, 2.2, 6) * 0.5 + 0.5
    edge = 0.78 + 0.25 * (n - 0.5)
    dens = smoothstep(edge, edge - 0.45, r) * (0.35 + 0.9 * n)
    dens = np.clip(dens, 0, 1) ** 1.2
    # fake lighting from the noise gradient (light from top-left)
    nl = fc.fbm(q, 2.2, 3) * 0.5 + 0.5          # smoother field for the lighting
    gy, gx = np.gradient(nl)
    lit = np.clip(0.75 + (-gx * 0.7 - gy * 0.7) * 9.0, 0.5, 1.0)
    shade = (0.62 + 0.38 * lit) * (0.85 + 0.15 * (1 - r))
    rgba = np.zeros((256, 256, 4), F32)
    rgba[..., 0] = shade * 0.94
    rgba[..., 1] = shade * 0.94
    rgba[..., 2] = shade * 0.96
    rgba[..., 3] = dens
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(FX, "smoke_puff.png"), optimize=True)


def noise_tile():
    n = TilePerlin2(seed=99).fbm(512, 512, base_period=4, octaves=7, gain=0.52)
    n = np.clip(n * 0.5 + 0.5, 0, 1)
    n = (n - n.min()) / (n.max() - n.min())
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(FX, "noise.png"), optimize=True)


if __name__ == "__main__":
    os.makedirs(FX, exist_ok=True)
    for fn in (glow, spark, flare, shockwave, smoke_puff, noise_tile):
        fn()
        print("done", fn.__name__)
    # preview sheet on dark background
    pdir = os.path.join(ROOT, "tools", "textures", "previews")
    os.makedirs(pdir, exist_ok=True)
    names = ["glow.png", "spark.png", "flare.png", "shockwave.png", "smoke_puff.png", "noise.png"]
    sheet = Image.new("RGBA", (256 * len(names), 256), (30, 32, 42, 255))
    for i, nm in enumerate(names):
        im = Image.open(os.path.join(FX, nm)).convert("RGBA")
        im.thumbnail((256, 256))
        sheet.alpha_composite(im, (i * 256 + (256 - im.width) // 2, (256 - im.height) // 2))
    sheet.save(os.path.join(pdir, "fx_sheet.png"))
