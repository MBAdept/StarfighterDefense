"""
gen_alien_planets.py - equirectangular textures for the planets of the hostile ALIEN star system.
Run:  /opt/tools/venv/bin/python tools/textures/gen_alien_planets.py [names...] [--preview]
Output (assets/textures/planets/, 2048x1024 RGB, sRGB):
  alien_crimson.png                      rust-red deserts, dark basalt ridges, deep canyon systems
  alien_spore.png                        sickly yellow-green / olive land, dark fungal colonies, murky toxic seas
  alien_ash.png  + alien_ash_emission.png    grey ash plains cut by a network of glowing fissures
  alien_crystal.png                      violet / teal crystalline facets with pale veins
  alien_home.png + alien_home_emission.png   alien home world: obsidian-purple continents, magenta-tinted seas,
                                         vast artificial geometric structures with magenta/red light networks
Like gen_planets.py every field is evaluated on 3D unit direction vectors (noiselib), so the maps are seamless at the
left/right edge and have no pole pinching. Geometric structures (Voronoi plates, grid lines, rings) are computed as
exact angular distances on the sphere, so their line widths stay constant everywhere.
Convention matches sphere_dirs(): longitude increases left->right, top row = north pole, +Y up.
"""
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import (F32, Fractal3, smoothstep, srgb_from_linear, linear_from_srgb, save_rgb,  # noqa: E402
                      gradient_map, random_rotation)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "planets")
PREV = os.path.join(ROOT, "tools", "textures", "previews")
W, H = 2048, 1024


def c(*rgb_srgb):
    """sRGB colour (0..1) -> linear."""
    return linear_from_srgb(np.array(rgb_srgb, F32))


def mix(a, b, t):
    t = np.asarray(t, F32)[..., None]
    return a * (1 - t) + b * t


def dirs_band(r0, r1):
    lon = (np.arange(W, dtype=np.float64) + 0.5) / W * 2.0 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(r0, r1, dtype=np.float64) + 0.5) / H * np.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    d = np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)], axis=-1).astype(F32)
    return d, lat.astype(F32), lon.astype(F32)


def warp(d, seed, freq, strength, octv=4):
    fx, fy, fz = Fractal3(seed), Fractal3(seed + 1), Fractal3(seed + 2)
    return d + strength * np.stack([fx.fbm(d, freq, octv), fy.fbm(d, freq, octv), fz.fbm(d, freq, octv)], -1)


def nrm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


# ------------------------------------------------------------------------------------------------
# spherical geometry helpers
# ------------------------------------------------------------------------------------------------
def seeds(n, seed, relax=2):
    """n roughly uniform unit vectors (a little Lloyd-like repulsion for even cells)."""
    rng = np.random.default_rng(seed)
    p = nrm(rng.normal(size=(n, 3)))
    for _ in range(relax):
        dots = p @ p.T
        np.fill_diagonal(dots, -1)
        nn = np.argsort(-dots, axis=1)[:, :6]
        push = np.zeros_like(p)
        for k in range(6):
            q = p[nn[:, k]]
            push += (p - q) / (np.linalg.norm(p - q, axis=1, keepdims=True) ** 2 + 1e-3)
        p = nrm(p + 0.002 * push)
    return p.astype(F32)


def voronoi(d, pts):
    """Spherical Voronoi on directions d (..., 3): returns (id1, edge distance in radians, node closeness).
    Edge distance = angular distance to the bisector great circle between the nearest two seeds."""
    shp = d.shape[:-1]
    flat = d.reshape(-1, 3)
    dots = flat @ pts.T                                      # (N, n)
    idx = np.argpartition(-dots, 2, axis=1)[:, :3]
    dd = np.take_along_axis(dots, idx, axis=1)
    order = np.argsort(-dd, axis=1)
    idx = np.take_along_axis(idx, order, axis=1)
    dd = np.take_along_axis(dd, order, axis=1)
    p1, p2, p3 = pts[idx[:, 0]], pts[idx[:, 1]], pts[idx[:, 2]]
    e12 = (dd[:, 0] - dd[:, 1]) / np.linalg.norm(p1 - p2, axis=1)
    e13 = (dd[:, 0] - dd[:, 2]) / np.linalg.norm(p1 - p3, axis=1)
    return idx[:, 0].reshape(shp), e12.reshape(shp).astype(F32), np.maximum(e12, e13).reshape(shp).astype(F32)


def voronoi_full(d, pts):
    """Like voronoi() but also returns the second-nearest id and the angle to the nearest seed."""
    shp = d.shape[:-1]
    flat = d.reshape(-1, 3)
    dots = flat @ pts.T
    idx = np.argpartition(-dots, 2, axis=1)[:, :3]
    dd = np.take_along_axis(dots, idx, axis=1)
    order = np.argsort(-dd, axis=1)
    idx = np.take_along_axis(idx, order, axis=1)
    dd = np.take_along_axis(dd, order, axis=1)
    p1, p2, p3 = pts[idx[:, 0]], pts[idx[:, 1]], pts[idx[:, 2]]
    e12 = (dd[:, 0] - dd[:, 1]) / np.linalg.norm(p1 - p2, axis=1)
    e13 = (dd[:, 0] - dd[:, 2]) / np.linalg.norm(p1 - p3, axis=1)
    ang1 = np.arccos(np.clip(dd[:, 0], -1, 1))
    r = lambda a: a.reshape(shp)  # noqa: E731
    return r(idx[:, 0]), r(idx[:, 1]), r(e12).astype(F32), r(np.maximum(e12, e13)).astype(F32), r(ang1).astype(F32)


def pair_rand(i, j, seed):
    a = np.minimum(i, j).astype(np.int64)
    b = np.maximum(i, j).astype(np.int64)
    hsh = (a * 73856093 + b * 19349663 + seed * 83492791) & 0xFFFFFFFF
    hsh = (hsh ^ (hsh >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((hsh ^ (hsh >> 16)) & 0xFFFF).astype(F32) / 65535.0


def cell_rand(idx, seed, k=1):
    rng = np.random.default_rng(seed)
    tab = rng.random((100000, k)).astype(F32)
    v = tab[idx % 100000]
    return v[..., 0] if k == 1 else v


def grid_dist(d, rot, n):
    """Angular distance to the nearest line of a cube-sphere grid with n cells per cube face edge
    (lines are great circles; frame rotated by `rot`)."""
    q = d @ rot.T
    ax = np.abs(q)
    best = np.full(d.shape[:-1], 9.0, F32)
    for m in range(3):                                       # dominant axis
        sel = (ax[..., m] >= ax[..., (m + 1) % 3]) & (ax[..., m] >= ax[..., (m + 2) % 3])
        for a in ((m + 1) % 3, (m + 2) % 3):                 # lines u = const on this face
            u = q[..., a] / np.maximum(ax[..., m], 1e-6)
            cc = np.round((u + 1.0) * n / 2.0) / (n / 2.0) - 1.0
            # plane through the origin containing the line: normal = e_a - cc * sign(q_m) e_m
            sgn = np.sign(q[..., m])
            nlen = np.sqrt(1.0 + cc * cc)
            dist = np.abs(q[..., a] - cc * sgn * q[..., m]) / nlen
            best = np.where(sel, np.minimum(best, dist), best)
    return best


def ring_dist(d, centre, radius):
    """Angular distance to a small circle of given angular radius around `centre`."""
    ang = np.arccos(np.clip(d @ centre, -1, 1))
    return np.abs(ang - radius), ang


PIX = np.pi / H   # angular size of one texel (rad)


def line_mask(dist, width, soft=0.0):
    """Anti-aliased line of half-width `width` (rad): exact 1D box-filter coverage of a texel, so even
    sub-texel lines stay continuous (just fainter). `soft` adds a gentle halo (x width)."""
    lo = np.maximum(dist - width, -PIX * 0.5)
    hi = np.minimum(dist + width, PIX * 0.5)
    cov = np.clip((hi - lo) / PIX, 0.0, 1.0)
    if soft > 0:
        cov = np.maximum(cov, 0.35 * halo(dist, width * (1.0 + soft) + PIX))
    return cov.astype(F32)


def halo(dist, r):
    return np.exp(-(dist / r) ** 2).astype(F32)


# ------------------------------------------------------------------------------------------------
# relief shading: height evaluated twice in 3D, offset along the tangent of a FIXED light vector
# (no dependency on lat/lon frames -> no pole artefacts)
# ------------------------------------------------------------------------------------------------
LIGHT = nrm(np.array([-0.45, 0.62, 0.64], F32))


def relief(hfun, d, h0, eps=0.006, k=1.0):
    lt = LIGHT[None, None, :] - (d @ LIGHT)[..., None] * d
    h1 = hfun(nrm(d + eps * lt))
    return np.clip((h1 - h0) / eps * k, -1.0, 1.0).astype(F32)


# ------------------------------------------------------------------------------------------------
# planet types: f(d, lat, lon) -> (albedo_linear, emission_linear_or_None)
# ------------------------------------------------------------------------------------------------
def crimson_h(d, parts=False):
    q = warp(d, 1201, 1.4, 0.30)
    region = Fractal3(1209).fbm(q, 1.1, 5) * 0.5 + 0.5
    base = Fractal3(1210).fbm(q, 2.3, 8) * 0.5 + 0.5
    ridge = Fractal3(1214).ridged(warp(d, 1240, 1.6, 0.28), 2.6, 7, sharp=3.4)
    rzone = smoothstep(0.42, 0.66, Fractal3(1215).fbm(q, 1.3, 4) * 0.5 + 0.5)
    can = Fractal3(1216).ridged(warp(d, 1250, 2.0, 0.24), 1.7, 7, sharp=6.0)
    czone = smoothstep(0.32, 0.58, Fractal3(1217).fbm(d, 1.5, 4) * 0.5 + 0.5)
    canyon = smoothstep(0.50, 0.90, can) * czone
    # a great rift valley along a tilted great circle
    nrift = nrm(np.array([0.35, 0.86, 0.37], F32))
    rd = np.abs(d @ nrift + 0.05 * Fractal3(1218).fbm(d, 3.0, 5))
    along = smoothstep(-0.2, 0.4, d @ np.array([0.9, -0.1, -0.42], F32))
    rift = smoothstep(0.05, 0.012, rd) * along
    mtn = ridge * rzone
    h = 0.45 * base + 0.35 * region + 0.75 * mtn ** 1.5 - 0.55 * canyon - 0.6 * rift
    if parts:
        return h, dict(region=region, base=base, mtn=mtn, canyon=canyon, can=can, czone=czone, rift=rift, rd=rd,
                       along=along)
    return h


def alien_crimson(d, lat, lon):
    h, P = crimson_h(d, True)
    shade = relief(crimson_h, d, h, k=0.9)
    det = Fractal3(1213).fbm(d, 34.0, 4) * 0.5 + 0.5
    grain = Fractal3(1219).fbm(d, 110.0, 2) * 0.5 + 0.5
    region, base = P["region"], P["base"]
    # rust-red deserts: maroon lowlands -> rust -> red-orange -> dusty salmon highlands
    t = np.clip(region * 0.65 + base * 0.45 - 0.1, 0, 1)
    col = gradient_map(t, [(0.0, c(0.30, 0.07, 0.05)), (0.28, c(0.48, 0.12, 0.07)), (0.52, c(0.62, 0.20, 0.10)),
                           (0.74, c(0.72, 0.30, 0.17)), (0.90, c(0.80, 0.44, 0.31)), (1.0, c(0.74, 0.36, 0.24))])
    # dune fields in the lowlands (stretched east-west)
    dq = d * np.array([1.0, 4.0, 1.0], F32)
    dunes = Fractal3(1211).ridged(warp(dq, 1230, 1.5, 0.2), 12.0, 4, sharp=1.8)
    low = smoothstep(0.55, 0.3, t)
    col = mix(col, c(0.70, 0.27, 0.13), dunes * 0.35 * low)
    # dark basalt ridges
    basalt = mix(c(0.09, 0.055, 0.055), c(0.19, 0.10, 0.08), det)
    col = mix(col, basalt, smoothstep(0.18, 0.55, P["mtn"]) * 0.92)
    # canyons: layered strata on the walls, near-black floors
    cv = P["canyon"]
    strata = 0.5 + 0.5 * np.sin(h * 26.0 + 2.0 * det)
    wall = smoothstep(0.08, 0.45, cv) * (1 - smoothstep(0.75, 0.95, cv))
    col = mix(col, mix(c(0.46, 0.13, 0.07), c(0.68, 0.32, 0.19), strata), wall * 0.6)
    col = mix(col, c(0.12, 0.03, 0.025), smoothstep(0.7, 0.97, cv) * 0.95)
    rift = P["rift"]
    col = mix(col, mix(c(0.40, 0.10, 0.06), c(0.68, 0.32, 0.20), strata), smoothstep(0.0, 0.5, rift) * 0.7)
    col = mix(col, c(0.10, 0.025, 0.02), smoothstep(0.55, 0.95, rift) * 0.95)
    # faint frost-dust at the poles
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.70, 0.46, 0.40), smoothstep(0.90, 0.985, alat + 0.04 * Fractal3(1220).fbm(d, 5, 4)) * 0.55)
    col = col * (1.0 + 0.42 * shade)[..., None]
    return col * (0.86 + 0.2 * det + 0.08 * grain)[..., None], None


def spore_h(d, parts=False):
    q = warp(d, 1301, 1.5, 0.34)
    h = Fractal3(1310).fbm(q, 1.4, 8)
    if parts:
        return h, q
    return h


def alien_spore(d, lat, lon):
    h, q = spore_h(d, True)
    sea_level = -0.06
    shade = relief(spore_h, d, h, k=0.35) * (h > sea_level)
    sw = Fractal3(1311).fbm(warp(d, 1320, 2.0, 0.16), 2.6, 7) * 0.5 + 0.5
    mott = Fractal3(1314).fbm(d, 14.0, 4) * 0.5 + 0.5
    det = Fractal3(1312).fbm(d, 28.0, 4) * 0.5 + 0.5
    grain = Fractal3(1313).fbm(d, 100.0, 2) * 0.5 + 0.5
    # land: olive -> sickly yellow-green -> pale chartreuse
    land = gradient_map(sw, [(0.0, c(0.30, 0.33, 0.10)), (0.35, c(0.46, 0.50, 0.15)), (0.6, c(0.62, 0.66, 0.21)),
                             (0.82, c(0.74, 0.74, 0.33)), (1.0, c(0.52, 0.56, 0.17))])
    elev = np.clip((h - sea_level) / 0.6, 0, 1)
    land = mix(land, c(0.40, 0.37, 0.19), smoothstep(0.45, 0.9, elev) * 0.6)
    # large dark mould regions with a darker rim at their edge
    big_n = Fractal3(1344).fbm(warp(d, 1345, 2.0, 0.25), 2.0, 7) * 0.5 + 0.5
    big = smoothstep(0.585, 0.62, big_n)
    big_rim = smoothstep(0.56, 0.585, big_n) * (1 - big)
    spots = smoothstep(0.6, 0.8, Fractal3(1343).fbm(d, 40.0, 3) * 0.5 + 0.5)
    mould = mix(c(0.14, 0.11, 0.05), c(0.30, 0.27, 0.09), spots) * (0.8 + 0.4 * mott)[..., None]
    land = mix(land, c(0.24, 0.22, 0.08), big_rim * 0.8)
    land = mix(land, mould, big * 0.9)
    # round fungal colonies (fairy rings): circles around random seeds, noisy radius, dark ring + dim interior
    pts = seeds(700, 1330, relax=1)
    flat = d.reshape(-1, 3)
    dots = flat @ pts.T
    i1 = np.argmax(dots, axis=1)
    ang = np.arccos(np.clip(dots[np.arange(len(i1)), i1], -1, 1)).reshape(d.shape[:-1])
    i1 = i1.reshape(d.shape[:-1])
    rr = cell_rand(i1, 1331, 2)
    rad = (0.006 + 0.03 * rr[..., 0] ** 2) * (1.0 + 0.25 * (Fractal3(1332).fbm(d, 30.0, 3)))
    on = (rr[..., 1] < 0.55) * smoothstep(0.3, 0.55, sw)
    ring = line_mask(np.abs(ang - rad), 0.0026) * on
    disc = smoothstep(rad, rad * 0.7, ang) * on
    land = mix(land, c(0.24, 0.24, 0.08), disc * 0.55)
    land = mix(land, c(0.09, 0.10, 0.04), ring * 0.85)
    land = land * (1.0 + 0.3 * shade)[..., None] * (0.80 + 0.16 * det + 0.16 * mott + 0.08 * grain)[..., None]
    # murky toxic seas: dark brown-green murk, slimy swirls, sickly scum at the shores
    depth = np.clip((sea_level - h) / 0.6, 0, 1)
    sea = mix(c(0.25, 0.31, 0.16), c(0.13, 0.21, 0.15), smoothstep(0.0, 0.3, depth))
    sea = mix(sea, c(0.07, 0.12, 0.10), smoothstep(0.3, 1.0, depth))
    swirl = Fractal3(1350).fbm(warp(d, 1351, 3.5, 0.3), 6.0, 5) * 0.5 + 0.5
    sea = mix(sea, c(0.30, 0.33, 0.12), smoothstep(0.62, 0.9, swirl) * 0.45)
    sea = mix(sea, c(0.05, 0.09, 0.08), smoothstep(0.4, 0.15, swirl) * 0.35)
    sea = mix(sea, c(0.56, 0.57, 0.17), smoothstep(0.03, 0.0, sea_level - h) * 0.6)
    col = np.where((h > sea_level)[..., None], land, sea)
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.54, 0.56, 0.38), smoothstep(0.91, 0.98, alat + 0.03 * Fractal3(1352).fbm(d, 4, 4)) * 0.7)
    return col, None


def ash_h(d, parts=False):
    q = warp(d, 1401, 1.5, 0.3)
    base = Fractal3(1410).fbm(q, 1.6, 7) * 0.5 + 0.5
    flow = smoothstep(0.60, 0.72, Fractal3(1415).fbm(warp(d, 1430, 1.8, 0.3), 2.2, 6) * 0.5 + 0.5)
    h = 0.6 * base + 0.25 * flow
    if parts:
        return h, dict(q=q, base=base, flow=flow)
    return h


def alien_ash(d, lat, lon):
    h, P = ash_h(d, True)
    shade = relief(ash_h, d, h, k=0.5)
    base, flow = P["base"], P["flow"]
    det = Fractal3(1413).fbm(d, 32.0, 4) * 0.5 + 0.5
    grain = Fractal3(1416).fbm(d, 110.0, 2) * 0.5 + 0.5
    col = gradient_map(base, [(0.0, c(0.33, 0.32, 0.32)), (0.35, c(0.47, 0.46, 0.45)), (0.62, c(0.60, 0.59, 0.57)),
                              (0.85, c(0.71, 0.70, 0.68)), (1.0, c(0.58, 0.57, 0.56))])
    # wind-blown ash streaks
    dq = d * np.array([1.0, 3.0, 1.0], F32)
    streak = Fractal3(1414).fbm(warp(dq, 1420, 2.0, 0.2), 8.0, 4) * 0.5 + 0.5
    col *= (0.86 + 0.26 * streak)[..., None]
    col = mix(col, c(0.19, 0.18, 0.18), flow * 0.85)                      # old basalt flows
    # --- fissures: active volcanic provinces with crack networks + a few long rifts ---------------
    act = smoothstep(0.52, 0.70, Fractal3(1452).fbm(warp(d, 1456, 1.5, 0.2), 1.3, 5) * 0.5 + 0.5)
    _, e1, n1 = voronoi(nrm(warp(d, 1440, 3.0, 0.07)), seeds(240, 1441))
    _, e2, _ = voronoi(nrm(warp(d, 1450, 5.0, 0.045)), seeds(1300, 1451, relax=1))
    w1 = 0.0012 + 0.0032 * act                                             # wider near province cores
    f1 = line_mask(e1, w1) * smoothstep(0.05, 0.4, act)
    f2 = line_mask(e2, 0.0011) * smoothstep(0.35, 0.8, act) * 0.8
    rift_n = Fractal3(1453).ridged(warp(d, 1460, 1.4, 0.22), 1.15, 5, sharp=16.0)
    belt = smoothstep(0.45, 0.62, Fractal3(1457).fbm(d, 0.9, 3) * 0.5 + 0.5)
    rift = smoothstep(0.80, 0.97, rift_n) * belt
    fiss = np.clip(f1 + f2 + rift, 0, 1)
    scorch = np.clip(halo(e1, 0.010) * smoothstep(0.1, 0.6, act) + halo(e2, 0.004) * act * 0.5
                     + smoothstep(0.55, 0.9, rift_n) * belt * 0.8, 0, 1)
    col = mix(col, c(0.16, 0.13, 0.13), scorch * 0.6)
    col = mix(col, c(0.24, 0.07, 0.04), fiss * 0.92)
    hot = smoothstep(0.022, 0.0, n1) * smoothstep(0.3, 0.7, act)            # calderas at network nodes
    col = mix(col, c(0.20, 0.06, 0.035), hot * 0.85)
    col = col * (1.0 + 0.35 * shade)[..., None] * (0.88 + 0.16 * det + 0.06 * grain)[..., None]
    # --- emission -------------------------------------------------------------------------------
    flick = Fractal3(1455).fbm(d, 16.0, 3) * 0.5 + 0.5
    core = np.clip(f1 * (0.5 + 0.6 * act) + f2 * 0.7 + rift * 1.1, 0, 1.2) * (0.45 + 0.75 * flick)
    spill = (halo(e1, 0.006) * act * 0.22 + smoothstep(0.7, 0.97, rift_n) * belt * 0.25) * (0.5 + 0.5 * flick)
    heat = np.clip(core + spill + hot * 1.1, 0, 1)
    emis = gradient_map(heat, [(0.0, c(0, 0, 0)), (0.2, c(0.40, 0.04, 0.01)), (0.5, c(0.92, 0.22, 0.03)),
                               (0.8, c(1.0, 0.52, 0.10)), (1.0, c(1.0, 0.80, 0.40))])
    return col, emis


def alien_crystal(d, lat, lon):
    q = warp(d, 1501, 1.3, 0.3)
    region = Fractal3(1509).fbm(q, 1.2, 5) * 0.5 + 0.5          # violet <-> teal provinces
    terr = Fractal3(1510).fbm(q, 2.2, 7) * 0.5 + 0.5
    det = Fractal3(1513).fbm(d, 28.0, 3) * 0.5 + 0.5
    plate_seeds = seeds(130, 1521)
    i1, e1, _ = voronoi(nrm(warp(d, 1520, 2.2, 0.05)), plate_seeds)
    reg_seed = Fractal3(1509).fbm(warp(plate_seeds[None, :, :], 1501, 1.3, 0.3), 1.2, 5)[0] * 0.5 + 0.5
    i2, e2, _ = voronoi(nrm(warp(d, 1530, 4.0, 0.03)), seeds(1400, 1531, relax=1))
    r1 = cell_rand(i1, 1522, 3)
    r2 = cell_rand(i2, 1532, 2)
    t = np.clip(0.7 * reg_seed[i1] + 0.3 * region + (r1[..., 0] - 0.5) * 0.2, 0, 1)
    violet = mix(c(0.33, 0.16, 0.54), c(0.52, 0.30, 0.76), terr)
    teal = mix(c(0.08, 0.31, 0.35), c(0.22, 0.54, 0.55), terr)
    col = mix(violet, teal, smoothstep(0.42, 0.58, t))
    # plates sit at slightly different levels; inside crystal fields every facet catches light differently
    col *= (0.88 + 0.24 * r1[..., 1])[..., None]
    field = smoothstep(0.45, 0.62, Fractal3(1534).fbm(warp(d, 1535, 1.6, 0.2), 1.8, 5) * 0.5 + 0.5)
    col *= (1.0 + field * (r2[..., 0] - 0.5) * 0.55)[..., None]
    col *= (0.88 + 0.24 * (Fractal3(1533).fbm(d, 9.0, 3) * 0.5 + 0.5))[..., None]
    # deep crystal basins (dark) and bright salt-like crystal plains
    basin = smoothstep(0.64, 0.76, Fractal3(1540).fbm(warp(d, 1541, 1.6, 0.3), 1.8, 6) * 0.5 + 0.5)
    col = mix(col, c(0.08, 0.06, 0.17), basin * 0.8)
    plain = smoothstep(0.66, 0.8, Fractal3(1542).fbm(q, 2.6, 5) * 0.5 + 0.5) * (1 - field)
    col = mix(col, mix(c(0.72, 0.66, 0.86), c(0.64, 0.82, 0.82), smoothstep(0.38, 0.62, t)), plain * 0.55)
    # pale veins: thin plate borders, faint facet borders, meandering ridged veins
    v1 = line_mask(e1, 0.0016) * 0.75
    v2 = line_mask(e2, 0.0007) * field * 0.35
    vr = Fractal3(1550).ridged(warp(d, 1551, 2.2, 0.25), 3.2, 6, sharp=12.0)
    v3 = smoothstep(0.62, 0.92, vr) * 0.75
    veins = np.clip(v1 + v2 + v3, 0, 1)
    vein_col = mix(c(0.88, 0.82, 0.97), c(0.82, 0.96, 0.95), smoothstep(0.4, 0.6, t))
    col = mix(col, vein_col, veins * 0.8)
    glit = smoothstep(0.90, 0.98, r2[..., 1]) * field * 0.22
    col = mix(col, c(0.86, 0.84, 0.97), glit)
    alat = np.abs(lat) / (np.pi / 2)
    col = mix(col, c(0.84, 0.84, 0.94), smoothstep(0.90, 0.97, alat + 0.03 * Fractal3(1560).fbm(d, 4, 4)) * 0.7)
    return col * (0.92 + 0.16 * det)[..., None], None


def home_h(d):
    q = warp(d, 1601, 1.25, 0.28)
    return Fractal3(1610).fbm(q, 1.3, 9, gain=0.52) + 0.25 * Fractal3(1612).ridged(q, 3.0, 6, sharp=2.4)


def alien_home(d, lat, lon):
    h = home_h(d)
    sea_level = 0.24
    land = h > sea_level
    shade = relief(home_h, d, h, k=0.6) * land
    det = Fractal3(1613).fbm(d, 26.0, 4) * 0.5 + 0.5
    elev = np.clip((h - sea_level) / 0.6, 0, 1)
    # obsidian continents with glassy flow bands
    flowb = Fractal3(1611).fbm(warp(d, 1620, 2.0, 0.25), 2.5, 6) * 0.5 + 0.5
    obs = gradient_map(flowb, [(0.0, c(0.07, 0.05, 0.10)), (0.4, c(0.13, 0.09, 0.18)), (0.7, c(0.20, 0.14, 0.26)),
                               (1.0, c(0.11, 0.08, 0.15))])
    obs = mix(obs, c(0.30, 0.24, 0.35), smoothstep(0.35, 0.8, elev) * 0.45)
    obs = obs * (1.0 + 0.45 * shade)[..., None] * (0.85 + 0.3 * det)[..., None]
    # magenta-tinted seas: smooth depth gradient, bright shallows along the coasts
    depth = np.clip((sea_level - h) / 0.75, 0, 1)
    sea = mix(c(0.48, 0.15, 0.40), c(0.32, 0.07, 0.29), smoothstep(0.0, 0.14, depth))
    sea = mix(sea, c(0.15, 0.025, 0.17), smoothstep(0.18, 1.0, depth))
    swirl = Fractal3(1614).fbm(warp(d, 1615, 3.0, 0.2), 4.0, 4) * 0.5 + 0.5
    sea *= (0.94 + 0.12 * swirl)[..., None]
    # ---- artificial megastructures ------------------------------------------------------------
    rng = np.random.default_rng(1630)
    rotA = random_rotation(rng)
    rotB = random_rotation(rng)
    dev = smoothstep(0.34, 0.56, Fractal3(1631).fbm(d, 1.5, 5) * 0.5 + 0.5)
    dev = dev * smoothstep(sea_level - 0.01, sea_level + 0.05, h)
    pts = seeds(54, 1632)
    i1, i2, e_sec, n_sec, a_hub = voronoi_full(d, pts)
    hub = np.exp(-(a_hub / 0.16) ** 2)                                     # cities cluster around sector hubs
    on_land = smoothstep(sea_level - 0.02, sea_level + 0.02, h)
    causeway = (pair_rand(i1, i2, 7) < 0.18).astype(F32)
    hw = line_mask(e_sec, 0.0020) * np.clip(on_land + causeway, 0, 1)
    node = smoothstep(0.028, 0.0, n_sec) * on_land
    g1 = line_mask(grid_dist(d, rotA, 56), 0.0010)
    g2 = line_mask(grid_dist(d, rotB, 180), 0.0005)
    grid = np.clip(g1 + g2 * 0.9, 0, 1) * dev * (0.25 + 0.75 * hub)
    blocks = smoothstep(0.55, 0.75, Fractal3(1634).fbm(d, 60.0, 2) * 0.5 + 0.5) * dev * hub
    rings = np.zeros(d.shape[:-1], F32)
    ring_fill = np.zeros(d.shape[:-1], F32)
    rr = np.random.default_rng(1641)
    for k in range(len(pts)):
        if rr.random() < 0.22:
            r0 = rr.uniform(0.06, 0.12)
            dist, ang = ring_dist(d, pts[k], r0)
            rings += line_mask(dist, 0.0020)
            dist2, _ = ring_dist(d, pts[k], r0 * 0.66)
            rings += line_mask(dist2, 0.0013) * 0.8
            dist3, _ = ring_dist(d, pts[k], r0 * 0.3)
            rings += line_mask(dist3, 0.0013) * 0.7
            ring_fill += smoothstep(r0 * 1.01, r0 * 0.97, ang) * 0.6
    rings = np.clip(rings, 0, 1) * np.clip(on_land + 0.35, 0, 1)
    ring_fill = np.clip(ring_fill, 0, 1) * land
    plating = c(0.32, 0.26, 0.38)
    alb = np.where(land[..., None], obs, sea)
    alb = mix(alb, c(0.18, 0.13, 0.24), ring_fill * 0.6)
    alb = mix(alb, plating * 0.8, blocks * 0.4)
    alb = mix(alb, plating, np.clip(grid * 0.6 + rings * 0.8 + hw * 0.7, 0, 1))
    alat = np.abs(lat) / (np.pi / 2)
    alb = mix(alb, c(0.40, 0.33, 0.46), smoothstep(0.90, 0.97, alat + 0.03 * Fractal3(1650).fbm(d, 4, 4)) * 0.6)
    # ---- emission: magenta / red light networks along the structures ---------------------------
    spark = Fractal3(1660).fbm(d, 90.0, 2) * 0.5 + 0.5
    city = smoothstep(0.42, 0.75, spark)
    along = Fractal3(1662).fbm(d, 24.0, 3) * 0.5 + 0.5
    hue = smoothstep(0.35, 0.65, Fractal3(1661).fbm(d, 3.0, 3) * 0.5 + 0.5)
    lights = (grid * (0.4 + 0.8 * city) + rings * 0.95 + hw * (0.35 + 0.65 * along) * (0.5 + 0.5 * on_land)
              + node * 1.2 + blocks * city * 0.3 + hub * dev * city * 0.15)
    lights = np.clip(lights, 0, 1.4)
    ecol = mix(c(1.0, 0.16, 0.62), c(1.0, 0.16, 0.10), hue)
    emis = ecol * np.clip(lights, 0, 1)[..., None] * 0.95
    emis = emis + c(1.0, 0.78, 0.92) * np.clip(lights - 1.0, 0, 0.4)[..., None]
    return alb, emis


TYPES = {"alien_crimson": alien_crimson, "alien_spore": alien_spore, "alien_ash": alien_ash,
         "alien_crystal": alien_crystal, "alien_home": alien_home}


def work(args):
    name, r0, r1 = args
    d, lat, lon = dirs_band(r0, r1)
    alb, extra = TYPES[name](d, lat, lon)
    return r0, alb.astype(F32), None if extra is None else extra.astype(F32)


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
        im = Image.open(os.path.join(OUT, name + ".png"))
        im.resize((512, 256), Image.LANCZOS).save(os.path.join(PREV, "planet_%s.png" % name))
        if extra is not None:
            Image.open(os.path.join(OUT, name + "_emission.png")).resize((512, 256), Image.LANCZOS).save(
                os.path.join(PREV, "planet_%s_emission.png" % name))


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(TYPES)
    for nm in names:
        build(nm, "--preview" in sys.argv)
