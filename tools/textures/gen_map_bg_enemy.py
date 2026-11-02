"""
gen_map_bg_enemy.py - background for the 2D map of the hostile ENEMY star system (2560x1440).
Run:  /opt/tools/venv/bin/python tools/textures/gen_map_bg_enemy.py
Output: assets/textures/map/map_background_enemy.png  (+ preview tools/textures/previews/map_bg_enemy_small.png)
Deep red-black / violet base, fine crimson-violet nebula wisps around the edges, crisp stars (same star renderer
as gen_map_bg.py, different seed). The centre (where the game draws the enemy star and its orbits) stays calm;
the bottom-right corner carries a faint warm golden glow - the direction of the player's home star.
"""
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import F32, Fractal3, smoothstep, srgb_from_linear, save_rgb  # noqa: E402
import gen_map_bg  # noqa: E402  (star renderer, W/H = 2560x1440)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "map", "map_background_enemy.png")
W, H = gen_map_bg.W, gen_map_bg.H
SEED = 6620


def band(args):
    r0, r1 = args
    ys = (np.arange(r0, r1, dtype=F32) + 0.5) / H
    xs = (np.arange(W, dtype=F32) + 0.5) / W
    X, Y = np.meshgrid(xs * (W / H), ys)      # aspect-correct coordinates, y down
    p = np.stack([X, Y, np.full_like(X, 0.377)], -1)
    out = np.zeros(X.shape + (3,), F32)
    f = [Fractal3(SEED + k) for k in range(10)]
    # base: deep red-black / violet with large faint variation
    g = f[0].fbm(p, 1.2, 4) * 0.5 + 0.5
    hue = f[9].fbm(p, 0.8, 3) * 0.5 + 0.5
    base_col = np.array([0.80, 0.14, 0.30], F32)[None, None, :] * (1 - hue[..., None]) + \
        np.array([0.42, 0.12, 0.80], F32)[None, None, :] * hue[..., None]
    out += (0.0020 + 0.0032 * g ** 2)[..., None] * base_col
    # calm zone around the map centre (enemy star)
    cx, cy = (W / H) * 0.5, 0.5
    dc = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
    calm = smoothstep(0.20, 0.78, dc)
    # fine nebula: warped density + bright filaments
    q = p + 0.25 * np.stack([f[1].fbm(p, 2.0, 4), f[2].fbm(p, 2.0, 4), np.zeros_like(X)], -1)
    dens = smoothstep(0.35, 0.95, f[3].fbm(q, 2.8, 7) * 0.5 + 0.5)
    fil = f[4].ridged(q, 4.5, 6, sharp=3.2)
    dark = 1.0 - 0.6 * smoothstep(0.58, 0.85, f[8].fbm(q, 6.0, 4) * 0.5 + 0.5)      # dust globules
    neb = (0.45 * dens + 0.95 * dens * fil) * dark
    # top-left: crimson
    d1 = np.sqrt((X - 0.20) ** 2 + (Y - 0.18) ** 2)
    out += (0.080 * np.exp(-(d1 / 0.46) ** 2) * neb)[..., None] * np.array([0.85, 0.10, 0.16], F32)
    # top-right: violet
    d2 = np.sqrt((X - (W / H - 0.30)) ** 2 + (Y - 0.12) ** 2)
    out += (0.060 * np.exp(-(d2 / 0.42) ** 2) * neb)[..., None] * np.array([0.48, 0.12, 0.86], F32)
    # bottom-left: magenta-red
    d3 = np.sqrt((X - 0.35) ** 2 + (Y - 0.92) ** 2)
    out += (0.050 * np.exp(-(d3 / 0.40) ** 2) * neb)[..., None] * np.array([0.80, 0.12, 0.42], F32)
    # faint reddish haze across the whole map except the calm centre
    haze = smoothstep(0.45, 0.9, f[5].fbm(q, 1.6, 5) * 0.5 + 0.5)
    out += (0.011 * haze * calm)[..., None] * np.array([0.75, 0.16, 0.40], F32)
    # bottom-right corner: faint warm golden glow towards the player's home star
    dbr = np.sqrt((X - (W / H + 0.05)) ** 2 + (Y - 1.06) ** 2)
    glow = np.exp(-(dbr / 0.42) ** 2) * 0.024 + np.exp(-(dbr / 0.16) ** 2) * 0.018
    wisp = 0.65 + 0.35 * (f[6].fbm(q, 3.0, 5) * 0.5 + 0.5)
    out += (glow * wisp)[..., None] * np.array([1.0, 0.60, 0.20], F32)
    return r0, out


def main():
    t0 = time.time()
    img = np.zeros((H, W, 3), F32)
    bands = [(r, min(H, r + 96)) for r in range(0, H, 96)]
    with Pool(4) as pool:
        for r0, part in pool.imap_unordered(band, bands):
            img[r0:r0 + part.shape[0]] = part
    rng = np.random.default_rng(SEED)
    img += gen_map_bg.stars(rng)
    img = img / (1.0 + 0.25 * img)
    srgb = srgb_from_linear(img)
    lum = srgb.mean(-1, keepdims=True)
    dn = (rng.random(srgb.shape, dtype=F32) - rng.random(srgb.shape, dtype=F32)) / 255.0
    srgb = srgb + dn * smoothstep(0.03, 0.12, lum)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    save_rgb(OUT, srgb)
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6), "%.1fs" % (time.time() - t0))
    from PIL import Image
    pdir = os.path.join(ROOT, "tools", "textures", "previews")
    os.makedirs(pdir, exist_ok=True)
    Image.open(OUT).resize((1280, 720), Image.LANCZOS).save(os.path.join(pdir, "map_bg_enemy_small.png"))


if __name__ == "__main__":
    main()
