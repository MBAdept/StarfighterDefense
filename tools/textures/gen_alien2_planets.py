"""
gen_alien2_planets.py - equirectangular textures for the planets of the SECOND hostile star system "Ixmora"
(blue giant star, cold light). Same conventions and helpers as gen_alien_planets.py.
Run:  /opt/tools/venv/bin/python tools/textures/gen_alien2_planets.py [names...] [--preview]
Output (assets/textures/planets/, 2048x1024 RGB, sRGB):
  alien_glacier.png                          pale lilac ice sheets, dark rock ridges, blue-black crevasse networks,
                                             glossy frozen methane lakes
  alien_magma.png  + alien_magma_emission.png    near-black basalt plates, glowing rifts, magma seas under a thin crust
  alien_bloom.png  + alien_bloom_emission.png    dark teal bioluminescent forests with glowing colonies, inky seas with
                                             luminous plankton swirls
  alien_void.png   + alien_void_emission.png     home world: indigo obsidian continents, deep blue seas, megastructures
                                             with cyan / violet light networks
"""
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import F32, Fractal3, smoothstep, srgb_from_linear, save_rgb, gradient_map, random_rotation  # noqa: E402
from gen_alien_planets import (c, mix, warp, nrm, seeds, voronoi, voronoi_full, pair_rand, cell_rand,  # noqa: E402
                               grid_dist, ring_dist, line_mask, halo, relief, dirs_band, W, H, OUT, PREV)


# ------------------------------------------------------------------------------------------------
# glacier world
# ------------------------------------------------------------------------------------------------
def glacier_h(d, parts=False):
    q = warp(d, 2101, 1.3, 0.30)
    base = Fractal3(2110).fbm(q, 1.5, 8) * 0.5 + 0.5
    ridge = Fractal3(2114).ridged(warp(d, 2140, 1.6, 0.25), 2.4, 7, sharp=3.0)
    rz = smoothstep(0.45, 0.70, Fractal3(2115).fbm(q, 1.2, 4) * 0.5 + 0.5)
    h = 0.6 * base + 0.6 * ridge ** 1.4 * rz
    if parts:
        return h, dict(base=base, ridge=ridge, rz=rz)
    return h


def alien_glacier(d, lat, lon):
    h, P = glacier_h(d, True)
    shade = relief(glacier_h, d, h, k=0.7)
    det = Fractal3(2113).fbm(d, 30.0, 4) * 0.5 + 0.5
    grain = Fractal3(2119).fbm(d, 110.0, 2) * 0.5 + 0.5
    # ice sheets: pale lilac-blue -> white
    t = np.clip(P["base"] * 0.9 + 0.1 * det, 0, 1)
    col = gradient_map(t, [(0.0, c(0.44, 0.48, 0.66)), (0.3, c(0.60, 0.64, 0.80)), (0.55, c(0.76, 0.79, 0.90)),
                           (0.8, c(0.88, 0.90, 0.97)), (1.0, c(0.80, 0.83, 0.93))])
    # wind-swept snow streaks (east-west)
    dq = d * np.array([1.0, 3.5, 1.0], F32)
    streak = Fractal3(2111).fbm(warp(dq, 2130, 1.5, 0.2), 9.0, 4) * 0.5 + 0.5
    col = mix(col, c(0.93, 0.94, 0.99), smoothstep(0.6, 0.85, streak) * 0.35)
    # dark rocky ridges poking through the ice
    rock = mix(c(0.16, 0.17, 0.27), c(0.30, 0.31, 0.44), det)
    mtn = smoothstep(0.35, 0.75, P["ridge"]) * P["rz"]
    col = mix(col, rock, mtn * 0.85)
    # crevasse networks: blue-black cracks in active zones, faint blue glow around them
    zone = smoothstep(0.42, 0.62, Fractal3(2152).fbm(warp(d, 2153, 1.4, 0.2), 1.6, 5) * 0.5 + 0.5)
    _, e1, _ = voronoi(nrm(warp(d, 2150, 3.0, 0.06)), seeds(300, 2151))
    _, e2, _ = voronoi(nrm(warp(d, 2155, 5.0, 0.04)), seeds(1400, 2156, relax=1))
    crev = np.clip(line_mask(e1, 0.0016) * zone + line_mask(e2, 0.0008) * zone * 0.6, 0, 1)
    col = mix(col, c(0.30, 0.40, 0.72), halo(e1, 0.006) * zone * 0.35)
    col = mix(col, c(0.06, 0.08, 0.22), crev * 0.9)
    # frozen methane lakes: smooth, glossy indigo with bright frost rims
    ln = Fractal3(2160).fbm(warp(d, 2161, 2.0, 0.25), 1.8, 6) * 0.5 + 0.5
    lake = smoothstep(0.64, 0.67, ln) * (1 - mtn)
    lakecol = mix(c(0.18, 0.20, 0.50), c(0.30, 0.34, 0.68), Fractal3(2162).fbm(d, 6.0, 4) * 0.5 + 0.5)
    shore = smoothstep(0.60, 0.64, ln) * (1 - lake)
    col = mix(col, c(0.92, 0.93, 0.99), shore * 0.5)
    col = mix(col, lakecol, lake * 0.92)
    # polar caps: brighter, smoother
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.94, 0.95, 1.0), smoothstep(0.82, 0.95, alat + 0.04 * Fractal3(2170).fbm(d, 5, 4)) * 0.7)
    col = col * (1.0 + 0.40 * shade * (1 - lake))[..., None]
    return col * (0.88 + 0.16 * det + 0.06 * grain)[..., None], None


# ------------------------------------------------------------------------------------------------
# magma world
# ------------------------------------------------------------------------------------------------
def magma_h(d):
    q = warp(d, 2201, 1.5, 0.3)
    return Fractal3(2210).fbm(q, 1.6, 7) * 0.5 + 0.5


def alien_magma(d, lat, lon):
    base = magma_h(d)
    shade = relief(magma_h, d, base, k=0.55)
    det = Fractal3(2213).fbm(d, 32.0, 4) * 0.5 + 0.5
    grain = Fractal3(2216).fbm(d, 110.0, 2) * 0.5 + 0.5
    # basalt crust: near-black violet-grey
    col = gradient_map(base, [(0.0, c(0.07, 0.06, 0.09)), (0.4, c(0.13, 0.11, 0.15)), (0.7, c(0.20, 0.17, 0.21)),
                              (1.0, c(0.15, 0.13, 0.16))])
    # crust plates (Voronoi) with slightly varying tone
    i1, e1, _ = voronoi(nrm(warp(d, 2240, 2.6, 0.06)), seeds(220, 2241))
    r1 = cell_rand(i1, 2242, 2)
    col = col * (0.85 + 0.3 * r1[..., 0])[..., None]
    # magma seas: large basins of molten rock under a thin cooled skin
    sea_n = Fractal3(2250).fbm(warp(d, 2251, 1.6, 0.3), 1.4, 6) * 0.5 + 0.5
    sea = smoothstep(0.60, 0.64, sea_n)
    act = smoothstep(0.40, 0.70, Fractal3(2252).fbm(d, 1.2, 4) * 0.5 + 0.5)
    rift = line_mask(e1, 0.0010 + 0.0030 * act) * smoothstep(0.12, 0.55, act)
    _, e2, _ = voronoi(nrm(warp(d, 2260, 6.0, 0.04)), seeds(1600, 2261, relax=1))
    skin = line_mask(e2, 0.0012) * sea
    riv = smoothstep(0.86, 0.97, Fractal3(2270).ridged(warp(d, 2271, 1.8, 0.25), 2.2, 6, sharp=10.0)) * \
        smoothstep(0.3, 0.6, act)
    scorch = np.clip(halo(e1, 0.010) * act + halo(e2, 0.003) * sea * 0.5 + riv * 0.6, 0, 1)
    col = mix(col, c(0.05, 0.04, 0.05), scorch * 0.5)
    col = mix(col, c(0.10, 0.05, 0.05), sea * 0.85)
    hot = np.clip(rift * (0.5 + 0.6 * act) + skin * 0.9 + riv, 0, 1)
    col = mix(col, c(0.25, 0.08, 0.04), hot * 0.9)
    col = col * (1.0 + 0.32 * shade * (1 - sea))[..., None] * (0.88 + 0.16 * det + 0.06 * grain)[..., None]
    # emission: glowing rifts, rivers and cracks in the crust of the seas
    flick = Fractal3(2280).fbm(d, 14.0, 3) * 0.5 + 0.5
    core = np.clip(rift * (0.45 + 0.6 * act) + skin * 0.85 + riv * 1.0, 0, 1.2) * (0.4 + 0.7 * flick)
    pool = sea * smoothstep(0.62, 0.75, sea_n) * 0.18 * (0.5 + 0.5 * flick)
    heat = np.clip(core + pool + halo(e1, 0.005) * act * 0.2, 0, 1)
    emis = gradient_map(heat, [(0.0, c(0, 0, 0)), (0.2, c(0.42, 0.05, 0.02)), (0.5, c(0.95, 0.26, 0.04)),
                               (0.8, c(1.0, 0.56, 0.12)), (1.0, c(1.0, 0.84, 0.45))])
    return col, emis


# ------------------------------------------------------------------------------------------------
# bioluminescent forest world
# ------------------------------------------------------------------------------------------------
def bloom_h(d):
    q = warp(d, 2301, 1.4, 0.32)
    return Fractal3(2310).fbm(q, 1.3, 8)


def alien_bloom(d, lat, lon):
    h = bloom_h(d)
    sea_level = 0.02
    land = h > sea_level
    shade = relief(bloom_h, d, h, k=0.4) * land
    det = Fractal3(2313).fbm(d, 26.0, 4) * 0.5 + 0.5
    grain = Fractal3(2314).fbm(d, 100.0, 2) * 0.5 + 0.5
    elev = np.clip((h - sea_level) / 0.6, 0, 1)
    # forests: dark teal canopy with lighter blue-green clearings, bare slate highlands
    canopy = Fractal3(2320).fbm(warp(d, 2321, 2.5, 0.15), 3.0, 6) * 0.5 + 0.5
    landcol = gradient_map(canopy, [(0.0, c(0.03, 0.12, 0.14)), (0.4, c(0.05, 0.20, 0.22)), (0.7, c(0.10, 0.28, 0.30)),
                                    (1.0, c(0.16, 0.30, 0.36))])
    landcol = mix(landcol, c(0.22, 0.24, 0.34), smoothstep(0.45, 0.9, elev) * 0.6)
    # glowing colonies: small rings and spots in clusters
    pts = seeds(900, 2330, relax=1)
    flat = d.reshape(-1, 3)
    dots = flat @ pts.T
    i1 = np.argmax(dots, axis=1)
    ang = np.arccos(np.clip(dots[np.arange(len(i1)), i1], -1, 1)).reshape(d.shape[:-1]).astype(F32)
    i1 = i1.reshape(d.shape[:-1])
    rr = cell_rand(i1, 2331, 3)
    zone = smoothstep(0.36, 0.56, Fractal3(2332).fbm(d, 2.2, 5) * 0.5 + 0.5) * land
    rad = 0.006 + 0.022 * rr[..., 0] ** 2
    ring = line_mask(np.abs(ang - rad), 0.0024) * (rr[..., 1] < 0.6) * zone
    spot = smoothstep(rad * 0.6, 0.0, ang) * (rr[..., 1] >= 0.6) * zone
    glow_land = np.clip(ring + spot, 0, 1).astype(F32)
    landcol = mix(landcol, c(0.10, 0.42, 0.40), glow_land * 0.6)
    landcol = landcol * (1.0 + 0.32 * shade)[..., None] * (0.82 + 0.2 * det + 0.06 * grain)[..., None]
    # inky seas with luminous plankton swirls
    depth = np.clip((sea_level - h) / 0.6, 0, 1)
    sea = mix(c(0.04, 0.14, 0.20), c(0.02, 0.06, 0.12), smoothstep(0.0, 0.4, depth))
    swirl = Fractal3(2340).fbm(warp(d, 2341, 4.0, 0.35), 5.0, 5) * 0.5 + 0.5
    plank = smoothstep(0.66, 0.82, swirl) * (1 - smoothstep(0.5, 1.0, depth)) * (1 - land)
    sea = mix(sea, c(0.08, 0.30, 0.34), plank * 0.5)
    shore = smoothstep(0.03, 0.0, sea_level - h) * (1 - land)
    sea = mix(sea, c(0.12, 0.36, 0.36), shore * 0.5)
    col = np.where(land[..., None], landcol, sea)
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.55, 0.68, 0.75), smoothstep(0.90, 0.97, alat + 0.03 * Fractal3(2350).fbm(d, 4, 4)) * 0.6)
    # emission: cyan-teal bioluminescence (colonies, plankton, coasts)
    flick = Fractal3(2360).fbm(d, 20.0, 3) * 0.5 + 0.5
    lum = np.clip(glow_land * (0.85 + 0.6 * flick) + plank * 0.55 * flick + shore * 0.3, 0, 1)
    emis = gradient_map(lum, [(0.0, c(0, 0, 0)), (0.3, c(0.02, 0.25, 0.26)), (0.7, c(0.15, 0.80, 0.75)),
                              (1.0, c(0.6, 1.0, 0.95))])
    return col, emis


# ------------------------------------------------------------------------------------------------
# home world of the second system: indigo obsidian, deep blue seas, cyan / violet light networks
# ------------------------------------------------------------------------------------------------
def void_h(d):
    q = warp(d, 2401, 1.25, 0.28)
    return Fractal3(2410).fbm(q, 1.3, 9, gain=0.52) + 0.25 * Fractal3(2412).ridged(q, 3.0, 6, sharp=2.4)


def alien_void(d, lat, lon):
    h = void_h(d)
    sea_level = 0.22
    land = h > sea_level
    shade = relief(void_h, d, h, k=0.6) * land
    det = Fractal3(2413).fbm(d, 26.0, 4) * 0.5 + 0.5
    elev = np.clip((h - sea_level) / 0.6, 0, 1)
    flowb = Fractal3(2411).fbm(warp(d, 2420, 2.0, 0.25), 2.5, 6) * 0.5 + 0.5
    obs = gradient_map(flowb, [(0.0, c(0.05, 0.05, 0.11)), (0.4, c(0.09, 0.09, 0.19)), (0.7, c(0.14, 0.15, 0.28)),
                               (1.0, c(0.08, 0.08, 0.16))])
    obs = mix(obs, c(0.26, 0.28, 0.40), smoothstep(0.35, 0.8, elev) * 0.45)
    obs = obs * (1.0 + 0.45 * shade)[..., None] * (0.85 + 0.3 * det)[..., None]
    depth = np.clip((sea_level - h) / 0.75, 0, 1)
    sea = mix(c(0.11, 0.15, 0.40), c(0.05, 0.07, 0.25), smoothstep(0.0, 0.14, depth))
    sea = mix(sea, c(0.02, 0.025, 0.11), smoothstep(0.18, 1.0, depth))
    swirl = Fractal3(2414).fbm(warp(d, 2415, 3.0, 0.2), 4.0, 4) * 0.5 + 0.5
    sea = sea * (0.94 + 0.12 * swirl)[..., None]
    # ---- artificial megastructures ------------------------------------------------------------
    rng = np.random.default_rng(2430)
    rotA = random_rotation(rng)
    rotB = random_rotation(rng)
    dev = smoothstep(0.34, 0.56, Fractal3(2431).fbm(d, 1.5, 5) * 0.5 + 0.5)
    dev = dev * smoothstep(sea_level - 0.01, sea_level + 0.05, h)
    pts = seeds(48, 2432)
    i1, i2, e_sec, n_sec, a_hub = voronoi_full(d, pts)
    hub = np.exp(-(a_hub / 0.16) ** 2)
    on_land = smoothstep(sea_level - 0.02, sea_level + 0.02, h)
    causeway = (pair_rand(i1, i2, 9) < 0.18).astype(F32)
    hw = line_mask(e_sec, 0.0020) * np.clip(on_land + causeway, 0, 1)
    node = smoothstep(0.028, 0.0, n_sec) * on_land
    g1 = line_mask(grid_dist(d, rotA, 48), 0.0010)
    g2 = line_mask(grid_dist(d, rotB, 160), 0.0005)
    grid = np.clip(g1 + g2 * 0.9, 0, 1) * dev * (0.25 + 0.75 * hub)
    blocks = smoothstep(0.55, 0.75, Fractal3(2434).fbm(d, 60.0, 2) * 0.5 + 0.5) * dev * hub
    rings = np.zeros(d.shape[:-1], F32)
    ring_fill = np.zeros(d.shape[:-1], F32)
    rr = np.random.default_rng(2441)
    for k in range(len(pts)):
        if rr.random() < 0.26:
            r0 = rr.uniform(0.06, 0.12)
            dist, ang = ring_dist(d, pts[k], r0)
            rings += line_mask(dist, 0.0020)
            dist2, _ = ring_dist(d, pts[k], r0 * 0.6)
            rings += line_mask(dist2, 0.0013) * 0.8
            ring_fill += smoothstep(r0 * 1.01, r0 * 0.97, ang) * 0.6
    rings = np.clip(rings, 0, 1) * np.clip(on_land + 0.35, 0, 1)
    ring_fill = np.clip(ring_fill, 0, 1) * land
    plating = c(0.26, 0.28, 0.42)
    alb = np.where(land[..., None], obs, sea)
    alb = mix(alb, c(0.12, 0.13, 0.26), ring_fill * 0.6)
    alb = mix(alb, plating * 0.8, blocks * 0.4)
    alb = mix(alb, plating, np.clip(grid * 0.6 + rings * 0.8 + hw * 0.7, 0, 1))
    alat = np.abs(lat) / (np.pi / 2)
    alb = mix(alb, c(0.36, 0.38, 0.50), smoothstep(0.90, 0.97, alat + 0.03 * Fractal3(2450).fbm(d, 4, 4)) * 0.6)
    # ---- emission: cyan / violet light networks ---------------------------------------------
    spark = Fractal3(2460).fbm(d, 90.0, 2) * 0.5 + 0.5
    city = smoothstep(0.42, 0.75, spark)
    along = Fractal3(2462).fbm(d, 24.0, 3) * 0.5 + 0.5
    hue = smoothstep(0.35, 0.65, Fractal3(2461).fbm(d, 3.0, 3) * 0.5 + 0.5)
    lights = (grid * (0.4 + 0.8 * city) + rings * 0.95 + hw * (0.35 + 0.65 * along) * (0.5 + 0.5 * on_land)
              + node * 1.2 + blocks * city * 0.3 + hub * dev * city * 0.15)
    lights = np.clip(lights, 0, 1.4)
    ecol = mix(c(0.25, 0.72, 1.0), c(0.56, 0.30, 1.0), hue)
    emis = ecol * np.clip(lights, 0, 1)[..., None] * 0.95
    emis = emis + c(0.85, 0.90, 1.0) * np.clip(lights - 1.0, 0, 0.4)[..., None]
    return alb, emis


TYPES = {"alien_glacier": alien_glacier, "alien_magma": alien_magma, "alien_bloom": alien_bloom,
         "alien_void": alien_void}


def work(args):
    name, r0, r1 = args
    d, lat, lon = dirs_band(r0, r1)
    alb, extra = TYPES[name](d, lat, lon)
    return r0, np.asarray(alb, F32), None if extra is None else np.asarray(extra, F32)


def build(name, preview=False):
    t0 = time.time()
    alb = np.zeros((H, W, 3), F32)
    extra = None
    step = 32
    jobs = [(name, r, min(H, r + step)) for r in range(0, H, step)]
    with Pool(4) as pool:
        for r0, a, e in pool.imap_unordered(work, jobs):
            alb[r0:r0 + a.shape[0]] = a
            if e is not None:
                if extra is None:
                    extra = np.zeros((H, W, 3), F32)
                extra[r0:r0 + e.shape[0]] = e
    os.makedirs(OUT, exist_ok=True)
    save_rgb(os.path.join(OUT, name + ".png"), srgb_from_linear(alb))
    if extra is not None:
        save_rgb(os.path.join(OUT, name + "_emission.png"), srgb_from_linear(extra))
    print("%-14s %dx%d  %.1fs" % (name, W, H, time.time() - t0), flush=True)
    if preview:
        from PIL import Image
        os.makedirs(PREV, exist_ok=True)
        Image.open(os.path.join(OUT, name + ".png")).resize((512, 256), Image.LANCZOS).save(
            os.path.join(PREV, "planet_%s.png" % name))
        if extra is not None:
            Image.open(os.path.join(OUT, name + "_emission.png")).resize((512, 256), Image.LANCZOS).save(
                os.path.join(PREV, "planet_%s_emission.png" % name))


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(TYPES)
    for nm in names:
        build(nm, "--preview" in sys.argv)
