"""
gen_sky.py - procedural equirectangular space panoramas for Starfighter Defense.

Usage:  python gen_sky.py [a|b|both] [--preview]
Writes  assets/textures/sky/space_panorama.png   (variant a: teal / violet / amber nebulae)
        assets/textures/sky/space_panorama_b.png (variant b: blue / magenta / cyan nebulae)

Everything is evaluated from 3D unit direction vectors, so the image is seamless at the
left/right edge and has no pinching at the poles. Stars are splatted with their exact angular
distance (2x supersampled, then box filtered) so they stay round and crisp everywhere.
Work happens in linear light; conversion to sRGB at the end.
"""
import os
import sys
import time
import numpy as np
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import (F32, Fractal3, sphere_dirs, smoothstep, srgb_from_linear, box_down,
                      save_rgb, random_rotation)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "sky")

W, H = 4096, 2048
SS = 2  # star supersampling

VARIANTS = {
    "a": dict(
        seed=1701,
        out="space_panorama.png",
        # (center lon deg, center lat deg, radius deg, inner rgb, outer rgb, strength)
        nebulae=[
            (-35, 18, 48, (0.10, 0.55, 0.62), (0.05, 0.16, 0.38), 1.00),   # teal
            (120, -22, 55, (0.55, 0.22, 0.85), (0.20, 0.06, 0.42), 0.95),  # violet
            (-150, 40, 36, (0.95, 0.48, 0.16), (0.45, 0.10, 0.12), 0.70),  # amber
        ],
        band_tint=(1.0, 0.92, 0.82),
        bg_tint=(0.35, 0.45, 0.75),
    ),
    "b": dict(
        seed=4242,
        out="space_panorama_b.png",
        nebulae=[
            (60, 25, 52, (0.18, 0.36, 0.95), (0.06, 0.08, 0.40), 1.00),    # blue
            (-100, -15, 50, (0.85, 0.16, 0.62), (0.30, 0.05, 0.35), 0.95),  # magenta
            (170, -45, 34, (0.25, 0.85, 0.90), (0.05, 0.25, 0.40), 0.65),  # cyan
        ],
        band_tint=(0.88, 0.92, 1.0),
        bg_tint=(0.45, 0.35, 0.70),
    ),
}


def lonlat_to_dir(lon_deg, lat_deg):
    lon = np.radians(lon_deg)
    lat = np.radians(lat_deg)
    return np.array([np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)], dtype=F32)


# ---------------------------------------------------------------------------------------------
# Diffuse layers (nebulae, milky way band, background glow), computed in row bands in parallel
# ---------------------------------------------------------------------------------------------
_CFG = None


def _init(cfg):
    global _CFG
    _CFG = cfg


def diffuse_band(args):
    r0, r1 = args
    cfg = _CFG
    seed = cfg["seed"]
    lon = (np.arange(W, dtype=np.float64) + 0.5) / W * 2.0 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(r0, r1, dtype=np.float64) + 0.5) / H * np.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    d = np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)], axis=-1).astype(F32)
    rng = np.random.default_rng(seed)
    gal_n = cfg["gal_n"]
    gal_c = cfg["gal_c"]

    fr = [Fractal3(seed + k * 31) for k in range(10)]
    out = np.zeros(d.shape, dtype=F32)

    # --- faint large scale background glow so space is not a dead flat black
    g = fr[0].fbm(d, 1.3, 4) * 0.5 + 0.5
    bg = (0.0005 + 0.0012 * g ** 2)[..., None] * np.array(cfg["bg_tint"], F32)
    out += bg

    # --- milky way band
    b = np.arcsin(np.clip((d * gal_n).sum(-1), -1, 1))           # galactic latitude
    core = np.clip((d * gal_c).sum(-1), -1, 1)
    core_w = np.exp(-((np.arccos(core)) / 0.75) ** 2)              # bulge around galactic centre
    # perturb latitude for an irregular band edge
    wob = fr[1].fbm(d, 2.2, 5) * 0.07
    band = np.exp(-((b + wob) / (0.12 + 0.08 * core_w)) ** 2)
    mott = fr[2].fbm(d, 6.0, 6) * 0.5 + 0.5
    mott2 = fr[3].fbm(d, 18.0, 4) * 0.5 + 0.5
    band_i = band * (0.25 + 0.75 * mott ** 1.5) * (0.6 + 0.4 * mott2) * (0.55 + 1.1 * core_w)
    # dust lanes: ridged noise darkening close to the plane
    lanes = fr[4].ridged(d, 4.0, 6, sharp=3.0)
    lane_mask = np.exp(-((b - 0.02 + fr[5].fbm(d, 3.0, 4) * 0.05) / 0.09) ** 2)
    dust = 1.0 - np.clip(lanes * 1.3 * lane_mask, 0, 0.92)
    band_col = np.array(cfg["band_tint"], F32)
    core_col = np.array((1.0, 0.78, 0.55), F32)
    bc = band_col[None, None, :] * (1 - core_w[..., None]) + core_col[None, None, :] * core_w[..., None]
    out += (0.040 * band_i * dust)[..., None] * bc

    # --- nebulae
    for i, (lon, lat, rad, cin, cout, strength) in enumerate(cfg["nebulae"]):
        c = lonlat_to_dir(lon, lat)
        ang = np.arccos(np.clip((d * c).sum(-1), -1, 1))
        fa = Fractal3(seed + 101 + i * 17)
        fb = Fractal3(seed + 202 + i * 17)
        fc = Fractal3(seed + 303 + i * 17)
        # domain warp for wispy structure
        q = d * 1.0
        q = q + 0.35 * np.stack([fa.fbm(d, 2.0, 4), fb.fbm(d, 2.0, 4), fc.fbm(d, 2.0, 4)], -1)
        edge = np.radians(rad) * (1.0 + 0.45 * fa.fbm(q, 1.6, 4))
        mask = np.exp(-(ang / np.maximum(edge, 1e-3)) ** 2 * 1.15)
        dens = fb.fbm(q, 3.5, 7) * 0.5 + 0.5
        dens = smoothstep(0.30, 0.92, dens) ** 1.3
        fil = fc.ridged(q, 5.0, 6, sharp=4.0)          # bright filaments
        dark = Fractal3(seed + 404 + i).fbm(q, 7.0, 5) * 0.5 + 0.5
        dark = 1.0 - 0.75 * smoothstep(0.55, 0.85, dark)   # dark globules/dust
        mixv = np.clip(Fractal3(seed + 505 + i).fbm(q, 2.5, 4) * 0.6 + 0.5, 0, 1)
        col = np.array(cin, F32)[None, None, :] * mixv[..., None] + np.array(cout, F32)[None, None, :] * (1 - mixv[..., None])
        inten = mask * (0.55 * dens + 0.45 * dens * fil * 2.2) * dark
        # soft glow halo around the nebula body
        inten = inten + 0.18 * mask ** 2.5 * (0.5 + 0.5 * dens)
        out += (0.10 * strength * inten)[..., None] * col

    # --- very faint unresolved star haze following the band (adds depth)
    haze = (fr[6].fbm(d, 40.0, 3) * 0.5 + 0.5) ** 4
    out += (0.004 * haze * (0.15 + band))[..., None] * np.array((0.9, 0.9, 1.0), F32)
    return r0, out.astype(F32)


# ---------------------------------------------------------------------------------------------
# Stars
# ---------------------------------------------------------------------------------------------
def temperature_rgb(t):
    """Approximate blackbody colour (linear RGB, normalised to max=1) for temperature t (K)."""
    t = np.asarray(t, dtype=np.float64) / 100.0
    r = np.where(t <= 66, 255.0, 329.698727446 * np.power(np.maximum(t - 60, 1e-6), -0.1332047592))
    g = np.where(t <= 66, 99.4708025861 * np.log(np.maximum(t, 1e-6)) - 161.1195681661,
                 288.1221695283 * np.power(np.maximum(t - 60, 1e-6), -0.0755148492))
    b = np.where(t >= 66, 255.0, np.where(t <= 19, 0.0,
                 138.5177312231 * np.log(np.maximum(t - 10, 1e-6)) - 305.0447927307))
    rgb = np.stack([r, g, b], -1).clip(0, 255) / 255.0
    rgb = rgb ** 2.2  # to linear-ish
    return rgb / rgb.max(-1, keepdims=True)


def render_stars(cfg, rng):
    Ws, Hs = W * SS, H * SS
    buf = np.zeros((Hs, Ws, 3), dtype=F32)
    n_field = 70000
    n_band = 38000
    # uniform directions
    v = rng.normal(size=(n_field, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    # band directions: sample around the galactic plane, concentrated toward the core
    gal_n, gal_c = cfg["gal_n"].astype(np.float64), cfg["gal_c"].astype(np.float64)
    gal_e = np.cross(gal_n, gal_c)
    lon_g = rng.normal(0, 1.2, n_band) + rng.choice([0, np.pi], n_band, p=[0.65, 0.35])
    lat_g = rng.normal(0, 0.09, n_band) * (1.0 + 0.8 * rng.random(n_band))
    vb = (np.cos(lat_g)[:, None] * (np.cos(lon_g)[:, None] * gal_c + np.sin(lon_g)[:, None] * gal_e)
          + np.sin(lat_g)[:, None] * gal_n)
    dirs = np.concatenate([v, vb], 0)
    n = len(dirs)
    # brightness: power law, band stars slightly dimmer on average
    u = rng.random(n)
    bright = 0.020 * u ** (-1.0 / 1.75)
    bright[n_field:] *= 0.75
    bright = np.minimum(bright, 6.0)
    # colours
    tsel = rng.random(n)
    temp = np.where(tsel < 0.55, rng.uniform(5200, 6800, n),
           np.where(tsel < 0.78, rng.uniform(6800, 14000, n),
           np.where(tsel < 0.95, rng.uniform(3800, 5200, n), rng.uniform(2900, 3800, n))))
    col = temperature_rgb(temp)
    col = 0.55 * col + 0.45  # stars look pale-tinted, not saturated
    col /= col.max(-1, keepdims=True)

    delta = np.pi / Hs                 # angular size of one supersampled pixel (rad)
    sig0 = 0.42 * SS * delta           # core sigma in rad (~0.42 final texel)
    lon = np.arctan2(dirs[:, 0], -dirs[:, 2])
    lat = np.arcsin(np.clip(dirs[:, 1], -1, 1))
    order = np.argsort(bright)         # dim first

    def splat(i, sigma, amp, colr, rad_mult=3.5):
        r_ang = sigma * rad_mult
        la, lo = lat[i], lon[i]
        row_c = (np.pi / 2 - la) / np.pi * Hs - 0.5
        rr = int(np.ceil(r_ang / delta)) + 1
        r0 = max(0, int(np.floor(row_c)) - rr)
        r1 = min(Hs, int(np.ceil(row_c)) + rr + 1)
        lat_max = min(np.pi / 2, abs(la) + r_ang)
        cosm = max(np.cos(lat_max), 1e-4)
        cr = int(np.ceil(r_ang / (delta * 2.0 * cosm / 2.0) / 1.0)) + 1  # columns span 2pi/Ws each
        col_c = (lo + np.pi) / (2 * np.pi) * Ws - 0.5
        if 2 * cr + 1 >= Ws:
            cols = np.arange(Ws)
        else:
            cols = np.arange(int(np.floor(col_c)) - cr, int(np.ceil(col_c)) + cr + 1) % Ws
        rows = np.arange(r0, r1)
        plat = np.pi / 2 - (rows + 0.5) / Hs * np.pi
        plon = (cols + 0.5) / Ws * 2 * np.pi - np.pi
        cl = np.cos(plat)[:, None]
        px = cl * np.sin(plon)[None, :]
        py = np.sin(plat)[:, None] * np.ones((1, len(cols)))
        pz = -cl * np.cos(plon)[None, :]
        dx = px - dirs[i, 0]
        dy = py - dirs[i, 1]
        dz = pz - dirs[i, 2]
        chord = np.sqrt(dx * dx + dy * dy + dz * dz)
        ang = 2.0 * np.arcsin(np.clip(chord / 2.0, 0, 1))
        val = amp * np.exp(-0.5 * (ang / sigma) ** 2)
        buf[rows[:, None], cols[None, :]] += (val[..., None] * colr[None, None, :]).astype(F32)

    t0 = time.time()
    for k, i in enumerate(order):
        b = bright[i]
        sig = sig0 * (1.0 + 0.35 * np.clip(np.log10(b / 0.05), 0, 2))
        # amplitude so that the integrated energy ~ brightness, but peak stays crisp
        splat(i, sig, b, col[i])
        if b > 0.35:  # soft halo for brighter stars
            splat(i, sig0 * (5.0 + 5.0 * min(b, 3.0)), 0.035 * b, col[i], rad_mult=3.0)
    print(f"  stars: {n} splats in {time.time() - t0:.1f}s")

    # subtle diffraction spikes for the very brightest few
    top = order[-14:]
    for i in top:
        b = bright[i]
        la, lo = lat[i], lon[i]
        row_c = (np.pi / 2 - la) / np.pi * Hs
        col_c = (lo + np.pi) / (2 * np.pi) * Ws
        cosl = max(np.cos(la), 0.05)
        L = int(18 * SS * min(b, 4.0) ** 0.6)
        tt = np.arange(-L, L + 1)
        fall = np.exp(-np.abs(tt) / (L * 0.28)) * 0.10 * b
        for ang in (0.0, np.pi / 2):
            dr = np.sin(ang) * tt
            dc = np.cos(ang) * tt / cosl
            rr = np.clip(np.round(row_c + dr).astype(int), 0, Hs - 1)
            cc = np.round(col_c + dc).astype(int) % Ws
            buf[rr, cc] += (fall[:, None] * col[i][None, :]).astype(F32)
    return buf


def build(variant, preview=False):
    cfg = dict(VARIANTS[variant])
    seed = cfg["seed"]
    rng = np.random.default_rng(seed)
    rot = random_rotation(rng)
    cfg["gal_n"] = (rot @ np.array([0.0, 1.0, 0.0], F32)).astype(F32)
    cfg["gal_c"] = (rot @ np.array([1.0, 0.0, 0.0], F32)).astype(F32)
    t0 = time.time()
    bands = [(r, min(H, r + 128)) for r in range(0, H, 128)]
    img = np.zeros((H, W, 3), dtype=F32)
    with Pool(4, initializer=_init, initargs=(cfg,)) as pool:
        for r0, part in pool.imap_unordered(diffuse_band, bands):
            img[r0:r0 + part.shape[0]] = part
    print(f"  diffuse layers: {time.time() - t0:.1f}s")
    stars = render_stars(cfg, rng)
    img += box_down(stars, SS)
    del stars
    # gentle filmic shoulder so bright cores do not clip harshly
    img = img / (1.0 + 0.25 * img)
    srgb = srgb_from_linear(img)
    # light dither only where there is structure (keeps black areas compressible)
    lum = srgb.mean(-1, keepdims=True)
    dn = (rng.random(srgb.shape, dtype=F32) - rng.random(srgb.shape, dtype=F32)) / 255.0
    srgb = srgb + dn * smoothstep(0.03, 0.12, lum)
    path = os.path.join(OUT_DIR, cfg["out"])
    save_rgb(path, srgb)
    print(f"  wrote {path} ({os.path.getsize(path) / 1e6:.1f} MB) in {time.time() - t0:.1f}s")
    if preview:
        from PIL import Image
        im = Image.open(path)
        pdir = os.path.join(ROOT, "tools", "textures", "previews")
        os.makedirs(pdir, exist_ok=True)
        im.resize((1024, 512), Image.LANCZOS).save(os.path.join(pdir, f"sky_{variant}_small.png"))
        # 1:1 crops: equator centre, seam (wrap) region, and near the pole
        w = 512
        im.crop((W // 2 - w // 2, H // 2 - w // 4, W // 2 + w // 2, H // 2 + w // 4)).save(
            os.path.join(pdir, f"sky_{variant}_crop_center.png"))
        seam = Image.new("RGB", (w, w // 2))
        seam.paste(im.crop((W - w // 2, H // 2 - w // 4, W, H // 2 + w // 4)), (0, 0))
        seam.paste(im.crop((0, H // 2 - w // 4, w // 2, H // 2 + w // 4)), (w // 2, 0))
        seam.save(os.path.join(pdir, f"sky_{variant}_crop_seam.png"))
        im.crop((W // 2 - w // 2, 0, W // 2 + w // 2, w // 2)).save(
            os.path.join(pdir, f"sky_{variant}_crop_pole.png"))


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    preview = "--preview" in sys.argv
    for v in (["a", "b"] if which == "both" else [which]):
        print("variant", v)
        build(v, preview)
