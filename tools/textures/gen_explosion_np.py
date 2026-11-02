"""
gen_explosion_np.py - explosion flipbook via a small numpy volume ray-marcher.

(The Cycles volume version in tools/blender/gen_explosion.py works too but needs ~45 s/frame on
this CPU and the denoiser washes out the billows; this renderer is ~50x faster and crisper.)

Run:  /opt/tools/venv/bin/python tools/textures/gen_explosion_np.py [--test]
Output: assets/textures/fx/explosion_flipbook.png  (8x8 frames x 256 px, row-major from top-left,
        straight alpha; frame 0 = ignition flash ... frame 63 = fully faded smoke)

Model: a spherical fireball whose surface is displaced by two noise octaves (features scale with the
radius, slowly rotating -> feels like advection), fine wisps modulate density, temperature is high in
the core early and decays; colour from a stylised blackbody ramp; smoke lit by an ambient term, a
top-left key light and the glow of the fire.
"""
import os
import sys
import time
from multiprocessing import Pool

import numpy as np
from scipy.ndimage import map_coordinates

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import F32, Fractal3, smoothstep  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "fx", "explosion_flipbook.png")
FRAMES = 64
RES = 256
STEPS = 110
EXT = 1.6  # noise volume half extent
VOL = {}


def build_volumes():
    vols = {}
    for name, (g, freq, octv, seed) in {"n1": (72, 1.1, 4, 11), "n2": (96, 2.6, 4, 22), "n3": (128, 6.0, 3, 33)}.items():
        ax = np.linspace(-EXT, EXT, g, dtype=F32)
        p = np.stack(np.meshgrid(ax, ax, ax, indexing="ij"), -1)
        vols[name] = Fractal3(seed).fbm(p, freq, octv).astype(F32)
    return vols


def sample(vol, q):
    g = vol.shape[0]
    idx = (q + EXT) / (2 * EXT) * (g - 1)
    return map_coordinates(vol, [idx[..., 0].ravel(), idx[..., 1].ravel(), idx[..., 2].ravel()], order=1,
                           mode="mirror").reshape(q.shape[:-1])


def ramp(tmp):
    """Stylised blackbody ramp, tmp in [0,1] -> linear rgb (can exceed 1 for the hottest part)."""
    stops = np.array([0.0, 0.12, 0.28, 0.45, 0.62, 0.80, 1.0], F32)
    cols = np.array([[0.0, 0.0, 0.0], [0.35, 0.03, 0.01], [0.95, 0.16, 0.02], [1.6, 0.55, 0.08],
                     [2.4, 1.25, 0.30], [3.2, 2.5, 1.2], [4.0, 3.8, 3.2]], F32)
    out = np.empty(tmp.shape + (3,), F32)
    for c in range(3):
        out[..., c] = np.interp(tmp, stops, cols[:, c])
    return out


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], F32)


def params(t):
    return dict(
        R=0.13 + 0.70 * (1.0 - (1.0 - t) ** 3.0),       # radius: fast burst then slow drift
        A1=0.34 + 0.20 * t,                               # large lobe displacement
        A2=0.19 + 0.10 * t,                               # billows
        dens=32.0 * (1.0 - t) ** 1.7 + 1.6,               # optical density
        heat=max(0.0, 1.0 - t / 0.58) ** 1.15,            # fire temperature factor
        emis=2.7 + 4.0 * max(0.0, 1.0 - t / 0.06),        # emission gain (extra flash at start)
        hollow=0.65 * smoothstep(0.25, 0.9, t),           # thinning core -> smoke shell
        fade=1.0 if t < 0.72 else max(0.0, 1.0 - (t - 0.72) / 0.28) ** 1.4,
        rot=0.9 * t,
        drift=np.array([0.10, -0.06, 0.08], F32) * t * 3.0,
    )


def render_frame(f):
    v = VOL
    t = f / (FRAMES - 1)
    P = params(t)
    R = P["R"]
    ax = (np.arange(RES, dtype=F32) + 0.5) / RES * 2.1 - 1.05
    X, Y = np.meshgrid(ax, -ax)                     # image y up
    zs = np.linspace(-1.05, 1.05, STEPS, dtype=F32)
    dt = F32(zs[1] - zs[0])
    trans = np.ones((RES, RES), F32)
    col = np.zeros((RES, RES, 3), F32)
    M = rot_y(P["rot"])
    L = np.array([-0.55, 0.65, -0.52], F32)
    L /= np.linalg.norm(L)
    smoke_base = np.array([0.105, 0.098, 0.092], F32)
    for z in zs:  # front (camera at -z) to back
        p = np.stack([X, Y, np.full_like(X, z)], -1)
        r = np.sqrt((p * p).sum(-1)) + 1e-6
        u = r / R
        active = u < 1.9
        if not active.any():
            continue
        q = (p / max(R, 0.25) * 0.85) @ M.T + P["drift"]
        n1 = sample(v["n1"], q)
        n2 = sample(v["n2"], q)
        n3 = sample(v["n3"], q * 1.3)
        d = P["A1"] * n1 + P["A2"] * n2
        shape = 1.0 + d - u
        dens = smoothstep(0.0, 0.10, shape) * (0.22 + 1.35 * np.clip(n3 * 0.5 + 0.55, 0, 1) ** 1.6)
        dens *= 1.0 - P["hollow"] * smoothstep(0.75, 0.0, u)
        dens *= P["dens"]
        # temperature: core hot, noisy pockets
        tmp = P["heat"] * np.clip(1.35 - u * (0.35 + 1.15 * t) + 0.45 * n2 + 0.25 * n3, 0, 1.2)
        tmp = np.clip(tmp, 0, 1)
        emit = ramp(tmp) * (P["emis"] * tmp ** 1.3)[..., None]
        # smoke lighting: ambient + key light (spherical approx with displaced normal) + fire glow
        nrm = p / r[..., None]
        lam = np.clip((nrm * L).sum(-1) * 0.5 + 0.5 + 0.25 * n2, 0, 1)
        fire = P["heat"] * np.exp(-np.maximum(u - 0.2, 0) * 2.5) * 1.4
        light = 0.10 + 0.55 * lam ** 1.5
        smoke = smoke_base[None, None, :] * light[..., None] + np.array([1.0, 0.38, 0.10], F32) * (fire * 0.45)[..., None]
        a = 1.0 - np.exp(-dens * dt)
        col += (trans * a)[..., None] * (smoke + emit)
        trans *= 1.0 - a
    alpha = (1.0 - trans) * P["fade"]
    # soft circular vignette so nothing touches the frame border
    rr = np.sqrt(X * X + Y * Y)
    alpha *= np.clip((1.04 - rr) / 0.08, 0, 1)
    prem = col * P["fade"]
    # tone map premultiplied colour (soft shoulder), then un-premultiply for straight alpha
    prem = prem / (1.0 + 0.18 * prem)
    straight = np.where(alpha[..., None] > 1e-4, prem / np.maximum(alpha[..., None], 1e-4), 0)
    straight = np.clip(straight, 0, 1)
    srgb = np.where(straight <= 0.0031308, 12.92 * straight, 1.055 * np.power(straight, 1 / 2.4) - 0.055)
    rgba = np.concatenate([srgb, alpha[..., None]], -1)
    return f, (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)


def _init(vols):
    global VOL
    VOL = vols


def main(test=False):
    from PIL import Image
    t0 = time.time()
    vols = build_volumes()
    print("volumes %.1fs" % (time.time() - t0))
    frames = [1, 8, 18, 30, 44, 58] if test else list(range(FRAMES))
    out = {}
    with Pool(4, initializer=_init, initargs=(vols,)) as pool:
        for f, img in pool.imap_unordered(render_frame, frames):
            out[f] = img
    print("rendered %d frames in %.1fs" % (len(frames), time.time() - t0))
    pdir = os.path.join(ROOT, "tools", "textures", "previews")
    os.makedirs(pdir, exist_ok=True)
    if test:
        sheet = Image.new("RGBA", (RES * len(frames), RES), (35, 38, 48, 255))
        for i, f in enumerate(frames):
            sheet.alpha_composite(Image.fromarray(out[f], "RGBA"), (i * RES, 0))
        sheet.save(os.path.join(pdir, "explosion_np_test.png"))
        return
    atlas = Image.new("RGBA", (RES * 8, RES * 8), (0, 0, 0, 0))
    for f in range(FRAMES):
        atlas.paste(Image.fromarray(out[f], "RGBA"), ((f % 8) * RES, (f // 8) * RES))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT, optimize=True)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")
    bg = Image.new("RGBA", atlas.size, (35, 38, 48, 255))
    bg.alpha_composite(atlas)
    bg.resize((1024, 1024)).save(os.path.join(pdir, "explosion_atlas_preview.png"))


if __name__ == "__main__":
    main("--test" in sys.argv)
