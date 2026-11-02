"""
gen_map_bg.py - background for the 2D solar-system map (2560x1440).
Run:  /opt/tools/venv/bin/python tools/textures/gen_map_bg.py
Output: assets/textures/map/map_background.png
Deep blue-black, fine faint nebula, crisp stars. The centre (where the game draws the sun and
the planet orbits) stays calm; the top-left corner (enemy-system jump point) gets a reddish-violet
nebula glow, the bottom-right a faint teal one for balance.
"""
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import F32, Fractal3, smoothstep, srgb_from_linear, save_rgb, box_down  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "map", "map_background.png")
W, H = 2560, 1440
SEED = 314


def band(args):
    r0, r1 = args
    ys = (np.arange(r0, r1, dtype=F32) + 0.5) / H
    xs = (np.arange(W, dtype=F32) + 0.5) / W
    X, Y = np.meshgrid(xs * (W / H), ys)      # aspect-correct coordinates, y down
    p = np.stack([X, Y, np.full_like(X, 0.123)], -1)
    out = np.zeros(X.shape + (3,), F32)
    f = [Fractal3(SEED + k) for k in range(8)]
    # base: deep blue-black gradient + large faint variation
    g = f[0].fbm(p, 1.2, 4) * 0.5 + 0.5
    out += (0.0020 + 0.0030 * g ** 2)[..., None] * np.array([0.30, 0.42, 0.95], F32)
    # distance from the map centre (sun) -> calm zone
    cx, cy = (W / H) * 0.5, 0.5
    dc = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
    calm = smoothstep(0.18, 0.75, dc)
    # nebula layers
    q = p + 0.25 * np.stack([f[1].fbm(p, 2.0, 4), f[2].fbm(p, 2.0, 4), np.zeros_like(X)], -1)
    dens = smoothstep(0.35, 0.95, f[3].fbm(q, 2.6, 7) * 0.5 + 0.5)
    fil = f[4].ridged(q, 4.0, 6, sharp=3.0)
    # top-left (enemy jump point) reddish violet
    dtl = np.sqrt((X - 0.18) ** 2 + (Y - 0.16) ** 2)
    m_tl = np.exp(-(dtl / 0.42) ** 2)
    col_tl = np.array([0.75, 0.16, 0.42], F32) * 0.6 + np.array([0.45, 0.12, 0.85], F32) * 0.4
    out += (0.085 * m_tl * (0.45 * dens + 0.9 * dens * fil))[..., None] * col_tl
    # bottom-right faint teal
    dbr = np.sqrt((X - (W / H - 0.25)) ** 2 + (Y - 0.85) ** 2)
    m_br = np.exp(-(dbr / 0.45) ** 2)
    out += (0.055 * m_br * (0.45 * dens + 0.8 * dens * fil))[..., None] * np.array([0.10, 0.55, 0.62], F32)
    # very faint blue haze across the whole map (except the calm centre)
    haze = smoothstep(0.45, 0.9, f[5].fbm(q, 1.6, 5) * 0.5 + 0.5)
    out += (0.012 * haze * calm)[..., None] * np.array([0.25, 0.35, 0.9], F32)
    return r0, out


def stars(rng):
    ss = 2
    Ws, Hs = W * ss, H * ss
    buf = np.zeros((Hs, Ws, 3), F32)
    n = 9000
    xs = rng.uniform(0, Ws, n)
    ys = rng.uniform(0, Hs, n)
    b = np.minimum(0.022 * rng.random(n) ** (-1 / 2.3), 0.9)  # few bright stars: must not look like planets
    tint = rng.random(n)
    cols = np.where(tint[:, None] < 0.6, [1.0, 0.97, 0.92], np.where(tint[:, None] < 0.85, [0.8, 0.88, 1.0],
                                                                   [1.0, 0.82, 0.62])).astype(F32)
    sig = 0.85 * ss * (1 + 0.3 * np.clip(np.log10(b / 0.05), 0, 2))
    for i in range(n):
        s = sig[i]
        R = int(np.ceil(s * 3.5))
        x0, y0 = int(xs[i]) - R, int(ys[i]) - R
        x1, y1 = int(xs[i]) + R + 1, int(ys[i]) + R + 1
        if x0 < 0 or y0 < 0 or x1 > Ws or y1 > Hs:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        v = b[i] * np.exp(-0.5 * ((xx + 0.5 - xs[i]) ** 2 + (yy + 0.5 - ys[i]) ** 2) / s ** 2)
        buf[y0:y1, x0:x1] += v[..., None] * cols[i]
        if b[i] > 0.7:
            s2 = s * 6
            R2 = int(np.ceil(s2 * 3))
            xa, ya = max(0, int(xs[i]) - R2), max(0, int(ys[i]) - R2)
            xb, yb = min(Ws, int(xs[i]) + R2 + 1), min(Hs, int(ys[i]) + R2 + 1)
            yy, xx = np.mgrid[ya:yb, xa:xb]
            v = 0.03 * b[i] * np.exp(-0.5 * ((xx + 0.5 - xs[i]) ** 2 + (yy + 0.5 - ys[i]) ** 2) / s2 ** 2)
            buf[ya:yb, xa:xb] += v[..., None] * cols[i]
    return box_down(buf, ss)


def main():
    t0 = time.time()
    img = np.zeros((H, W, 3), F32)
    bands = [(r, min(H, r + 96)) for r in range(0, H, 96)]
    with Pool(4) as pool:
        for r0, part in pool.imap_unordered(band, bands):
            img[r0:r0 + part.shape[0]] = part
    rng = np.random.default_rng(SEED)
    img += stars(rng)
    img = img / (1.0 + 0.25 * img)
    srgb = srgb_from_linear(img)
    lum = srgb.mean(-1, keepdims=True)
    dn = (rng.random(srgb.shape, dtype=F32) - rng.random(srgb.shape, dtype=F32)) / 255.0
    srgb = srgb + dn * smoothstep(0.03, 0.12, lum)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    save_rgb(OUT, srgb)
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6), "%.1fs" % (time.time() - t0))
    from PIL import Image
    Image.open(OUT).resize((1280, 720), Image.LANCZOS).save(
        os.path.join(ROOT, "tools", "textures", "previews", "map_bg_small.png"))


if __name__ == "__main__":
    main()
