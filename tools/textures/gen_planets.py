"""
gen_planets.py - equirectangular planet textures for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/textures/gen_planets.py [names...] [--preview]
Output (assets/textures/planets/):
  terran.png (4096x2048, home world), desert.png, ice.png, jungle.png, volcanic.png (+ volcanic_emission.png),
  ocean.png, toxic.png, barren.png, gas_giant.png (2048x1024), clouds.png (4096x2048 RGBA, white + alpha)
All fields are evaluated on 3D unit directions -> seamless at the 180 deg meridian, no pole pinching.
Convention matches sphere_dirs(): longitude increases left->right, top row = north pole, +Y up.
"""
import math
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import (F32, Fractal3, smoothstep, srgb_from_linear, linear_from_srgb, save_rgb, save_rgba,
                      gradient_map)  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "planets")

SIZES = {"terran": (4096, 2048), "clouds": (4096, 2048)}
DEFAULT = (2048, 1024)


def c(*rgb_srgb):
    """sRGB colour (0..1) -> linear (so palettes can be authored in familiar sRGB values)."""
    return linear_from_srgb(np.array(rgb_srgb, F32))


def mix(a, b, t):
    t = np.asarray(t, F32)[..., None]
    return a * (1 - t) + b * t


def dirs_band(W, H, r0, r1):
    lon = (np.arange(W, dtype=np.float64) + 0.5) / W * 2.0 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(r0, r1, dtype=np.float64) + 0.5) / H * np.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    d = np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)], axis=-1).astype(F32)
    return d, lat.astype(F32), lon.astype(F32)


def warp(d, seed, freq, strength, octv=4):
    fx, fy, fz = Fractal3(seed), Fractal3(seed + 1), Fractal3(seed + 2)
    return d + strength * np.stack([fx.fbm(d, freq, octv), fy.fbm(d, freq, octv), fz.fbm(d, freq, octv)], -1)


# ------------------------------------------------------------------------------------------------
# planet types: f(d, lat, lon) -> (albedo_linear, emission_linear_or_None)
# ------------------------------------------------------------------------------------------------
def terran(d, lat, lon):
    q = warp(d, 101, 1.2, 0.28)
    h = Fractal3(110).fbm(q, 1.35, 9, gain=0.52)
    mtn = Fractal3(111).ridged(q, 3.2, 7, sharp=2.2)
    moist = Fractal3(112).fbm(warp(d, 120, 1.8, 0.2), 1.7, 6) * 0.5 + 0.5
    det = Fractal3(113).fbm(d, 24.0, 4) * 0.5 + 0.5
    sea = 0.06
    land = h > sea
    alat = np.abs(lat) / (np.pi / 2)
    # ocean
    depth = np.clip((sea - h) / 0.55, 0, 1)
    ocean = mix(c(0.10, 0.42, 0.55), c(0.03, 0.16, 0.36), smoothstep(0.0, 0.25, depth))
    ocean = mix(ocean, c(0.015, 0.07, 0.22), smoothstep(0.25, 1.0, depth))
    ocean = mix(ocean, c(0.28, 0.66, 0.70), smoothstep(0.025, 0.0, sea - h) * 0.65)  # reef / shallows
    # land biomes
    elev = np.clip((h - sea) / 0.6, 0, 1)
    dry = smoothstep(0.55, 0.30, moist) * smoothstep(0.10, 0.22, alat) * smoothstep(0.55, 0.38, alat)
    grass = mix(c(0.33, 0.52, 0.18), c(0.16, 0.36, 0.12), smoothstep(0.4, 0.75, moist))
    grass = mix(grass, c(0.82, 0.68, 0.42), dry)
    grass = mix(grass, c(0.58, 0.58, 0.48), smoothstep(0.55, 0.75, alat))          # tundra
    beach = smoothstep(0.03, 0.0, h - sea)
    grass = mix(grass, c(0.80, 0.74, 0.55), beach * 0.8)
    rock = mix(c(0.50, 0.42, 0.33), c(0.40, 0.36, 0.32), det)
    landc = mix(grass, rock, np.clip(smoothstep(0.25, 0.6, elev) * 0.7 + mtn * smoothstep(0.1, 0.5, elev) * 0.6, 0, 1))
    snow_line = 0.92 - 0.50 * alat
    landc = mix(landc, c(0.93, 0.94, 0.96), smoothstep(snow_line, snow_line + 0.12, elev + mtn * 0.25))
    landc *= (0.85 + 0.3 * det)[..., None]
    alb = np.where(land[..., None], landc, ocean)
    # polar ice caps (noisy edge), cover land and sea
    cap = smoothstep(0.80, 0.88, alat + 0.06 * Fractal3(114).fbm(d, 4.0, 5))
    alb = mix(alb, c(0.90, 0.94, 0.98) * (0.92 + 0.08 * det)[..., None], cap)
    return alb, None


def desert(d, lat, lon):
    q = warp(d, 201, 1.3, 0.32)
    region = Fractal3(209).fbm(q, 1.1, 5) * 0.5 + 0.5          # large provinces
    base = Fractal3(210).fbm(q, 2.2, 7) * 0.5 + 0.5
    dq = d * np.array([1.0, 3.5, 1.0], F32)
    dunes = Fractal3(211).ridged(warp(dq, 230, 1.6, 0.2), 9.0, 4, sharp=1.6)
    canyon = Fractal3(212).ridged(warp(d, 240, 1.8, 0.25), 2.2, 6, sharp=5.0)
    mesa = smoothstep(0.58, 0.64, Fractal3(216).fbm(q, 3.0, 6) * 0.5 + 0.5)
    det = Fractal3(213).fbm(d, 30.0, 3) * 0.5 + 0.5
    col = gradient_map(region, [(0.0, c(0.50, 0.24, 0.13)), (0.3, c(0.74, 0.42, 0.22)), (0.55, c(0.88, 0.62, 0.36)),
                                (0.75, c(0.93, 0.78, 0.56)), (1.0, c(0.80, 0.55, 0.32))])
    col *= (0.82 + 0.36 * base)[..., None]
    col = mix(col, c(0.97, 0.84, 0.60), dunes * 0.30 * smoothstep(0.45, 0.75, region))
    col = mix(col, c(0.62, 0.30, 0.17), mesa * 0.75)
    col = mix(col, c(0.30, 0.13, 0.07), smoothstep(0.5, 0.92, canyon) * 0.9)
    salt = smoothstep(0.83, 0.88, Fractal3(214).fbm(q, 2.0, 5) * 0.5 + 0.5)
    col = mix(col, c(0.95, 0.92, 0.86), salt * 0.85)
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.95, 0.93, 0.90), smoothstep(0.91, 0.96, alat + 0.03 * Fractal3(215).fbm(d, 5, 4)))
    return col * (0.9 + 0.2 * det)[..., None], None


def ice(d, lat, lon):
    q = warp(d, 301, 1.3, 0.35)
    region = Fractal3(309).fbm(q, 1.0, 5) * 0.5 + 0.5
    base = Fractal3(310).fbm(q, 2.4, 7) * 0.5 + 0.5
    crack_mask = smoothstep(0.45, 0.7, Fractal3(315).fbm(d, 1.6, 4) * 0.5 + 0.5)
    cracks = Fractal3(311).ridged(warp(d, 320, 2.0, 0.2), 3.5, 6, sharp=12.0)
    det = Fractal3(313).fbm(d, 26.0, 3) * 0.5 + 0.5
    col = gradient_map(region, [(0.0, c(0.18, 0.38, 0.60)), (0.28, c(0.42, 0.64, 0.84)), (0.5, c(0.78, 0.88, 0.96)),
                                (0.75, c(0.95, 0.98, 1.0)), (1.0, c(0.86, 0.93, 0.99))])
    col *= (0.88 + 0.22 * base)[..., None]
    col = mix(col, c(0.15, 0.40, 0.66), cracks * crack_mask * 0.8)
    rock = smoothstep(0.80, 0.86, Fractal3(314).fbm(q, 2.6, 6) * 0.5 + 0.5)
    col = mix(col, c(0.40, 0.40, 0.44), rock * 0.9)
    return col * (0.94 + 0.1 * det)[..., None], None


def jungle(d, lat, lon):
    q = warp(d, 401, 1.4, 0.3)
    h = Fractal3(410).fbm(q, 1.5, 8)
    veg = Fractal3(411).fbm(warp(d, 420, 2.0, 0.2), 2.4, 7) * 0.5 + 0.5
    rivers = Fractal3(412).ridged(warp(d, 430, 2.5, 0.25), 3.5, 5, sharp=9.0)
    det = Fractal3(413).fbm(d, 28.0, 4) * 0.5 + 0.5
    col = gradient_map(veg, [(0.0, c(0.06, 0.22, 0.08)), (0.3, c(0.12, 0.36, 0.10)), (0.55, c(0.26, 0.50, 0.12)),
                             (0.75, c(0.40, 0.58, 0.18)), (1.0, c(0.10, 0.30, 0.12))])
    mtn = Fractal3(414).ridged(q, 3.0, 6, sharp=2.5)
    col = mix(col, c(0.38, 0.36, 0.28), smoothstep(0.55, 0.85, mtn) * smoothstep(0.2, 0.6, h) * 0.8)
    col = mix(col, c(0.42, 0.48, 0.30), smoothstep(0.45, 0.75, h) * 0.6)       # highlands
    water = c(0.05, 0.25, 0.30)
    col = mix(col, water, smoothstep(0.55, 0.9, rivers) * smoothstep(0.6, 0.1, h))
    lakes = h < -0.35
    col = np.where(lakes[..., None], mix(c(0.06, 0.32, 0.36), c(0.03, 0.15, 0.25), smoothstep(-0.35, -0.7, h)), col)
    return col * (0.85 + 0.3 * det)[..., None], None


def volcanic(d, lat, lon):
    q = warp(d, 501, 1.6, 0.3)
    base = Fractal3(510).fbm(q, 1.7, 7) * 0.5 + 0.5
    lava = Fractal3(511).ridged(warp(d, 530, 2.2, 0.22), 3.2, 6, sharp=7.0)
    lava2 = Fractal3(512).ridged(q, 7.0, 4, sharp=10.0)
    det = Fractal3(513).fbm(d, 30.0, 4) * 0.5 + 0.5
    col = gradient_map(base, [(0.0, c(0.08, 0.07, 0.07)), (0.35, c(0.16, 0.13, 0.12)), (0.6, c(0.30, 0.25, 0.22)),
                              (0.8, c(0.38, 0.17, 0.10)), (1.0, c(0.22, 0.12, 0.09))])
    flow = np.clip(smoothstep(0.42, 0.85, lava) * 1.0 + smoothstep(0.65, 0.95, lava2) * 0.6 * smoothstep(0.35, 0.7, base), 0, 1)
    col = mix(col, c(0.45, 0.14, 0.04), flow)
    col *= (0.85 + 0.3 * det)[..., None]
    heat = flow ** 1.5 * (0.6 + 0.4 * (Fractal3(514).fbm(d, 12.0, 3) * 0.5 + 0.5))
    emis = gradient_map(heat, [(0.0, c(0, 0, 0)), (0.3, c(0.55, 0.08, 0.01)), (0.6, c(1.0, 0.35, 0.04)),
                               (1.0, c(1.0, 0.80, 0.30))])
    return col, emis


def ocean(d, lat, lon):
    q = warp(d, 601, 1.3, 0.3)
    h = Fractal3(610).fbm(q, 1.8, 9)
    det = Fractal3(611).fbm(d, 24.0, 3) * 0.5 + 0.5
    sea = 0.42
    depth = np.clip((sea - h) / 0.9, 0, 1)
    col = mix(c(0.10, 0.50, 0.62), c(0.04, 0.22, 0.48), smoothstep(0.0, 0.2, depth))
    col = mix(col, c(0.02, 0.09, 0.30), smoothstep(0.2, 1.0, depth))
    swirl = Fractal3(612).fbm(warp(d, 620, 3.0, 0.2), 5.0, 4) * 0.5 + 0.5
    col *= (0.88 + 0.24 * swirl)[..., None]
    island = h > sea
    land = mix(c(0.85, 0.78, 0.55), c(0.25, 0.55, 0.20), smoothstep(0.0, 0.06, h - sea))
    land = mix(land, c(0.45, 0.40, 0.32), smoothstep(0.15, 0.35, h - sea))
    col = mix(col, c(0.35, 0.80, 0.78), smoothstep(0.05, 0.0, sea - h) * 0.7)
    col = np.where(island[..., None], land * (0.85 + 0.3 * det)[..., None], col)
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.90, 0.95, 0.99), smoothstep(0.86, 0.92, alat + 0.05 * Fractal3(613).fbm(d, 4.0, 4)))
    return col, None


def toxic(d, lat, lon):
    q = warp(d, 701, 1.5, 0.35)
    h = Fractal3(710).fbm(q, 1.5, 8)
    sw = Fractal3(711).fbm(warp(d, 720, 2.5, 0.3), 3.0, 6) * 0.5 + 0.5
    det = Fractal3(712).fbm(d, 26.0, 4) * 0.5 + 0.5
    seas = h < -0.05
    sea = mix(c(0.55, 0.70, 0.12), c(0.30, 0.45, 0.08), smoothstep(-0.05, -0.6, h))
    sea = mix(sea, c(0.75, 0.88, 0.25), smoothstep(0.75, 0.95, sw) * 0.6)
    land = gradient_map(sw, [(0.0, c(0.40, 0.30, 0.10)), (0.4, c(0.62, 0.52, 0.16)), (0.7, c(0.70, 0.62, 0.22)),
                             (1.0, c(0.48, 0.40, 0.14))])
    pools = smoothstep(0.82, 0.9, Fractal3(713).fbm(q, 4.0, 5) * 0.5 + 0.5)
    land = mix(land, c(0.65, 0.90, 0.20), pools)
    col = np.where(seas[..., None], sea, land)
    return col * (0.88 + 0.24 * det)[..., None], None


def barren(d, lat, lon, H=1024, W=2048):
    q = warp(d, 801, 1.3, 0.2)
    base = Fractal3(810).fbm(q, 1.4, 8) * 0.5 + 0.5
    det = Fractal3(811).fbm(d, 32.0, 4) * 0.5 + 0.5
    col = gradient_map(base, [(0.0, c(0.30, 0.29, 0.29)), (0.35, c(0.45, 0.43, 0.41)), (0.65, c(0.60, 0.57, 0.53)),
                              (1.0, c(0.68, 0.65, 0.60))])
    maria = smoothstep(0.62, 0.70, Fractal3(812).fbm(warp(d, 830, 1.5, 0.3), 1.2, 5) * 0.5 + 0.5)
    col = mix(col, c(0.24, 0.23, 0.23), maria * 0.85)
    # craters
    rng = np.random.default_rng(840)
    ncr = 260
    v = rng.normal(size=(ncr, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    rad = np.radians(np.clip(rng.pareto(2.2, ncr) * 1.2 + 0.6, 0.6, 14.0))
    shade = np.zeros(d.shape[:-1], F32)
    for k in range(ncr):
        ang = np.arccos(np.clip((d * v[k].astype(F32)).sum(-1), -1, 1))
        u = ang / rad[k]
        m = u < 1.6
        if not m.any():
            continue
        bowl = -0.30 * smoothstep(1.0, 0.0, u)                # dark floor
        rim = 0.28 * np.exp(-((u - 1.0) / 0.12) ** 2)        # bright rim
        ray = 0.06 * smoothstep(1.6, 1.0, u)
        shade += np.where(m, bowl + rim + ray, 0)
    col = col * np.clip(1.0 + shade, 0.4, 1.5)[..., None]
    return col * (0.88 + 0.24 * det)[..., None], None


def gas_giant(d, lat, lon):
    q = d * np.array([1.0, 7.0, 1.0], F32)
    turb = Fractal3(910).fbm(warp(q, 920, 0.8, 0.35), 1.2, 6)
    turb2 = Fractal3(911).fbm(warp(d, 930, 3.0, 0.1), 6.0, 4)
    y = d[..., 1] + 0.035 * turb + 0.01 * turb2
    # storm oval
    sc = np.array([0.55, -0.32, -0.77], F32)
    sc /= np.linalg.norm(sc)
    ang = np.arccos(np.clip((d * sc).sum(-1), -1, 1))
    storm = np.exp(-(ang / 0.24) ** 2)
    y = y + 0.05 * storm * np.sin(ang * 40.0)
    bands = np.sin(y * 18.0) * 0.5 + 0.5
    bands2 = np.sin(y * 47.0 + 1.3) * 0.5 + 0.5
    t = np.clip(0.55 * bands + 0.30 * bands2 + 0.15 * (turb * 0.5 + 0.5), 0, 1)
    col = gradient_map(t, [(0.0, c(0.62, 0.36, 0.20)), (0.25, c(0.78, 0.58, 0.38)), (0.5, c(0.90, 0.82, 0.66)),
                           (0.75, c(0.95, 0.92, 0.85)), (1.0, c(0.74, 0.52, 0.34))])
    col = mix(col, c(0.80, 0.36, 0.20), smoothstep(0.35, 0.9, storm))
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.50, 0.42, 0.40), smoothstep(0.75, 1.0, alat) * 0.6)
    return col, None


def clouds(d, lat, lon):
    # cyclones: rotate the sample direction around a few centres
    rng = np.random.default_rng(990)
    q = d.copy()
    for k in range(5):
        cc = rng.normal(size=3).astype(F32)
        cc /= np.linalg.norm(cc)
        ang = np.arccos(np.clip((d * cc).sum(-1), -1, 1))
        w = (2.5 + rng.random() * 2.0) * np.exp(-(ang / (0.12 + 0.1 * rng.random())) ** 2) * (1 if k % 2 else -1)
        # rotate q around axis cc by angle w (Rodrigues)
        cosw, sinw = np.cos(w)[..., None], np.sin(w)[..., None]
        cr = np.cross(cc[None, None, :], q)
        dot = (q * cc).sum(-1, keepdims=True)
        q = q * cosw + cr * sinw + cc * dot * (1 - cosw)
    q = q * np.array([1.0, 1.6, 1.0], F32)             # slight east-west stretch
    q = warp(q, 1001, 1.5, 0.3)
    n = Fractal3(1010).fbm(q, 2.0, 8, gain=0.55) * 0.5 + 0.5
    alat = np.abs(lat) / (np.pi / 2)
    cover = 0.50 + 0.08 * np.cos(alat * np.pi * 3.0)    # cloud belts
    dens = smoothstep(cover - 0.02, cover + 0.30, n)
    wisp = Fractal3(1011).fbm(q, 9.0, 4) * 0.5 + 0.5
    dens = np.clip(dens * (0.75 + 0.5 * wisp), 0, 1)
    rgb = np.ones(d.shape, F32)
    return rgb, dens


TYPES = {"terran": terran, "desert": desert, "ice": ice, "jungle": jungle, "volcanic": volcanic, "ocean": ocean,
         "toxic": toxic, "barren": barren, "gas_giant": gas_giant, "clouds": clouds}


def work(args):
    name, W, H, r0, r1 = args
    d, lat, lon = dirs_band(W, H, r0, r1)
    alb, extra = TYPES[name](d, lat, lon)
    return r0, alb.astype(F32), None if extra is None else extra.astype(F32)


def build(name, preview=False):
    t0 = time.time()
    W, H = SIZES.get(name, DEFAULT)
    alb = np.zeros((H, W, 3), F32)
    extra = None
    step = 64
    jobs = [(name, W, H, r, min(H, r + step)) for r in range(0, H, step)]
    with Pool(4) as pool:
        for r0, a, e in pool.imap_unordered(work, jobs):
            alb[r0:r0 + a.shape[0]] = a
            if e is not None:
                if extra is None:
                    extra = np.zeros((H, W) + e.shape[2:], F32)
                extra[r0:r0 + e.shape[0]] = e
    os.makedirs(OUT, exist_ok=True)
    if name == "clouds":
        rgba = np.concatenate([np.ones((H, W, 3), F32), extra[..., None]], -1)
        save_rgba(os.path.join(OUT, "clouds.png"), rgba)
    else:
        save_rgb(os.path.join(OUT, name + ".png"), srgb_from_linear(alb))
        if extra is not None:
            save_rgb(os.path.join(OUT, name + "_emission.png"), srgb_from_linear(extra))
    print("%-10s %dx%d  %.1fs" % (name, W, H, time.time() - t0), flush=True)
    if preview:
        from PIL import Image
        pdir = os.path.join(ROOT, "tools", "textures", "previews")
        os.makedirs(pdir, exist_ok=True)
        fn = "clouds.png" if name == "clouds" else name + ".png"
        im = Image.open(os.path.join(OUT, fn))
        if name == "clouds":
            bg = Image.new("RGBA", im.size, (20, 40, 90, 255))
            bg.alpha_composite(im.convert("RGBA"))
            im = bg
        im.convert("RGB").resize((512, 256), Image.LANCZOS).save(os.path.join(pdir, "planet_%s.png" % name))


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(TYPES)
    for nm in names:
        build(nm, "--preview" in sys.argv)
