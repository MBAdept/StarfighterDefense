"""
model_cities.py - planetary cities (3 variants) and a ruined city for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_cities.py [--preview]
Output: assets/models/city_a.glb, city_b.glb, city_c.glb, city_ruins.glb
Origin = ground centre (z=0 is the ground). Footprint diameter 36-44 m, max height ~26 m.
Each intact city has an empty "Beacon" at its highest point.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from model_fighter import strip  # noqa: E402


def mats():
    return dict(
        st=B.mat("Structure", (0.80, 0.82, 0.86), 0.3, 0.45),
        sd=B.mat("StructureDark", (0.26, 0.28, 0.32), 0.4, 0.5),
        dome=B.mat("Dome", (0.50, 0.78, 0.95), 0.1, 0.07, emission=(0.25, 0.55, 0.85), strength=0.7),
        win=B.mat("Windows", (1.0, 0.82, 0.55), 0.0, 0.3, emission=(1.0, 0.78, 0.48), strength=3.2),
        glow=B.mat("Glow", (0.3, 0.95, 1.0), 0.0, 0.3, emission=(0.3, 0.95, 1.0), strength=5.0),
    )


def ngon(r, n, z, rot=0.0):
    return [(r * math.cos(rot + 2 * math.pi * k / n), r * math.sin(rot + 2 * math.pi * k / n), z) for k in range(n)]


def platform(M, r, h=1.2, n=8):
    """Octagonal base slab with a glowing rim line."""
    secs = [ngon(r + 0.6, n, 0.0, math.pi / n), ngon(r, n, h, math.pi / n)]
    bm = B.bm_loft(secs)
    parts = [B.part("platform", bm, M["sd"], bevel_w=0.12, seg=1, angle=30)]
    # rim light: thin ring just inside the top edge
    rim = []
    for k in range(n):
        a0 = math.pi / n + 2 * math.pi * k / n
        a1 = math.pi / n + 2 * math.pi * (k + 1) / n
        p0 = Vector(((r - 0.5) * math.cos(a0), (r - 0.5) * math.sin(a0), h + 0.03))
        p1 = Vector(((r - 0.5) * math.cos(a1), (r - 0.5) * math.sin(a1), h + 0.03))
        rim.append(B.part("rim", strip(p0, p1, 0.3, 0.06), M["glow"], wn=False))
    return parts + rim


def tower(M, x, y, h, r, sides=12, band_every=2.4, cap=True, name="tower", taper=0.82, z0=0.0):
    parts = []
    secs = [ngon(r, sides, z0), ngon(r, sides, z0 + h * 0.75), ngon(r * taper, sides, z0 + h)]
    bm = B.bm_loft(secs)
    bmesh.ops.translate(bm, vec=Vector((x, y, 0)), verts=bm.verts)
    parts.append(B.part(name, bm, M["st"], bevel_w=0.06, seg=1, angle=25))
    # window bands
    z = z0 + 2.0
    while z < z0 + h * 0.72:
        band = B.bm_cyl((x, y, z), (x, y, z + 0.75), r + 0.04, r + 0.04, sides=sides)
        parts.append(B.part(name + "_win", band, M["win"], wn=False))
        z += band_every
    if cap:
        parts.append(B.part(name + "_cap", B.bm_cyl((x, y, z0 + h), (x, y, z0 + h + 0.8), r * taper + 0.6, r * taper * 0.6,
                                                    sides=sides), M["sd"], wn=False))
    return parts


def antenna(M, x, y, z0, h):
    return [B.part("antenna", B.bm_cyl((x, y, z0), (x, y, z0 + h), 0.18, 0.06, sides=6), M["sd"], wn=False),
            B.part("antenna_light", B.bm_box((x, y, z0 + h), (0.35, 0.35, 0.35)), M["glow"], wn=False)]


def dome(M, x, y, z, r, ribs=6, name="dome"):
    parts = []
    d = B.bm_uvsphere((0, 0, 0), r, segs=24, rings=12, hemi=True)
    bmesh.ops.translate(d, vec=Vector((x, y, z)), verts=d.verts)
    parts.append(B.part(name, d, M["dome"], wn=False, smooth=60))
    # ring wall under the dome
    parts.append(B.part(name + "_wall", B.bm_cyl((x, y, z - 1.2), (x, y, z + 0.25), r + 0.35, r + 0.25, sides=24),
                        M["sd"], wn=False))
    # meridian ribs
    for k in range(ribs):
        a = math.pi * k / ribs
        pts = []
        for i in range(9):
            t = math.pi * i / 8
            pts.append(Vector((x + (r + 0.05) * math.cos(t) * math.cos(a), y + (r + 0.05) * math.cos(t) * math.sin(a),
                               z + (r + 0.05) * math.sin(t))))
        for p0, p1 in zip(pts[:-1], pts[1:]):
            parts.append(B.part(name + "_rib", B.bm_cyl(p0, p1, 0.12, 0.12, sides=5, cap=False), M["st"], wn=False))
    return parts


def tube(M, p0, p1, r=0.8):
    return [B.part("tube", B.bm_cyl(p0, p1, r, r, sides=10), M["st"], wn=False)]


def pad(M, x, y, z, r=4.0):
    parts = [B.part("pad", B.bm_cyl((x, y, z), (x, y, z + 0.35), r, r, sides=16), M["sd"], wn=False)]
    for k in range(8):
        a = 2 * math.pi * k / 8
        parts.append(B.part("padlight", B.bm_box((x + (r - 0.4) * math.cos(a), y + (r - 0.4) * math.sin(a), z + 0.4),
                                                 (0.4, 0.4, 0.12)), M["glow"], wn=False))
    parts.append(B.part("padmark", B.bm_cyl((x, y, z + 0.36), (x, y, z + 0.40), r * 0.45, r * 0.45, sides=16),
                        M["win"], wn=False))
    return parts


# ------------------------------------------------------------------------------------------------
def city_a():
    B.reset()
    M = mats()
    P = platform(M, 19.0)
    P += dome(M, 0, 0, 1.2 + 1.2, 9.0, ribs=5, name="maindome")
    top = 0
    for k, (h, r) in enumerate(((24.0, 2.7), (19.0, 2.4), (15.0, 2.2))):
        a = math.radians(90 + 120 * k)
        x, y = 13.0 * math.cos(a), 13.0 * math.sin(a)
        P += tower(M, x, y, h, r, z0=1.2, name="tower%d" % k)
        P += tube(M, (x * 0.62, y * 0.62, 3.6), (x * 0.86, y * 0.86, 3.6))
        if k == 0:
            P += antenna(M, x, y, 1.2 + h + 0.8, 3.5)
            top = (x, y, 1.2 + h + 0.8 + 3.5)
    for k, a in enumerate((150.0, 270.0 + 60.0)):
        ar = math.radians(a)
        P += dome(M, 12.5 * math.cos(ar), 12.5 * math.sin(ar), 1.2 + 0.5, 3.2, ribs=3, name="smalldome%d" % k)
    ar = math.radians(30.0 - 60.0)
    P += pad(M, 13.5 * math.cos(ar), 13.5 * math.sin(ar), 1.2)
    ob = B.join(P, "CityA")
    B.empty("Beacon", top)
    return ob


def city_b():
    B.reset()
    M = mats()
    P = platform(M, 25.0, h=1.6, n=4)
    # central tower with ring
    P += tower(M, 0, 0, 24.0, 2.8, sides=8, z0=1.6, name="central", taper=0.7, band_every=2.0)
    P += antenna(M, 0, 0, 1.6 + 24.0 + 0.8, 0.0 + 2.2)
    ring = B.bm_torus_rect(5.6, 1.6, 2.2, segs=24)
    bmesh.ops.rotate(ring, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=ring.verts)
    bmesh.ops.translate(ring, vec=Vector((0, 0, 15.5)), verts=ring.verts)
    P.append(B.part("halo", ring, M["sd"], bevel_w=0.05, seg=1))
    P.append(B.part("halo_win", B.bm_cyl((0, 0, 15.2), (0, 0, 15.8), 6.73, 6.73, sides=24), M["win"], wn=False))
    for k in range(4):
        a = math.radians(45 + 90 * k)
        P.append(B.part("halo_strut", B.bm_cyl((2.4 * math.cos(a), 2.4 * math.sin(a), 15.5),
                                               (4.6 * math.cos(a), 4.6 * math.sin(a), 15.5), 0.3, 0.3, sides=6),
                        M["st"], wn=False))
    outer = [(12.5, 0.0, 19.0, 2.1), (0.0, 12.5, 14.0, 1.8), (-12.5, 0.0, 16.5, 2.0), (0.0, -12.5, 11.5, 1.7),
             (10.0, 10.0, 9.0, 1.5)]
    for k, (x, y, h, r) in enumerate(outer):
        P += tower(M, x, y, h, r, sides=8, z0=1.6, name="spire%d" % k, taper=0.75, band_every=2.2)
    # sky bridges
    for (x, y, h, r) in outer[:4]:
        z = min(h * 0.6, 10.0)
        P.append(B.part("bridge", strip((x * 0.25, y * 0.25, z), (x * 0.85, y * 0.85, z), 1.2, 0.8), M["st"], wn=False))
        P.append(B.part("bridge_win", strip((x * 0.3, y * 0.3, z + 0.05), (x * 0.8, y * 0.8, z + 0.05), 1.25, 0.3),
                        M["win"], wn=False))
    P += dome(M, -9.5, 9.5, 1.6 + 0.4, 3.6, ribs=3, name="d1")
    P += dome(M, 9.5, -9.5, 1.6 + 0.4, 3.0, ribs=3, name="d2")
    P += pad(M, -10.5, -10.5, 1.6, r=3.8)
    ob = B.join(P, "CityB")
    B.empty("Beacon", (0, 0, 1.6 + 24.0 + 0.8 + 2.2))
    return ob


def city_c():
    B.reset()
    M = mats()
    P = platform(M, 20.0)
    z = 1.2
    for k, (r, h) in enumerate(((15.0, 4.0), (10.5, 4.0), (6.2, 4.5))):
        secs = [ngon(r, 8, z, math.pi / 8), ngon(r * 0.94, 8, z + h, math.pi / 8)]
        bm = B.bm_loft(secs)
        B.inset_panels(bm, 3.0, 0.25, -0.1, normal_filter=lambda n: abs(n.z) < 0.5, seed=k)
        P.append(B.part("terrace%d" % k, bm, M["st"], bevel_w=0.1, seg=1, angle=30))
        # window strip around each terrace wall
        for j in range(8):
            a0 = math.pi / 8 + 2 * math.pi * j / 8 + 0.12
            a1 = math.pi / 8 + 2 * math.pi * (j + 1) / 8 - 0.12
            rr = r * 0.97 + 0.08
            p0 = Vector((rr * math.cos(a0), rr * math.sin(a0), z + h * 0.5))
            p1 = Vector((rr * math.cos(a1), rr * math.sin(a1), z + h * 0.5))
            P.append(B.part("twin", strip(p0, p1, 0.12, 0.9, up=(0, 0, 1)), M["win"], wn=False))
        z += h
    # spire
    P.append(B.part("spire", B.bm_cyl((0, 0, z), (0, 0, z + 11.5), 2.4, 0.25, sides=8), M["sd"], bevel_w=0.04, seg=1))
    P.append(B.part("spire_glow", B.bm_cyl((0, 0, z + 2.0), (0, 0, z + 2.6), 2.05, 1.95, sides=8), M["glow"], wn=False))
    P += dome(M, 11.0, 6.0, 1.2 + 4.0, 3.2, ribs=3, name="d1")
    P += dome(M, -11.5, -4.0, 1.2 + 4.0, 2.6, ribs=3, name="d2")
    P += pad(M, 0, -16.0, 1.2, r=3.6)
    P += pad(M, 15.5, -7.0, 1.2, r=2.6)
    ob = B.join(P, "CityC")
    B.empty("Beacon", (0, 0, z + 11.5))
    return ob


def city_ruins():
    B.reset()
    rnd = random.Random(77)
    ch = B.mat("Charred", (0.035, 0.032, 0.03), 0.1, 0.92)
    st = B.mat("Structure", (0.46, 0.46, 0.48), 0.25, 0.7)
    emb = B.mat("Embers", (0.4, 0.08, 0.02), 0.0, 0.8, emission=(1.0, 0.32, 0.06), strength=2.5)
    P = []
    # broken base slab: 5 tilted shards
    for k in range(5):
        a0 = 2 * math.pi * k / 5 + rnd.uniform(-0.1, 0.1)
        a1 = 2 * math.pi * (k + 1) / 5 + rnd.uniform(-0.1, 0.1)
        poly = [(0.8 * math.cos((a0 + a1) / 2), 0.8 * math.sin((a0 + a1) / 2))]
        for t in range(5):
            a = a0 + (a1 - a0) * t / 4
            r = 19.0 + rnd.uniform(-1.5, 0.5)
            poly.append((r * math.cos(a), r * math.sin(a)))
        bm = B.bm_prism(poly, 0.0, 1.0)
        tilt = Matrix.Rotation(math.radians(rnd.uniform(-3, 3)), 3, Vector((math.cos(a0), math.sin(a0), 0)))
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=tilt, verts=bm.verts)
        P.append(B.part("shard%d" % k, bm, ch, bevel_w=0.1, seg=1, angle=30))
    # broken tower stumps (cut with slanted plane)
    for k, (x, y, h, r) in enumerate(((10, 7, 9, 2.6), (-11, 6, 6, 2.3), (2, -12, 7.5, 2.4), (-5, -6, 3.5, 2.0))):
        bm = B.bm_cyl((x, y, 0.5), (x, y, h + 3), r, r * 0.9, sides=12)
        n = Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 1.0)).normalized()
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-4,
                                     plane_co=Vector((x, y, h)), plane_no=n, clear_outer=True)
        edges = [e for e in bm.edges if e.is_boundary]
        if edges:
            bmesh.ops.edgeloop_fill(bm, edges=edges)
        # jagged top: jitter the cut vertices
        for v in bm.verts:
            if v.co.z > h - 2.0:
                v.co += Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(-0.8, 0.4)))
        P.append(B.part("stump%d" % k, bm, st if k % 2 == 0 else ch, bevel_w=0.05, seg=1, angle=35))
        P.append(B.part("stump_emb%d" % k, B.bm_cyl((x, y, h - 1.2), (x, y, h - 0.9), r + 0.05, r + 0.03, sides=12),
                        emb, wn=False))
    # shattered dome: hemisphere with random faces removed, given thickness
    d = B.bm_uvsphere((0, 0, 0), 8.0, segs=20, rings=10, hemi=True)
    dele = [f for f in d.faces if f.calc_center_median().z > 2.0 and rnd.random() < 0.55]
    bmesh.ops.delete(d, geom=dele, context="FACES")
    bmesh.ops.translate(d, vec=Vector((0, 2.0, 0.6)), verts=d.verts)
    ob = B.obj_from_bm("dome", d, st)
    B.solidify(ob, 0.35)
    B.apply_mods(ob)
    B.smooth_by_angle(ob, 40)
    P.append(ob)
    # rubble
    rub = bmesh.new()
    for _ in range(60):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(2.0, 18.0)
        s = rnd.uniform(0.6, 2.4)
        b = B.bm_box((0, 0, 0), (s * rnd.uniform(0.6, 1.4), s * rnd.uniform(0.6, 1.4), s * rnd.uniform(0.3, 0.8)))
        rot = (Matrix.Rotation(rnd.uniform(0, 6.28), 3, "Z") @ Matrix.Rotation(rnd.uniform(-0.5, 0.5), 3, "X"))
        bmesh.ops.rotate(b, cent=Vector((0, 0, 0)), matrix=rot, verts=b.verts)
        bmesh.ops.translate(b, vec=Vector((r * math.cos(a), r * math.sin(a), 1.0 + s * 0.15)), verts=b.verts)
        B.merge_bm(rub, b)
    P.append(B.part("rubble", rub, ch, wn=False))
    # ember patches on the ground
    for _ in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(3.0, 15.0)
        cx, cy = r * math.cos(a), r * math.sin(a)
        poly = []
        for t in range(9):
            aa = 2 * math.pi * t / 9
            rr = rnd.uniform(0.8, 2.2)
            poly.append((cx + rr * math.cos(aa), cy + rr * math.sin(aa)))
        P.append(B.part("ember", B.bm_prism(poly, 1.0, 1.08), emb, wn=False))
    return B.join(P, "CityRuins")


def main(preview=False):
    for fn, name, label in ((city_a, "city_a.glb", "city_a"), (city_b, "city_b.glb", "city_b"),
                            (city_c, "city_c.glb", "city_c"), (city_ruins, "city_ruins.glb", "city_ruins")):
        ob = fn()
        print(label, "tris:", B.tri_count(ob), "dims:", tuple(round(v, 1) for v in ob.dimensions),
              "min z:", round(min((ob.matrix_world @ v.co).z for v in ob.data.vertices), 2))
        B.export_glb(os.path.join(B.MODEL_DIR, name))
        if preview:
            B.preview(os.path.join(B.PREVIEW_DIR, label + ".png"), target=(0, 0, 8), dist=70, elev=28, azim=30)


if __name__ == "__main__":
    main("--preview" in sys.argv)
