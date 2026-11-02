"""
model_alien_cities.py - hostile ALIEN cities (3 variants) + a destroyed alien city for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_alien_cities.py [a] [b] [c] [ruins] [--preview]
Output: assets/models/alien_city_a.glb, alien_city_b.glb, alien_city_c.glb, alien_city_ruins.glb
Conventions identical to the human cities (model_cities.py): metres, +Z up, origin = GROUND CENTRE
(z = 0 is the ground), footprint diameter 36-44 m, max height ~28 m, intact cities carry an empty
"Beacon" at their highest point.

Design language (deliberately the opposite of the friendly white/cyan domes):
  dark purple-black obsidian/chitin hull, pale bone ribs, fluted claw-like spires with glowing
  magenta veins in the grooves, red-orange slit windows, violet crystals, star-shaped bases with
  curved talons gripping the ground.
  a) hive: cluster of ribbed, inward-leaning hive spires around a tall central needle
  b) crystal citadel: stepped hexagonal fortress crowned by a huge crystal, ring of tilted crystal pylons
  c) carapace: segmented ribbed shell with flying-buttress ribs, a needle antenna tower and a dish

Materials (Principled BSDF): AlienHull, AlienHullLight, AlienGlow (#ff2a6d, 4.0), AlienWindows (red-orange, 2.6),
AlienCrystal (violet, 2.0). Ruins: Charred, AlienHull, Embers (1.5).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

TAU = 2.0 * math.pi
HULL, LIGHT, GLOW, WIN, CRYS = range(5)


def lin(hexstr):
    """'#rrggbb' (sRGB) -> linear RGB tuple (Blender colour inputs are scene-linear)."""
    h = hexstr.lstrip("#")

    def ch(s):
        v = int(s, 16) / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (ch(h[0:2]), ch(h[2:4]), ch(h[4:6]))


def mats():
    """Material list in slot order HULL, LIGHT, GLOW, WIN, CRYS."""
    return [
        B.mat("AlienHull", lin("#35244b"), 0.30, 0.34, coat=0.3),
        B.mat("AlienHullLight", lin("#c3b8c9"), 0.10, 0.46),
        B.mat("AlienGlow", lin("#ff2a6d"), 0.0, 0.35, emission=lin("#ff2a6d"), strength=4.0),
        B.mat("AlienWindows", lin("#ff4d14"), 0.0, 0.40, emission=lin("#ff4510"), strength=2.6),
        B.mat("AlienCrystal", lin("#4a1080"), 0.0, 0.06, emission=lin("#a032ff"), strength=2.0, coat=0.5, spec=0.6),
    ]


# ------------------------------------------------------------------------------------------------
# geometry helpers (all return bmesh objects; material indices are set per face)
# ------------------------------------------------------------------------------------------------
def V(x, y, z):
    return Vector((x, y, z))


def loft(rings, cap0=True, cap1=True, tip0=None, tip1=None):
    """Loft through point rings (each a list of Vector, same length, CCW seen from the +axis end).
    Returns (bm, grid, caps); grid[band][j] = face between ring band and band+1, column j."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    grid = []
    if tip0 is not None:
        tv = bm.verts.new(tip0)
        grid.append([bm.faces.new((vr[0][(i + 1) % n], vr[0][i], tv)) for i in range(n)])
    for a, b in zip(vr[:-1], vr[1:]):
        grid.append([bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])) for i in range(n)])
    if tip1 is not None:
        tv = bm.verts.new(tip1)
        grid.append([bm.faces.new((vr[-1][i], vr[-1][(i + 1) % n], tv)) for i in range(n)])
    caps = []
    if cap0 and tip0 is None:
        caps.append(bm.faces.new(list(reversed(vr[0]))))
    if cap1 and tip1 is None:
        caps.append(bm.faces.new(vr[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm, grid, caps


def ngon(cx, cy, z, r, n, rot=0.0, sx=1.0, sy=1.0):
    return [V(cx + sx * r * math.cos(rot + TAU * k / n), cy + sy * r * math.sin(rot + TAU * k / n), z) for k in range(n)]


def flute(cx, cy, z, ro, ri, m, rot=0.0, gw=0.2):
    """Fluted (star) section: m ridges at radius ro, m narrow groove floors (width gw) at radius ri.
    Column layout per ridge k: 3k = facet, 3k+1 = groove floor, 3k+2 = facet."""
    pts = []
    for k in range(m):
        a = rot + TAU * k / m
        pts.append(V(cx + ro * math.cos(a), cy + ro * math.sin(a), z))
        am = a + math.pi / m
        d = min(gw / (2.0 * max(ri, 1e-3)), math.pi / m * 0.28)
        for s in (-d, d):
            pts.append(V(cx + ri * math.cos(am + s), cy + ri * math.sin(am + s), z))
    return pts


def cone(p0, p1, r, sides=4, rot=0.0, flat=1.0):
    """Pointed cone/thorn from base centre p0 to tip p1."""
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0).normalized()
    ref = V(0, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0)
    u = ax.cross(ref).normalized()
    v = ax.cross(u).normalized()
    ring = [p0 + (u * math.cos(rot + TAU * k / sides) + v * math.sin(rot + TAU * k / sides) * flat) * r
            for k in range(sides)]
    bm, grid, caps = loft([ring], cap0=True, tip1=p1)
    return bm


def frames(path, up=V(0, 0, 1)):
    """Rotation-minimising frames along a polyline: tangents T, normals N (start aligned to `up`)."""
    n = len(path)
    T = []
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        T.append((b - a).normalized())
    N0 = up - T[0] * up.dot(T[0])
    if N0.length < 1e-4:
        N0 = V(1, 0, 0) - T[0] * T[0].x
    N = [N0.normalized()]
    for i in range(1, n):
        q = T[i - 1].rotation_difference(T[i])
        Ni = q @ N[i - 1]
        N.append((Ni - T[i] * Ni.dot(T[i])).normalized())
    return T, N


def sweep(path, widths, heights=None, profile=None, sides=4, tip=True, up=V(0, 0, 1), rot=0.0, tip0=False):
    """Sweep a 2D profile ((u = lateral, v = up) unit coords) along a path; ends in a point if tip
    (and starts in a point if tip0)."""
    path = [Vector(p) for p in path]
    T, N = frames(path, up)
    if profile is None:
        profile = [(math.cos(rot + TAU * k / sides), math.sin(rot + TAU * k / sides)) for k in range(sides)]
    rings = []
    first = 1 if tip0 else 0
    last = len(path) - 1 if tip else len(path)
    for i in range(first, last):
        Bv = T[i].cross(N[i])
        w = widths[i]
        h = heights[i] if heights is not None else w
        rings.append([path[i] + Bv * (u * w) + N[i] * (v * h) for (u, v) in profile])
    bm, grid, caps = loft(rings, cap0=True, cap1=not tip, tip0=path[0] if tip0 else None,
                          tip1=path[-1] if tip else None)
    return bm, grid


def bezier(p0, p1, p2, n, p3=None):
    """Quadratic (or cubic if p3) Bezier sampled with n points."""
    p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
    out = []
    for i in range(n):
        t = i / (n - 1)
        if p3 is None:
            out.append(p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t)
        else:
            out.append(p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + Vector(p3) * t ** 3)
    return out


def slit(bm, faces, wf=0.3, hf=0.75, depth=0.08, mat=WIN, up=V(0, 0, 1)):
    """Recessed slit in each face: inner face scaled by wf (across) / hf (along `up`), pushed in by depth."""
    faces = [f for f in faces if f.is_valid]
    if not faces:
        return
    bm.normal_update()
    info = []
    for f in faces:
        c = f.calc_center_median()
        n = f.normal.copy()
        u = n.cross(up)
        if u.length < 1e-4:
            u = n.cross(V(1, 0, 0))
        u.normalize()
        v = u.cross(n).normalized()
        info.append((c, n, u, v))
    bmesh.ops.inset_individual(bm, faces=faces, thickness=0.0, depth=0.0, use_even_offset=False)
    for f, (c, n, u, v) in zip(faces, info):
        f.material_index = mat
        for vert in f.verts:
            d = vert.co - c
            vert.co = c + u * (d.dot(u) * wf) + v * (d.dot(v) * hf) + n * (d.dot(n) - depth)


def transform(bm, mat3=None, loc=None, cent=V(0, 0, 0)):
    if mat3 is not None:
        bmesh.ops.rotate(bm, cent=cent, matrix=mat3, verts=bm.verts)
    if loc is not None:
        bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return bm


def set_mat(bm, idx):
    for f in bm.faces:
        f.material_index = idx
    return bm


def part(M, name, bm, bevel_w=None, seg=1, angle=35.0, smooth=35.0, wn=True):
    return B.part(name, bm, M, bevel_w=bevel_w, seg=seg, angle=angle, wn=wn, smooth=smooth)


# ------------------------------------------------------------------------------------------------
# building blocks
# ------------------------------------------------------------------------------------------------
def star_slab(M, n, apothem, h, batter=1.0, vein_w=0.32, rot=0.0, hub=2.2, name="slab"):
    """n-gon foundation with battered walls; glowing radial veins from the hub to every edge midpoint
    (edge midpoints are the talon directions rot + k*TAU/n)."""
    def ring(A, z, w):
        pts = []
        for k in range(n):
            a = rot + TAU * k / n
            c = V(A * math.cos(a), A * math.sin(a), z)
            t = V(-math.sin(a), math.cos(a), 0)
            pts += [c - t * (w * 0.5), c + t * (w * 0.5)]
            ac = a + math.pi / n
            R = A / math.cos(math.pi / n)
            pts.append(V(R * math.cos(ac), R * math.sin(ac), z))
        return pts
    rings = [ring(apothem + batter, 0.0, vein_w * 1.3), ring(apothem, h, vein_w), ring(hub, h, vein_w * 0.8)]
    bm, grid, caps = loft(rings, cap0=True, cap1=True)
    for row in grid:
        for j, f in enumerate(row):
            if j % 3 == 0:
                f.material_index = GLOW
    return part(M, name, bm, bevel_w=0.12, angle=30)


TALON_PROF = [(-1.0, 0.0), (-0.80, 0.52), (-0.24, 1.0), (-0.09, 0.84), (0.09, 0.84), (0.24, 1.0), (0.80, 0.52),
              (1.0, 0.0)]


def talon(M, a, r0, r1, w0, h0, curl=0.22, z=0.0, name="talon", npts=7, bone_from=0.72):
    """Curved, ridged claw lying on the ground from radius r0 to a point at r1 (direction angle a);
    a glowing groove runs along its spine, the last part is a pale bone claw tip."""
    path = []
    for i in range(npts):
        t = i / (npts - 1)
        r = r0 + (r1 - r0) * t
        aa = a + curl * t * t
        path.append(V(r * math.cos(aa), r * math.sin(aa), z))
    ts = [i / (npts - 1) for i in range(npts)]
    widths = [w0 * (1.0 - 0.9 * t ** 1.3) for t in ts]
    heights = [h0 * (0.82 + 0.5 * math.sin(math.pi * min(1.0, t * 1.6)) * (1 - t)) * (1.0 - 0.85 * t ** 1.2) for t in ts]
    bm, grid = sweep(path, widths, heights, profile=TALON_PROF, tip=True)
    for bi, row in enumerate(grid):
        t = ts[bi]
        for j, f in enumerate(row):
            if t >= bone_from - 1e-6:
                f.material_index = LIGHT
            elif j == 3 and t > 0.05:
                f.material_index = GLOW
    return part(M, name, bm, bevel_w=0.04, angle=45)


def spire(x, y, z0, h, r0, prof, m=5, inner=0.7, gw=0.22, twist=0.35, lean=(0.0, 0.0), lean_pow=2.0,
          glow_from=0.0, glow_to=1.1, rot=0.0, groove_mat=GLOW):
    """Fluted spire (ridges + glowing grooves) ending in a point. prof: [(t, radius factor)], t in [0, 1)."""
    rings, ts = [], []
    for (t, rf) in prof:
        lx, ly = lean[0] * t ** lean_pow, lean[1] * t ** lean_pow
        ro = r0 * rf
        rings.append(flute(x + lx, y + ly, z0 + t * h, ro, ro * inner, m, rot + twist * t, gw))
        ts.append(t)
    tip = V(x + lean[0], y + lean[1], z0 + h)
    bm, grid, caps = loft(rings, cap0=True, tip1=tip)
    for bi, row in enumerate(grid):
        t = ts[bi]
        if glow_from - 1e-6 <= t <= glow_to:
            for j, f in enumerate(row):
                if j % 3 == 1:
                    f.material_index = groove_mat
    return bm, grid, ts


def spire_axis(x, y, z0, h, lean, lean_pow, t):
    return V(x + lean[0] * t ** lean_pow, y + lean[1] * t ** lean_pow, z0 + t * h)


def collar(c, r, sides, h=0.55, lip=1.07, tilt=(0.0, 0.0), rot=0.0, mat=LIGHT):
    """Bone ring around a spire at centre c (optionally tilted -> organic look)."""
    cx, cy, z = c
    rings = [ngon(cx, cy, z - h / 2, r * 0.97, sides, rot), ngon(cx, cy, z, r * lip, sides, rot),
             ngon(cx, cy, z + h / 2, r * 0.97, sides, rot)]
    bm, grid, caps = loft(rings)
    if tilt != (0.0, 0.0):
        transform(bm, Euler((tilt[0], tilt[1], 0.0)).to_matrix(), cent=V(cx, cy, z))
    return set_mat(bm, mat)


def pod(c, r, h, sides=6, rot=0.0, mat=HULL, tipmat=LIGHT):
    """Squat faceted pod (hexagonal bipyramid-ish) sitting on the ground at c."""
    cx, cy, z = c
    rings = [ngon(cx, cy, z, r * 0.8, sides, rot), ngon(cx, cy, z + h * 0.35, r, sides, rot),
             ngon(cx, cy, z + h * 0.62, r * 0.72, sides, rot + 0.0)]
    bm, grid, caps = loft(rings, cap0=True, tip1=V(cx, cy, z + h))
    set_mat(bm, mat)
    for f in grid[-1]:
        f.material_index = tipmat
    return bm


# ------------------------------------------------------------------------------------------------
# city A: hive spires around a central needle
# ------------------------------------------------------------------------------------------------
HIVE_PROF = [(0.0, 1.0), (0.07, 1.10), (0.20, 1.16), (0.34, 1.06), (0.48, 0.86), (0.62, 0.64), (0.75, 0.44),
             (0.86, 0.27), (0.94, 0.14)]
SLIM_PROF = [(0.0, 1.0), (0.10, 1.04), (0.24, 0.98), (0.40, 0.84), (0.56, 0.66), (0.70, 0.47), (0.82, 0.30),
             (0.92, 0.15)]
NEEDLE_PROF = [(0.0, 1.0), (0.05, 1.10), (0.13, 1.12), (0.24, 0.96), (0.36, 0.78), (0.48, 0.62), (0.60, 0.47),
               (0.72, 0.33), (0.83, 0.21), (0.92, 0.11)]


def _prof_r(prof, t):
    for (t0, r0), (t1, r1) in zip(prof[:-1], prof[1:]):
        if t0 <= t <= t1:
            return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    return prof[-1][1]


def crystal(c, r, length, sides=6, axis=V(0, 0, 1), rot=0.0, base_frac=0.18, top_frac=0.35, mat=CRYS):
    """Elongated crystal (bipyramid with prism body) from base point c along axis."""
    c = Vector(c)
    ax = Vector(axis).normalized()
    ref = V(0, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0)
    u = ax.cross(ref).normalized()
    v = ax.cross(u).normalized()

    def ring(d, rr):
        return [c + ax * d + (u * math.cos(rot + TAU * k / sides) + v * math.sin(rot + TAU * k / sides)) * rr
                for k in range(sides)]
    rings = [ring(length * base_frac, r), ring(length * (1 - top_frac), r * 0.92)]
    bm, grid, caps = loft(rings, tip0=c, tip1=c + ax * length)
    return set_mat(bm, mat)


def hive_spire(M, P, x, y, z0, h, r0, rng, name, lean_in=1.4, m=5, prof=HIVE_PROF, ribs=(0.42, 0.66),
               twist=0.45, thorns=0, glow_from=0.40):
    # lean toward the centre (claws closing around the needle)
    d = Vector((-x, -y)).normalized() * lean_in
    lean = (d.x, d.y)
    rot = math.atan2(y, x) + rng.uniform(-0.3, 0.3)
    bm, grid, ts = spire(x, y, z0, h, r0, prof, m=m, inner=0.70, gw=0.24, twist=twist, lean=lean,
                         glow_from=glow_from, rot=rot)
    # narrow slit windows in the bulb (bands 1..2), every other facet, staggered
    faces = []
    for bi in (1, 2):
        for j, f in enumerate(grid[bi]):
            if j % 3 != 1 and (j // 3 + bi) % 2 == 0:
                faces.append(f)
    slit(bm, faces, wf=0.17, hf=0.70, depth=0.12, mat=WIN)
    P.append(part(M, name, bm))
    # bone ribs (tilted collars)
    for k, t in enumerate(ribs):
        c = spire_axis(x, y, z0, h, lean, 2.0, t)
        rf = r0 * _prof_r(prof, t)
        tilt = (rng.uniform(-0.14, 0.14), rng.uniform(-0.14, 0.14))
        P.append(part(M, name + "_rib", collar(c, rf * 1.04, 2 * m, h=0.55 - 0.12 * k, tilt=tilt, rot=rot), wn=False))
    # optional thorns sticking out of the bulb, curving upward
    if thorns:
        th = bmesh.new()
        t = 0.30
        c = spire_axis(x, y, z0, h, lean, 2.0, t)
        rf = r0 * _prof_r(prof, t)
        for k in range(thorns):
            a = rot + 0.45 * t + TAU * (k + 0.5) / thorns
            dv = V(math.cos(a), math.sin(a), 0)
            p0 = c + dv * (rf * 0.6)
            p1 = c + dv * (rf + 1.0) + V(0, 0, 0.2)
            p2 = c + dv * (rf + 1.9) + V(0, 0, 1.6)
            bmk, _ = sweep(bezier(p0, p1, p2, 4), [0.36, 0.28, 0.16, 0.0], sides=4, tip=True)
            B.merge_bm(th, set_mat(bmk, LIGHT))
        P.append(part(M, name + "_thorns", th, smooth=30))
    return V(x + lean[0], y + lean[1], z0 + h)


def city_a():
    B.reset()
    M = mats()
    rng = random.Random(11)
    P = []
    n = 7
    rot = math.pi / 2
    base_h = 1.0
    P.append(star_slab(M, n, 12.4, base_h, batter=1.1, rot=rot, name="slab"))
    for k in range(n):
        a = rot + TAU * k / n
        P.append(talon(M, a, 10.2, 19.6, 2.0, 2.3, curl=0.30, name="talon%d" % k))
    # central needle
    NH = 26.8
    bm, grid, ts = spire(0, 0, base_h, NH, 2.75, NEEDLE_PROF, m=5, inner=0.68, gw=0.26, twist=0.6, rot=rot)
    faces = [f for j, f in enumerate(grid[1]) if j % 3 != 1]
    slit(bm, faces, wf=0.16, hf=0.66, depth=0.12, mat=WIN)
    P.append(part(M, "needle", bm))
    for k, (t, hh) in enumerate(((0.30, 0.75), (0.53, 0.6), (0.71, 0.5))):
        rf = _prof_r(NEEDLE_PROF, t) * 2.75
        P.append(part(M, "needle_rib", collar((0, 0, base_h + NH * t), rf * 1.05, 10, h=hh, rot=rot + 0.6 * t),
                      wn=False))
    # thorn crown + violet crystal shards on the needle
    t = 0.40
    z = base_h + NH * t
    rf = _prof_r(NEEDLE_PROF, t) * 2.75
    th = bmesh.new()
    cr = bmesh.new()
    for k in range(5):
        a = rot + 0.6 * t + TAU * k / 5
        p0 = V(rf * 0.6 * math.cos(a), rf * 0.6 * math.sin(a), z)
        p1 = V((rf + 1.5) * math.cos(a), (rf + 1.5) * math.sin(a), z + 0.2)
        p2 = V((rf + 2.8) * math.cos(a + 0.2), (rf + 2.8) * math.sin(a + 0.2), z + 2.6)
        bmk, _ = sweep(bezier(p0, p1, p2, 5), [0.5, 0.4, 0.3, 0.17, 0.0], sides=4, tip=True)
        B.merge_bm(th, set_mat(bmk, LIGHT))
        a2 = a + TAU / 10
        B.merge_bm(cr, crystal(V(rf * 0.55 * math.cos(a2), rf * 0.55 * math.sin(a2), z - 0.4), 0.42, 3.4, sides=5,
                               axis=V(math.cos(a2) * 0.55, math.sin(a2) * 0.55, 1.0), rot=a2))
    P.append(part(M, "thorns", th, smooth=30))
    P.append(part(M, "crystals", cr, smooth=20, wn=False))
    # hive spires (one sector left free for a crystal garden)
    cfg = [  # height, radius, profile, ribs, thorns, ridges, twist
        (17.8, 2.95, HIVE_PROF, (0.42, 0.66), 0, 5, 0.45),
        (12.2, 2.40, SLIM_PROF, (0.50,), 4, 5, -0.5),
        (15.0, 2.70, HIVE_PROF, (0.40, 0.62), 0, 6, 0.35),
        (10.4, 2.25, HIVE_PROF, (0.48,), 3, 5, -0.4),
        (16.4, 2.80, SLIM_PROF, (0.38, 0.60), 0, 6, 0.5),
        (11.6, 2.35, HIVE_PROF, (0.52,), 0, 5, -0.45),
    ]
    for k, (hh, rr0, prof, ribs, thn, m, tw) in enumerate(cfg):
        a = rot + TAU * (k + 0.5) / n
        rr = 9.0 + rng.uniform(-0.3, 0.4)
        hive_spire(M, P, rr * math.cos(a), rr * math.sin(a), base_h, hh, rr0, rng, "spire%d" % k, prof=prof,
                   ribs=ribs, thorns=thn, m=m, twist=tw, lean_in=1.0 + 0.06 * hh)
    # crystal garden + pods in the free sector
    a = rot + TAU * 6.5 / n
    pods = bmesh.new()
    cr = bmesh.new()
    for (dr, da, r, h) in ((7.0, 0.30, 1.4, 2.8), (7.3, -0.30, 1.2, 2.4)):
        B.merge_bm(pods, pod((dr * math.cos(a + da), dr * math.sin(a + da), base_h), r, h, rot=rng.uniform(0, 1)))
    cc = V(9.8 * math.cos(a), 9.8 * math.sin(a), base_h - 0.3)
    for k, (L, rr, tx, ty) in enumerate(((6.0, 0.85, 0.0, 0.0), (4.2, 0.6, 0.45, 0.2), (4.6, 0.65, -0.4, 0.3),
                                          (3.2, 0.5, 0.2, -0.5), (3.6, 0.5, -0.3, -0.45))):
        off = V(tx * 1.6, ty * 1.6, 0)
        B.merge_bm(cr, crystal(cc + off, rr, L, sides=6, axis=V(tx, ty, 1.0), rot=k * 0.7))
    P.append(part(M, "pods", pods, bevel_w=0.03, angle=40))
    P.append(part(M, "garden", cr, smooth=20, wn=False))
    ob = B.join(P, "AlienCityA")
    beacon_at_top(ob)
    return ob


def beacon_at_top(ob, name="Beacon"):
    """Empty at the highest vertex of the joined mesh."""
    top = max(ob.data.vertices, key=lambda v: v.co.z)
    B.empty(name, tuple(top.co))
    return top.co


# ------------------------------------------------------------------------------------------------
# city B: crystal citadel - stepped hexagonal fortress crowned by a huge crystal, ring of tilted pylons
# ------------------------------------------------------------------------------------------------
def hex_ring(A, z, rot, seg=3, n=6):
    """Points of an n-gon with apothem A (edge midpoints at rot + k*TAU/n), each edge split into seg parts."""
    R = A / math.cos(math.pi / n)
    pts = []
    for k in range(n):
        a0 = rot + TAU * k / n - math.pi / n
        a1 = a0 + TAU / n
        p0 = V(R * math.cos(a0), R * math.sin(a0), z)
        p1 = V(R * math.cos(a1), R * math.sin(a1), z)
        for i in range(seg):
            pts.append(p0.lerp(p1, i / seg))
    return pts


def tier(M, z0, z1, a0, a1, rot, seam=True, win_cols=(1,), seg=3, name="tier", n=6):
    """Battered hexagonal tier (apothem a0 at the bottom, a1 at the top) with a recessed glowing seam
    under the parapet and slit windows in the given wall columns."""
    h = z1 - z0
    lerp = lambda t: a0 + (a1 - a0) * t  # noqa: E731
    zs = [(z0, a0)]
    seam_rows = []
    if seam:
        t0, t1 = 0.80, 0.88
        zs += [(z0 + h * t0, lerp(t0)), (z0 + h * t0 + 0.02, lerp(t0) - 0.16), (z0 + h * t1, lerp(t1) - 0.16),
               (z0 + h * t1 + 0.02, lerp(t1))]
        seam_rows = [2]
    zs.append((z1, a1))
    rings = [hex_ring(A, z, rot, seg, n) for (z, A) in zs]
    rings.append(hex_ring(a1 - 0.45, z1, rot, seg, n))      # parapet top -> terrace
    rings.append(hex_ring(a1 - 0.45, z1 - 0.35, rot, seg, n))  # sunken terrace floor
    bm, grid, caps = loft(rings, cap0=True, cap1=True)
    for r in seam_rows:
        for f in grid[r]:
            f.material_index = GLOW
    wall = grid[0]
    faces = [f for j, f in enumerate(wall) if (j % seg) in win_cols]
    slit(bm, faces, wf=0.11, hf=0.72, depth=0.15, mat=WIN)
    return part(M, name, bm, bevel_w=0.06, angle=30)


def blade(p0, p1, w, t=0.18, lean=V(0, 0, 0), mat=LIGHT):
    """Thin bone blade/fin from p0 to a point p1 (diamond section), slightly curved by `lean`."""
    p0, p1 = Vector(p0), Vector(p1)
    mid = (p0 + p1) * 0.5 + Vector(lean)
    path = bezier(p0, mid, p1, 5)
    prof = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
    bm, grid = sweep(path, [w, w * 0.85, w * 0.62, w * 0.35, 0], [t, t * 0.9, t * 0.75, t * 0.5, 0], profile=prof,
                     tip=True, up=(p1 - p0).cross(V(0, 0, 1)) if abs((p1 - p0).normalized().z) > 0.95 else V(0, 0, 1))
    return set_mat(bm, mat)


def city_b():
    B.reset()
    M = mats()
    rng = random.Random(23)
    P = []
    rot = math.pi / 2          # pylons (edge midpoints) at 90, 150, ...; corners at 60, 120, ...
    base_h = 1.2
    P.append(star_slab(M, 6, 13.2, base_h, batter=1.2, rot=rot, hub=3.0, name="slab"))
    # corner bastion thorns (straight talons) at the hexagon corners
    for k in range(6):
        a = rot + TAU * (k + 0.5) / 6
        P.append(talon(M, a, 12.6, 20.0, 1.9, 2.6, curl=0.0, name="bastion%d" % k, bone_from=0.62))
    # fortress tiers, alternately rotated by 30 deg
    tiers = [(base_h, 6.8, 8.4, 7.3, rot + math.pi / 6, (0, 2)), (6.8 - 0.35, 11.4, 6.0, 5.1, rot, (1,)),
             (11.4 - 0.35, 14.6, 3.9, 3.3, rot + math.pi / 6, (1,))]
    for i, (z0, z1, a0, a1, r, wc) in enumerate(tiers):
        P.append(tier(M, z0, z1, a0, a1, r, win_cols=wc, name="tier%d" % i))
        # bone fins on the corners rising above the parapet
        if i < 2:
            R0 = a0 / math.cos(math.pi / 6)
            R1 = a1 / math.cos(math.pi / 6)
            fins = bmesh.new()
            for k in range(6):
                ac = r + TAU * k / 6 + math.pi / 6
                d = V(math.cos(ac), math.sin(ac), 0)
                p0 = d * (R0 * 0.93) + V(0, 0, z0 + 0.4)
                p1 = d * (R1 + 0.9) + V(0, 0, z1 + (3.0 if i == 0 else 2.4))
                B.merge_bm(fins, blade(p0, p1, 0.75 if i == 0 else 0.6, t=0.22, lean=d * 0.6))
            P.append(part(M, "fins%d" % i, fins, smooth=30, wn=False))
    # crown crystal gripped by bone claws
    ztop = 14.6 - 0.35
    P.append(part(M, "crown", crystal(V(0, 0, ztop - 1.0), 2.15, 28.0 - (ztop - 1.0), sides=6, rot=rot,
                                       base_frac=0.12, top_frac=0.42), smooth=20, wn=False))
    sat = bmesh.new()
    for k in range(3):
        a = rot + math.pi / 6 + TAU * k / 3
        d = V(math.cos(a), math.sin(a), 0)
        B.merge_bm(sat, crystal(d * 1.6 + V(0, 0, ztop - 0.6), 0.8, 6.2, sides=6, axis=d * 0.5 + V(0, 0, 1),
                                rot=a))
    P.append(part(M, "crown_sat", sat, smooth=20, wn=False))
    cl = bmesh.new()
    for k in range(3):
        a = rot + TAU * k / 3
        d = V(math.cos(a), math.sin(a), 0)
        p0 = d * 3.2 + V(0, 0, ztop - 0.2)
        p1 = d * 4.6 + V(0, 0, ztop + 3.6)
        p2 = d * 2.25 + V(0, 0, ztop + 7.6)
        bmk, _ = sweep(bezier(p0, p1, p2, 6), [0.65, 0.6, 0.5, 0.4, 0.26, 0.0], [0.5, 0.48, 0.42, 0.34, 0.22, 0.0],
                       profile=[(1, 0), (0.45, 1), (-0.45, 1), (-1, 0), (-0.45, -1), (0.45, -1)], tip=True,
                       up=-d)
        B.merge_bm(cl, set_mat(bmk, LIGHT))
    P.append(part(M, "crown_claws", cl, smooth=30))
    # ring of tilted crystal pylons in angular sockets, fed by the glowing veins
    lengths = [12.6, 10.2, 11.8, 9.6, 12.2, 10.6]
    for k in range(6):
        a = rot + TAU * k / 6
        d = V(math.cos(a), math.sin(a), 0)
        c = d * 12.4
        # socket: truncated hex pyramid
        rings = [ngon(c.x, c.y, base_h - 0.2, 2.5, 6, a), ngon(c.x, c.y, base_h + 2.0, 1.75, 6, a),
                 ngon(c.x, c.y, base_h + 2.0, 1.35, 6, a), ngon(c.x, c.y, base_h + 1.6, 1.35, 6, a)]
        bm, grid, caps = loft(rings, cap0=True, cap1=True)
        slit(bm, [grid[0][j] for j in (2, 3)], wf=0.2, hf=0.55, depth=0.1, mat=WIN)
        P.append(part(M, "socket%d" % k, bm, bevel_w=0.05, angle=30))
        tilt = math.radians(22 + rng.uniform(-3, 3))
        side = V(-d.y, d.x, 0) * rng.uniform(-0.12, 0.12)
        ax = (d * math.sin(tilt) + side + V(0, 0, math.cos(tilt))).normalized()
        P.append(part(M, "pylon%d" % k, crystal(c + V(0, 0, base_h + 0.6), 1.15, lengths[k], sides=6, axis=ax,
                                                 rot=a + 0.3, base_frac=0.1, top_frac=0.3), smooth=20, wn=False))
        # three short bone prongs gripping the crystal
        pr = bmesh.new()
        u = ax.cross(V(0, 0, 1)).normalized()
        w = ax.cross(u).normalized()
        for j in range(3):
            ang = TAU * j / 3 + 0.4
            o = (u * math.cos(ang) + w * math.sin(ang))
            p0 = c + V(0, 0, base_h + 1.8) + o * 1.45
            p1 = c + V(0, 0, base_h + 1.8) + o * 1.75 + ax * 1.6
            p2 = c + V(0, 0, base_h + 1.8) + o * 1.05 + ax * 3.4
            bmk, _ = sweep(bezier(p0, p1, p2, 4), [0.3, 0.26, 0.16, 0.0], sides=4, tip=True)
            B.merge_bm(pr, set_mat(bmk, LIGHT))
        P.append(part(M, "prongs%d" % k, pr, smooth=30, wn=False))
    ob = B.join(P, "AlienCityB")
    beacon_at_top(ob)
    return ob


# ------------------------------------------------------------------------------------------------
# city C: ribbed carapace with flying-buttress ribs, needle antenna tower and a dish
# ------------------------------------------------------------------------------------------------
def shell_sec(x, w, h, z0, k=12, lift=0.0):
    """Half-ellipse arch section in the YZ plane at x (k+1 points from +y over the top to -y)."""
    pts = []
    for i in range(k + 1):
        th = math.pi * i / k
        pts.append(V(x, w * math.cos(th), z0 + h * math.sin(th) + lift))
    return pts


def carapace(M, ax=12.0, ay=8.6, az=10.0, z0=0.8, plates=6, k=12):
    """Segmented shell: overlapping plates along x separated by recessed glowing seams.
    Front (+x) end is cut open into a glowing maw, the rear tapers to a blunt tail."""
    def size(x):
        u = min(abs(x) / ax, 1.0)
        f = (1.0 - u ** 2.2) ** 0.55
        return ay * f, az * f
    xs_front, xs_back = ax * 0.80, -ax * 0.97
    bounds = [xs_back + (xs_front - xs_back) * i / plates for i in range(1, plates)]
    secs = []  # (x, scale, is_seam)
    secs.append((xs_back, 1.0, False))
    for xb in bounds:
        secs += [(xb - 0.05, 1.0, False), (xb, 0.94, True), (xb + 0.32, 0.94, False), (xb + 0.36, 1.07, False)]
    secs.append((xs_front - 0.6, 1.02, False))
    secs.append((xs_front, 1.04, False))
    rings = []
    seam_bands = []
    for i, (x, sc, seam) in enumerate(secs):
        w, h = size(x)
        rings.append(shell_sec(x, w * sc, h * sc, z0, k))
        if seam:
            seam_bands.append(i)
    tail = V(-ax, 0, z0 + 0.6)
    bm, grid, caps = loft(rings, cap0=False, tip0=tail, cap1=True)
    # grid[0] is the tail fan -> band i of the loft is grid[i + 1]
    for bi in seam_bands:
        for j, f in enumerate(grid[bi + 1]):
            if j < k:  # arch faces only (not the hidden bottom)
                f.material_index = GLOW
    # gill slits low on the side of every plate
    faces = []
    for bi in range(len(secs) - 1):
        x0, x1 = secs[bi][0], secs[bi + 1][0]
        if x1 - x0 > 1.5:
            row = grid[bi + 1]
            for j in (1, k - 2):
                faces.append(row[j])
    slit(bm, faces, wf=0.62, hf=0.16, depth=0.12, mat=WIN)
    # the maw: front cap recessed and glowing
    front = caps[-1]
    slit(bm, [front], wf=0.72, hf=0.62, depth=1.2, mat=WIN)
    return bm, size, bounds, xs_front


def dish(c, axis, R=4.0, depth=1.1, ring_r=0.62, seg=16):
    """Parabolic dish (closed shell) centred at c facing `axis`; bone lip, glowing ring, crystal feed."""
    axis = Vector(axis).normalized()
    ref = V(0, 0, 1) if abs(axis.z) < 0.9 else V(1, 0, 0)
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()

    def ring(r, hgt):
        return [c + axis * hgt + (u * math.cos(TAU * i / seg) + v * math.sin(TAU * i / seg)) * r for i in range(seg)]
    prof_in = [(R * f, depth * f * f) for f in (0.25, 0.5, ring_r, ring_r + 0.06, 0.82, 1.0)]
    rings = [ring(r, z) for (r, z) in prof_in]
    rings += [ring(R * 1.04, depth + 0.12), ring(R * 1.0, depth - 0.32), ring(R * 0.55, -0.15), ring(R * 0.22, -0.55)]
    bm, grid, caps = loft(rings, tip0=c + axis * 0.0, tip1=c - axis * 0.75)
    for f in bm.faces:
        f.material_index = HULL
    for f in grid[3]:          # ring_r .. ring_r+0.06 band
        f.material_index = GLOW
    for bi in (6, 7):
        for f in grid[bi]:
            f.material_index = LIGHT
    # feed: crystal on three bone struts
    focus = c + axis * (R * R / (4 * depth) * 0.55)
    for i in range(3):
        a = TAU * i / 3 + 0.5
        rim = c + axis * depth + (u * math.cos(a) + v * math.sin(a)) * (R * 0.95)
        st, _ = sweep([rim, rim.lerp(focus, 0.5), focus], [0.13, 0.11, 0.09], sides=4, tip=False)
        B.merge_bm(bm, set_mat(st, LIGHT))
    B.merge_bm(bm, crystal(focus - axis * 0.5, 0.42, 2.0, sides=5, axis=axis))
    return bm


def city_c():
    B.reset()
    M = mats()
    rng = random.Random(37)
    P = []
    rot = 0.0
    base_h = 0.8
    P.append(star_slab(M, 8, 13.4, base_h, batter=1.0, rot=rot, hub=2.5, name="slab"))
    # talons only at the two ends and the diagonals
    for k in (0, 1, 2, 3, 4, 5):
        a = rot + TAU * k / 8
        P.append(talon(M, a, 12.0, 19.8, 1.8, 2.0, curl=0.18 if k % 2 else -0.18, name="talon%d" % k))
    # the shell
    AX, AY, AZ = 12.0, 8.6, 10.0
    bm, size, bounds, xs_front = carapace(M, AX, AY, AZ, base_h)
    P.append(part(M, "carapace", bm, smooth=32))
    # maw teeth (bone) around the front opening
    wF, hF = size(xs_front)
    wF, hF = wF * 1.04, hF * 1.04
    teeth = bmesh.new()
    for i in range(7):
        th = math.pi * (0.18 + 0.64 * i / 6)
        p0 = V(xs_front - 0.6, wF * 0.84 * math.cos(th), base_h + hF * 0.84 * math.sin(th))
        p1 = p0 + V(0.25, 0, -1.6 - 0.6 * math.sin(th))
        B.merge_bm(teeth, cone(p0, p1, 0.32, sides=4, rot=0.4))
    for yy in (-3.0, -1.0, 1.0, 3.0):
        p0 = V(xs_front - 0.5, yy, base_h + 0.1)
        B.merge_bm(teeth, cone(p0, p0 + V(0.2, 0, 1.5), 0.3, sides=4, rot=0.4))
    P.append(part(M, "teeth", set_mat(teeth, LIGHT), wn=False, smooth=30))
    # bone ribs over the plates, continuing into flying-buttress feet
    for i, xb in enumerate(bounds):
        xr = xb + 1.1
        w, h = size(xr)
        w *= 1.07
        h *= 1.07
        pts = []
        for side in (-1, 1):
            half = []
            half.append(V(xr - 0.4 * side * 0, side * (w + 4.4), 0.0))
            half.append(V(xr, side * (w + 2.6), 2.6))
            half.append(V(xr, side * (w + 0.55), base_h + h * 0.30))
            for j in range(1, 6):
                th = math.pi / 2 * (1 - j / 6.0)
                half.append(V(xr, side * (w + 0.45) * math.cos(th) * 1.0, base_h + (h + 0.45) * math.sin(th)))
            pts.append(half)
        path = pts[0] + [V(xr, 0, base_h + h + 0.45)] + list(reversed(pts[1]))
        nn = len(path)
        mid = nn // 2
        widths = [0.42 + 0.0 * abs(j - mid) for j in range(nn)]
        widths[0] = widths[-1] = 0.0
        widths[1] = widths[-2] = 0.5
        heights = [0.36 if abs(j - mid) < mid - 1 else 0.5 for j in range(nn)]
        rb, rg = sweep(path, widths, heights, profile=[(1, 0), (0.5, 1), (-0.5, 1), (-1, 0), (-0.5, -0.8), (0.5, -0.8)],
                       tip=True, tip0=True, up=V(1, 0, 0))
        P.append(part(M, "rib%d" % i, set_mat(rb, LIGHT), smooth=40))
    # dorsal glowing spine plate
    # needle antenna tower rising from the rear
    tx, ty = -6.4, 0.0
    NH = 28.0 - 3.0
    bm, grid, ts = spire(tx, ty, 3.0, NH, 1.55, SLIM_PROF, m=4, inner=0.66, gw=0.22, twist=0.0, glow_from=0.0,
                         lean=(1.1, 0.0), lean_pow=2.2, rot=math.pi / 4)
    P.append(part(M, "mast", bm))
    for j, t in enumerate((0.36, 0.55, 0.72)):
        c = spire_axis(tx, ty, 3.0, NH, (1.1, 0.0), 2.2, t)
        rf = 1.55 * _prof_r(SLIM_PROF, t)
        P.append(part(M, "mast_node", collar(c, rf * 1.12, 8, h=0.6, rot=math.pi / 8), wn=False))
    spars = bmesh.new()
    for t, L in ((0.55, 3.4), (0.72, 2.4)):
        c = spire_axis(tx, ty, 3.0, NH, (1.1, 0.0), 2.2, t)
        for sd in (-1, 1):
            p0 = c + V(0, sd * 0.3, 0)
            p2 = c + V(0.2, sd * L, 1.2)
            bmk, _ = sweep(bezier(p0, c + V(0, sd * L * 0.6, 0.1), p2, 4), [0.2, 0.16, 0.1, 0.0], sides=4, tip=True)
            B.merge_bm(spars, set_mat(bmk, LIGHT))
    P.append(part(M, "spars", spars, wn=False, smooth=30))
    # dish on a pylon, front-left, looking up and outward
    dc = V(5.6, -11.4, 0.0)
    bm, grid, ts = spire(dc.x, dc.y, base_h - 0.2, 8.6, 1.35, [(0.0, 1.0), (0.3, 0.86), (0.6, 0.7), (0.85, 0.55)], m=4,
                         inner=0.7, gw=0.2, twist=0.0, rot=0.3)
    P.append(part(M, "dish_pylon", bm))
    joint = V(dc.x, dc.y, base_h + 7.2)
    P.append(part(M, "dish_joint", pod((joint.x, joint.y, joint.z - 1.2), 1.5, 2.8, sides=6), wn=False))
    axis = V(0.40, -0.40, 0.82)
    P.append(part(M, "dish", dish(joint + axis.normalized() * 1.1, axis, R=5.0, depth=1.4), smooth=40))
    # side pods with glowing slits
    for (px, py, r, hh) in ((-1.0, 11.4, 2.4, 3.6), (5.2, 10.6, 1.9, 2.9), (-6.4, -10.8, 2.1, 3.2)):
        pb = pod((px, py, base_h - 0.1), r, hh, sides=6, rot=rng.uniform(0, 1))
        bmesh.ops.recalc_face_normals(pb, faces=pb.faces)
        side = [f for f in pb.faces if abs(f.normal.z) < 0.6 and f.calc_center_median().z < base_h + hh * 0.4]
        slit(pb, side[::2], wf=0.16, hf=0.5, depth=0.08, mat=GLOW)
        P.append(part(M, "pod", pb, bevel_w=0.03, angle=40))
    ob = B.join(P, "AlienCityC")
    beacon_at_top(ob)
    return ob


# ------------------------------------------------------------------------------------------------
# ruins: destroyed alien city (materials Charred, AlienHull, Embers)
# ------------------------------------------------------------------------------------------------
CH, AH, EM = 0, 1, 2


def ruin_mats():
    return [
        B.mat("Charred", lin("#120e14"), 0.10, 0.90),
        B.mat("AlienHull", lin("#35244b"), 0.30, 0.34, coat=0.3),
        B.mat("Embers", lin("#2a0802"), 0.0, 0.85, emission=lin("#ff420d"), strength=1.5),
    ]


def jag_cut(bm, plane_co, plane_no, rng, jitter=(0.35, 0.9), core=0.42, rim_mat=CH, core_mat=EM):
    """Cut a closed mesh with a plane (keep the part below), close the hole with a charred rim and a small
    sunken glowing core, and roughen the broken edge."""
    n = Vector(plane_no).normalized()
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=Vector(plane_co), plane_no=n, clear_outer=True)
    edges = [e for e in bm.edges if e.is_boundary]
    if not edges:
        return
    res = bmesh.ops.edgeloop_fill(bm, edges=edges)
    caps = res.get("faces", [])
    rim_verts = set(v for f in caps for v in f.verts)
    for v in rim_verts:  # roughen the broken edge
        v.co += Vector((rng.uniform(-jitter[0], jitter[0]), rng.uniform(-jitter[0], jitter[0]),
                        rng.uniform(-jitter[1], jitter[1] * 0.4)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in caps:
        f.material_index = rim_mat
    slit(bm, caps, wf=core, hf=core, depth=0.7, mat=core_mat, up=V(0, 1, 0))
    poked = bmesh.ops.poke(bm, faces=[f for f in caps if f.is_valid])
    for f in poked["faces"]:
        f.material_index = core_mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def shell_fragment(x0, x1, th0, th1, ax=11.0, ay=8.0, az=9.0, z0=0.0, thick=0.4, nx=6, nt=6, rng=None):
    """Curved, ridged piece of a carapace (closed, with thickness) between x0..x1 and arch angles th0..th1."""
    def pt(x, th, grow):
        u = min(abs(x) / ax, 1.0)
        f = (1.0 - u ** 2.2) ** 0.55
        ridge = 1.0 + 0.045 * math.cos(x * 2.4) + 0.03 * math.cos(x * 7.0)
        return V(x, (ay * f * ridge + grow) * math.cos(th), z0 + (az * f * ridge + grow) * math.sin(th))
    bm = bmesh.new()
    outer, inner = [], []
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        ro, ri = [], []
        for j in range(nt + 1):
            th = th0 + (th1 - th0) * j / nt
            edge = rng and (i in (0, nx) or j in (0, nt))
            jit = rng.uniform(-0.6, 0.6) if edge else 0.0
            jth = rng.uniform(-0.07, 0.07) if edge else 0.0
            ro.append(bm.verts.new(pt(x + jit, th + jth, 0.0)))
            ri.append(bm.verts.new(pt(x + jit, th + jth, -thick)))
        outer.append(ro)
        inner.append(ri)
    for i in range(nx):
        for j in range(nt):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nx):  # border walls
        for j in (0, nt):
            a, b = (outer[i][j], outer[i + 1][j]), (inner[i][j], inner[i + 1][j])
            bm.faces.new((a[0], b[0], b[1], a[1]))
    for j in range(nt):
        for i in (0, nx):
            bm.faces.new((outer[i][j], inner[i][j], inner[i][j + 1], outer[i][j + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def city_ruins():
    B.reset()
    M = ruin_mats()
    rng = random.Random(91)
    P = []
    n = 7
    rot = math.pi / 2
    # glowing cracked ground under the shards (only visible through the gaps)
    floor = B.bm_prism([(13.0 * math.cos(rot + TAU * (k + 0.5) / n), 13.0 * math.sin(rot + TAU * (k + 0.5) / n))
                        for k in range(n)], 0.0, 0.2)
    P.append(part(M, "ember_floor", set_mat(floor, EM), wn=False))
    # shattered foundation: wedge shards with gaps, tilted
    for k in range(n):
        a0 = rot + TAU * k / n
        a1 = rot + TAU * (k + 1) / n
        gap = 0.16  # constant-width glowing crack between neighbouring shards
        poly = [(1.6 * math.cos((a0 + a1) / 2), 1.6 * math.sin((a0 + a1) / 2))]
        for t in range(4):
            r = 13.4 + rng.uniform(-1.2, 0.4)
            a = a0 + (a1 - a0) * t / 3
            if t == 0:
                a += gap / r
            elif t == 3:
                a -= gap / r
            poly.append((r * math.cos(a), r * math.sin(a)))
        bm = B.bm_prism(poly, 0.0, 1.0 - rng.uniform(0.0, 0.25))
        tilt = Matrix.Rotation(math.radians(rng.uniform(-4, 4)), 3, V(math.cos(a0), math.sin(a0), 0))
        transform(bm, tilt, loc=(0, 0, rng.uniform(-0.15, 0.1)))
        set_mat(bm, CH if k % 3 else AH)
        P.append(part(M, "shard%d" % k, bm, bevel_w=0.08, angle=30))
    # surviving (broken, charred) talons
    for k in (0, 2, 3, 5):
        a = rot + TAU * k / n
        tb = talon(M, a, 10.4, 19.9 - rng.uniform(0, 1.6), 1.9, 2.1, curl=0.28, name="talon%d" % k, bone_from=2.0)
        for poly in tb.data.polygons:
            poly.material_index = CH
        P.append(tb)
    # broken fluted spire stumps with glowing cores
    stumps = [(8.6, 0.55, 2.8, 9.5), (8.8, 1.75, 2.4, 5.5), (9.2, 3.15, 2.6, 7.2), (8.4, 4.6, 2.2, 3.6),
              (0.0, 0.0, 2.75, 6.4)]
    for k, (rr, a, r0, hcut) in enumerate(stumps):
        x, y = rr * math.cos(rot + a), rr * math.sin(rot + a)
        bm, grid, ts = spire(x, y, 0.6, hcut * 2.2, r0, HIVE_PROF, m=5, inner=0.7, gw=0.24, twist=0.4, rot=a,
                             glow_from=2.0)
        for f in bm.faces:
            f.material_index = AH if k % 2 == 0 else CH
        nrm = V(rng.uniform(-0.45, 0.45), rng.uniform(-0.45, 0.45), 1.0)
        jag_cut(bm, (x, y, 0.6 + hcut), nrm, rng)
        P.append(part(M, "stump%d" % k, bm))
    # toppled needle: two broken segments lying across the foundation
    for k, (t0, t1, cpos, yaw, pitch) in enumerate(((0.20, 0.50, V(4.2, -3.6, 2.6), -0.40, 0.09),
                                                    (0.50, 0.84, V(-3.6, -11.6, 1.6), -0.62, -0.05))):
        L = 26.0 * (t1 - t0)
        prof = [((t - t0) / (t1 - t0), _prof_r(NEEDLE_PROF, t)) for t in (t0, (t0 + t1) / 2, t1 - 0.001)]
        rings = [flute(0, 0, tt * L, 2.75 * rf, 2.75 * rf * 0.68, 5, 0.3 * k, 0.26) for (tt, rf) in prof]
        bm, grid, caps = loft(rings, cap0=True, cap1=True)
        for f in bm.faces:
            f.material_index = AH
        for f in caps:
            f.material_index = CH
            for v in f.verts:
                v.co.z += rng.uniform(-0.5, 0.5)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        slit(bm, [caps[1]] if k == 0 else [caps[0]], wf=0.4, hf=0.4, depth=0.6, mat=EM, up=V(0, 1, 0))
        rmat = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(math.pi / 2 + pitch, 3, "X")
        transform(bm, rmat, loc=cpos)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        P.append(part(M, "fallen%d" % k, bm))
    # cracked carapace: one ribbed fragment still standing (with charred ribs), two collapsed pieces
    frag = shell_fragment(-5.0, 4.0, 0.12, 1.45, z0=0.3, rng=rng, nx=8, nt=7)
    transform(frag, Matrix.Rotation(math.radians(-6), 3, "X"), loc=(-2.0, 4.8, 0.0))
    set_mat(frag, AH)
    P.append(part(M, "carapace0", frag, smooth=35))
    for k, xr in enumerate((-3.2, 0.2, 2.9)):
        u = abs(xr) / 11.0
        f = (1.0 - u ** 2.2) ** 0.55
        w, h = 8.0 * f + 0.35, 9.0 * f + 0.35
        th_end = (0.62, 0.48, 0.3)[k] * math.pi
        pts = [V(xr, w * math.cos(th), 0.3 + h * math.sin(th)) for th in
               [0.10 + (th_end - 0.10) * i / 7 for i in range(8)]]
        rb, _ = sweep(pts, [0.4] * 8, [0.34] * 8, profile=[(1, 0), (0.5, 1), (-0.5, 1), (-1, 0), (-0.5, -0.8),
                                                         (0.5, -0.8)], tip=False, up=V(1, 0, 0))
        transform(rb, Matrix.Rotation(math.radians(-6), 3, "X"), loc=(-2.0, 4.8, 0.0))
        P.append(part(M, "rib%d" % k, set_mat(rb, CH), smooth=40))
    for k, (x0, x1, t0, t1, loc, rz, rx) in enumerate(((-2.4, 2.6, 1.7, 2.7, V(9.0, 6.5, 0), 0.7, 0.55),
                                                       (-1.8, 2.2, 0.45, 1.35, V(-10.5, -2.5, 0), 2.3, -0.35))):
        fr = shell_fragment(x0, x1, t0, t1, z0=0.0, rng=rng, nx=5, nt=4)
        transform(fr, Matrix.Rotation(rz, 3, "Z") @ Matrix.Rotation(rx, 3, "X"))
        zmin = min(v.co.z for v in fr.verts)
        cen = sum((v.co for v in fr.verts), Vector()) / len(fr.verts)
        transform(fr, loc=(loc.x - cen.x, loc.y - cen.y, 0.7 - zmin))
        set_mat(fr, CH if k else AH)
        P.append(part(M, "carapace%d" % (k + 1), fr, smooth=35))
    # a fallen rib lying on the ground
    pts = [V(6.2 * math.cos(th), 0.0, 5.0 * math.sin(th)) for th in [0.15 + 0.85 * math.pi * i / 8 for i in range(9)]]
    rb, _ = sweep(pts, [0.42] * 9, [0.36] * 9, profile=[(1, 0), (0.5, 1), (-0.5, 1), (-1, 0), (-0.5, -0.8),
                                                        (0.5, -0.8)], tip=False, up=V(0, 1, 0))
    transform(rb, Matrix.Rotation(1.1, 3, "Z") @ Matrix.Rotation(math.radians(72), 3, "X"), loc=(-9.0, 8.5, 0.6))
    P.append(part(M, "rib_fallen", set_mat(rb, CH), smooth=40))
    # charred crystal shards jutting out of the ground
    cr = bmesh.new()
    for k in range(6):
        a = rot + TAU * (k + 0.3) / 6 + rng.uniform(-0.2, 0.2)
        rr = rng.uniform(10.5, 15.5)
        d = V(math.cos(a), math.sin(a), 0)
        ax = d * rng.uniform(0.6, 1.4) + V(rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 1.0)
        B.merge_bm(cr, crystal(d * rr + V(0, 0, -0.3), rng.uniform(0.55, 0.95), rng.uniform(3.0, 5.5), sides=6,
                               axis=ax, rot=rng.uniform(0, 3), mat=CH, top_frac=0.3))
    P.append(part(M, "crystal_shards", cr, wn=False, smooth=20))
    # rubble: angular chunks, denser near the centre
    rub = bmesh.new()
    for _ in range(36):
        a = rng.uniform(0, TAU)
        r = 2.5 + 15.0 * rng.random() ** 1.4
        s_ = rng.uniform(0.6, 1.8)
        b_ = cone(V(0, 0, 0), V(0, 0, s_ * rng.uniform(0.7, 1.3)), s_ * 0.75, sides=rng.choice((3, 4, 5)),
                  rot=rng.uniform(0, 3))
        rmat = Matrix.Rotation(rng.uniform(0, TAU), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.6, 0.6), 3, "X")
        transform(b_, rmat, loc=(r * math.cos(a), r * math.sin(a), 0.75 if r < 12.0 else 0.0))
        B.merge_bm(rub, b_)
    P.append(part(M, "rubble", set_mat(rub, CH), wn=False, smooth=20))
    # a few smouldering ember patches
    emb = bmesh.new()
    for _ in range(5):
        a = rng.uniform(0, TAU)
        r = rng.uniform(4.0, 16.0)
        cx, cy = r * math.cos(a), r * math.sin(a)
        poly = []
        for t in range(7):
            aa = TAU * t / 7
            rr = rng.uniform(0.5, 1.3)
            poly.append((cx + rr * math.cos(aa), cy + rr * math.sin(aa)))
        z = 1.0 if r < 12.0 else 0.0
        B.merge_bm(emb, B.bm_prism(poly, z - 0.1, z + 0.05))
    P.append(part(M, "embers", set_mat(emb, EM), wn=False))
    return B.join(P, "AlienCityRuins")


# ------------------------------------------------------------------------------------------------
def stats(ob):
    zs = [(ob.matrix_world @ v.co).z for v in ob.data.vertices]
    xs = [(ob.matrix_world @ v.co).x for v in ob.data.vertices]
    ys = [(ob.matrix_world @ v.co).y for v in ob.data.vertices]
    return dict(tris=B.tri_count(ob), x=(round(min(xs), 2), round(max(xs), 2)), y=(round(min(ys), 2), round(max(ys), 2)),
                z=(round(min(zs), 2), round(max(zs), 2)))


BUILDERS = {"a": (city_a, "alien_city_a"), "b": (city_b, "alien_city_b"), "c": (city_c, "alien_city_c"),
            "ruins": (city_ruins, "alien_city_ruins")}


def main(which, preview=False, views=("std",)):
    for key in which:
        fn, label = BUILDERS[key]
        ob = fn()
        print(label, stats(ob), flush=True)
        B.export_glb(os.path.join(B.MODEL_DIR, label + ".glb"))
        if preview:
            for v in views:
                if v == "std":
                    B.preview(os.path.join(B.PREVIEW_DIR, label + ".png"), target=(0, 0, 9), dist=74, elev=28, azim=30)
                elif v == "low":
                    B.preview(os.path.join(B.PREVIEW_DIR, label + "_low.png"), target=(0, 0, 8), dist=95, elev=9,
                              azim=-20, lens=60)
                elif v == "top":
                    B.preview(os.path.join(B.PREVIEW_DIR, label + "_top.png"), target=(0, 0, 0), dist=80, elev=80,
                              azim=0, lens=50)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    views = ("std",)
    for a in sys.argv[1:]:
        if a.startswith("--views="):
            views = tuple(a.split("=", 1)[1].split(","))
    main(args or list(BUILDERS), "--preview" in sys.argv, views)
