"""
model_bomb.py - the PLAYER's bomb (friendly side) for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_bomb.py [--preview]
Output: assets/models/bomb.glb
Length 1.8 m, body diameter 0.45 m, nose points to Blender +Y (= Godot -Z forward), origin = bounding-box centre.
Design: grey metal body with an ogive nose and boat tail, two amber warning stripes behind the nose and one at the
tail, recessed panel seams, 4 swept tail fins (X layout) held by a ring-tail shroud whose inner face glows
cyan-white (visible from behind while the bomb falls away), glowing rear nozzle.
Materials: BombHull (grey metallic), BombStripe (amber), Glow (emission cyan-white, 4.0).
Empty "Tail" at the rear centre.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

HULL, STRIPE, GLOW = range(3)
SEG = 18
LENGTH = 1.80


def mats():
    return [
        B.mat("BombHull", (0.46, 0.48, 0.51), 0.75, 0.36),
        B.mat("BombStripe", (1.0, 0.42, 0.02), 0.10, 0.42),
        B.mat("Glow", (0.62, 0.95, 1.0), 0.0, 0.30, emission=(0.62, 0.95, 1.0), strength=4.0),
    ]


def ring(y, r, seg=SEG, rot=0.0):
    """Circle in the XZ plane at y (CCW seen from +Y)."""
    return [Vector((r * math.cos(rot + 2 * math.pi * k / seg), y, r * math.sin(rot + 2 * math.pi * k / seg)))
            for k in range(seg)]


def lathe(profile, tip_front=None, tip_back=None, cap_back=True):
    """profile: [(y, r, mat)] from nose to tail; band i (between i and i+1) gets mat of entry i."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in ring(y, r)] for (y, r, _) in profile]
    n = SEG
    for i, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        for k in range(n):
            f = bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
            f.material_index = profile[i][2]
    if tip_front is not None:
        tv = bm.verts.new(tip_front[0])
        for k in range(n):
            f = bm.faces.new((rings[0][(k + 1) % n], rings[0][k], tv))
            f.material_index = tip_front[1]
    if tip_back is not None:
        tv = bm.verts.new(tip_back[0])
        for k in range(n):
            f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % n], tv))
            f.material_index = tip_back[1]
    elif cap_back:
        bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build(preview=False):
    B.reset()
    M = mats()
    parts = []
    H, S, G = HULL, STRIPE, GLOW
    # ---- body: ogive nose -> cylinder -> boat tail -> nozzle -------------------------------------
    R = 0.225
    prof = [
        (0.875, 0.028, H), (0.86, 0.055, H), (0.83, 0.085, H), (0.78, 0.122, H), (0.71, 0.158, H),
        (0.62, 0.190, H), (0.52, 0.212, H), (0.42, 0.223, S),       # stripe 1
        (0.34, R, H), (0.30, R, S),                                   # stripe 2 (thin)
        (0.26, R, H),
        (0.06, R, H), (0.055, R - 0.008, H), (0.045, R - 0.008, H), (0.04, R, H),   # panel seam
        (-0.30, R, H), (-0.305, R - 0.008, H), (-0.315, R - 0.008, H), (-0.32, R, S),  # seam + tail stripe
        (-0.40, R, H),
        (-0.52, 0.208, H), (-0.64, 0.178, H), (-0.74, 0.150, H), (-0.79, 0.136, H),
        (-0.80, 0.105, H), (-0.82, 0.100, G),                         # glowing nozzle lip
        (-0.86, 0.085, G),
    ]
    body = lathe(prof, tip_front=(Vector((0, 0.90, 0)), H), tip_back=(Vector((0, -0.80, 0)), G))
    parts.append(B.part("body", body, M, smooth=40, wn=False))
    # ---- tail fins (X layout), swept, slightly thick ---------------------------------------------
    fins = bmesh.new()
    for k in range(4):
        a = math.radians(45 + 90 * k)
        d = Vector((math.cos(a), 0, math.sin(a)))
        t = Vector((-math.sin(a), 0, math.cos(a))) * 0.012
        r_root, r_tip = 0.17, 0.315
        # root chord along the boat tail, tip chord swept back
        pts = [(r_root + 0.04, -0.44), (r_tip, -0.62), (r_tip, -0.86), (r_root - 0.03, -0.82)]
        quad = [d * r + Vector((0, y, 0)) for (r, y) in pts]
        sec0 = [p - t for p in quad]
        sec1 = [p + t for p in quad]
        fb = bmesh.new()
        v0 = [fb.verts.new(p) for p in sec0]
        v1 = [fb.verts.new(p) for p in sec1]
        fb.faces.new(list(reversed(v0)))
        fb.faces.new(v1)
        for i in range(4):
            j = (i + 1) % 4
            fb.faces.new((v0[i], v0[j], v1[j], v1[i]))
        bmesh.ops.recalc_face_normals(fb, faces=fb.faces)
        B.merge_bm(fins, fb)
    parts.append(B.part("fins", fins, M, bevel_w=0.004, seg=1, angle=30, wn=False))
    # ---- ring-tail shroud: hull outside, glowing inside ------------------------------------------
    y0, y1 = -0.60, -0.86
    ro, ri = 0.345, 0.312
    sh = bmesh.new()
    outer0 = [sh.verts.new(p) for p in ring(y0, ro - 0.012)]
    outer1 = [sh.verts.new(p) for p in ring(y1, ro)]
    inner1 = [sh.verts.new(p) for p in ring(y1, ri)]
    inner0 = [sh.verts.new(p) for p in ring(y0, ri)]
    loops = [outer0, outer1, inner1, inner0]
    mats_l = [H, G, G, H]   # outer surface, rear lip, inner surface, front lip
    for li in range(4):
        a, b = loops[li], loops[(li + 1) % 4]
        for k in range(SEG):
            f = sh.faces.new((a[k], a[(k + 1) % SEG], b[(k + 1) % SEG], b[k]))
            f.material_index = mats_l[li]
    bmesh.ops.recalc_face_normals(sh, faces=sh.faces)
    parts.append(B.part("shroud", sh, M, smooth=40, wn=False))
    # ---- small details: lifting lug on top, fuze collar at the nose ------------------------------
    lug = B.bm_box((0, 0.10, R + 0.018), (0.05, 0.12, 0.04))
    lug2 = B.bm_box((0, -0.18, R + 0.018), (0.05, 0.12, 0.04))
    B.merge_bm(lug, lug2)
    parts.append(B.part("lugs", lug, M, bevel_w=0.006, seg=1, angle=30, wn=False))
    ob = B.join(parts, "Bomb")
    # ---- origin = bounding-box centre --------------------------------------------------------------
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    c = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
    k = LENGTH / (max(ys) - min(ys))   # normalise the overall length along the bomb axis
    for v in ob.data.vertices:
        v.co -= c
        v.co.y *= k
    ob.data.update()
    ymin = (min(ys) - c.y) * k
    B.empty("Tail", (0.0, ymin, 0.0), size=0.1)
    print("bomb tris:", B.tri_count(ob), "dims:", tuple(round(v, 3) for v in ob.dimensions),
          "centre shift:", tuple(round(v, 4) for v in c), "tail y:", round(ymin, 3))
    B.export_glb(os.path.join(B.MODEL_DIR, "bomb.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "bomb.png"), target=(0, 0, 0), dist=3.6, elev=22, azim=55)
        B.preview(os.path.join(B.PREVIEW_DIR, "bomb_rear.png"), target=(0, 0, 0), dist=3.0, elev=18, azim=200)


if __name__ == "__main__":
    build("--preview" in sys.argv)
