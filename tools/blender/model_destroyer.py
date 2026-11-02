"""
model_destroyer.py - enemy destroyer for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_destroyer.py [--preview]
Output: assets/models/destroyer.glb
Length ~24 m (nose +Y), width ~14 m. Heavy "hammerhead" gunship: armoured crossbar with a
glowing eye-line (material Accent, neutral white -> tinted blue/green/red in Godot), command
tower, four-engine block, twin main gun under the crossbar, bomb bay in the belly.
Tintable materials: Accent (emissive strips), AccentPaint (painted armour plates, non-emissive).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from model_fighter import strip  # noqa: E402


def build(preview=False):
    B.reset()
    hull = B.mat("Hull", (0.33, 0.34, 0.37), 0.6, 0.38)
    dark = B.mat("HullDark", (0.06, 0.06, 0.07), 0.5, 0.48)
    accent = B.mat("Accent", (0.85, 0.85, 0.88), 0.0, 0.35, emission=(1.0, 1.0, 1.0), strength=3.0)
    paint = B.mat("AccentPaint", (0.70, 0.70, 0.73), 0.25, 0.42)
    glow = B.mat("Glow", (1.0, 0.75, 0.5), 0.0, 0.3, emission=(1.0, 0.72, 0.45), strength=8.0)

    parts = []

    # ---------------- core hull ---------------------------------------------------------------
    core = [  # y, half width, top, bottom, waist
        (11.9, 1.10, 0.80, -0.95, 0.0),
        (10.6, 2.40, 1.55, -1.65, 0.0),
        (7.20, 3.00, 1.95, -1.95, 0.1),
        (3.20, 2.60, 2.15, -1.75, 0.1),
        (-2.0, 2.90, 2.35, -1.90, 0.15),
        (-6.0, 3.70, 2.55, -2.10, 0.2),
        (-10.0, 4.10, 2.45, -2.20, 0.2),
        (-11.8, 3.70, 2.15, -1.95, 0.1),
    ]
    secs = [B.sec_y(y, B.oct_pts(w, zt, zb, zm, ts=0.55, bs=0.6)) for (y, w, zt, zb, zm) in core]
    bm = B.bm_loft(secs)
    B.inset_panels(bm, 1.2, 0.09, -0.04, frac=0.85, seed=21)
    parts.append(B.part("core", bm, hull, bevel_w=0.07, seg=1, angle=28))

    # ---------------- hammerhead crossbar (right half, mirrored) ------------------------------
    def xsec(x, y_back, y_front, z_bot, z_top):
        d = y_front - y_back
        return [(x, y_front - d * 0.14, z_top * 0.85), (x, y_front, (z_top + z_bot) * 0.45),
                (x, y_front - d * 0.18, z_bot), (x, y_back + d * 0.05, z_bot * 0.85),
                (x, y_back, (z_top + z_bot) * 0.5), (x, y_back + d * 0.12, z_top)]
    xb = [xsec(0.4, 5.4, 11.1, -1.45, 1.85), xsec(3.2, 5.9, 10.9, -1.30, 1.65),
          xsec(5.8, 6.4, 10.4, -1.05, 1.30), xsec(7.05, 6.9, 9.9, -0.80, 0.95)]
    bmx = B.bm_loft(xb)
    B.inset_panels(bmx, 1.0, 0.08, -0.035, frac=0.7, seed=22)
    parts.append(B.part("crossbar", bmx, hull, bevel_w=0.06, seg=1, angle=28, mirror=True))
    # painted armour plates on top of the crossbar (tintable)
    plate = [(1.1, 6.6, 10.0, 1.62), (5.6, 7.1, 9.7, 1.30)]
    secs = []
    for x, y0, y1, z in plate:
        secs.append([(x, y0, z), (x, y0 + 0.25, z + 0.18), (x, y1 - 0.35, z + 0.18), (x, y1, z - 0.05)])
    parts.append(B.part("plate", B.bm_loft(secs), paint, bevel_w=0.04, seg=1, angle=30, mirror=True))
    # glowing eye-line along the crossbar front
    parts.append(B.part("eyeline", strip((0.9, 11.12, 0.25), (6.75, 10.12, 0.05), 0.42, 0.10, up=(0, 0.25, 1)),
                        accent, mirror=True, wn=False))
    # wingtip emitter pods
    pod_secs = []
    for y, w, zt, zb in ((10.6, 0.25, 0.6, -0.6), (9.6, 0.55, 2.2, -2.0), (7.4, 0.55, 2.0, -1.9), (6.4, 0.3, 0.9, -0.9)):
        pod_secs.append(B.sec_y(y, [(7.05 - w, zt * 0.8), (7.05, zt), (7.05 + w, zt * 0.7), (7.05 + w, zb * 0.7),
                                    (7.05, zb), (7.05 - w, zb * 0.8)]))
    parts.append(B.part("tippod", B.bm_loft(pod_secs), dark, bevel_w=0.04, seg=1, angle=30, mirror=True))
    parts.append(B.part("tipglow_t", B.bm_box((7.05, 8.4, 2.25), (0.5, 1.9, 0.22)), accent, mirror=True, wn=False))
    parts.append(B.part("tipglow_b", B.bm_box((7.05, 8.4, -2.05), (0.5, 1.9, 0.22)), accent, mirror=True, wn=False))

    # ---------------- side armour skirts (mirrored) -------------------------------------------
    sk = []
    for y, xo, zt, zb in ((4.0, 2.75, 1.4, -1.2), (-1.5, 3.15, 1.8, -1.5), (-6.2, 3.95, 1.9, -1.6)):
        sk.append([(xo, y, zt), (xo + 0.55, y, zt - 0.3), (xo + 0.55, y, zb + 0.3), (xo, y, zb)])
    bmsk = B.bm_loft(sk)
    B.inset_panels(bmsk, 0.8, 0.07, -0.03, seed=23)
    parts.append(B.part("skirt", bmsk, dark, bevel_w=0.04, seg=1, angle=30, mirror=True))
    parts.append(B.part("skirt_glow", strip((3.35, 3.2, 0.2), (4.55, -6.0, 0.2), 0.12, 0.10, up=(1, 0, 0)),
                        accent, mirror=True, wn=False))

    # ---------------- command tower -------------------------------------------------------------
    tw = [(1.6, 0.9, 2.25, 2.0), (0.8, 1.55, 3.5, 2.0), (-3.0, 1.75, 3.75, 2.2), (-5.6, 1.2, 3.1, 2.4)]
    secs = [B.sec_y(y, [(-w, zb), (-w, zt - 0.4), (-w * 0.55, zt), (w * 0.55, zt), (w, zt - 0.4), (w, zb)])
            for (y, w, zt, zb) in tw]
    parts.append(B.part("tower", B.bm_loft(secs), paint, bevel_w=0.05, seg=1, angle=28))
    # bridge window slit (glowing)
    parts.append(B.part("bridge", strip((-1.25, 0.9, 3.05), (1.25, 0.9, 3.05), 0.10, 0.16, up=(0, 0.6, 1)),
                        accent, wn=False))
    # antennas & sensor mast
    parts.append(B.part("mast", B.bm_cyl((0.0, -3.6, 3.7), (0.0, -3.6, 5.6), 0.10, 0.04, sides=6), dark, wn=False))
    parts.append(B.part("mast2", B.bm_cyl((0.9, -4.6, 3.3), (0.9, -4.6, 4.5), 0.07, 0.03, sides=6), dark, wn=False))
    parts.append(B.part("mast_light", B.bm_box((0.0, -3.6, 5.62), (0.16, 0.16, 0.16)), accent, wn=False))

    # ---------------- engine block ----------------------------------------------------------------
    eng = [(-1.85, 1.05), (1.85, 1.05), (-1.85, -1.05), (1.85, -1.05)]
    for i, (ex, ez) in enumerate(eng):
        parts.append(B.part("housing%d" % i, B.bm_box((ex, -10.6, ez), (1.95, 3.4, 1.85)), hull,
                            bevel_w=0.08, seg=1, angle=30))
        parts.append(B.part("nozzle%d" % i, B.bm_cyl((ex, -11.9, ez), (ex, -12.75, ez), 0.88, 0.80, sides=16),
                            dark, bevel_w=0.03, seg=1, angle=40))
        parts.append(B.part("eglow%d" % i, B.bm_cyl((ex, -12.76, ez), (ex, -12.78, ez), 0.66, 0.66, sides=16),
                            glow, wn=False))
    # engine block top greebles
    top_faces = [(Vector((x, y, 2.6)), Vector((0, 0, 1)), 1.0) for x in (-2.2, -1.0, 0.0, 1.0, 2.2)
                 for y in (-7.0, -8.2, -9.4)]
    gb = B.greebles(top_faces, 22, 0.25, 0.75, seed=31, height=(0.3, 0.9))
    parts.append(B.part("greebles", gb, dark, wn=False))

    # ---------------- main gun (twin barrels under the crossbar) -------------------------------
    parts.append(B.part("turret", B.bm_cyl((0, 8.4, -1.7), (0, 8.4, -2.65), 1.35, 1.15, sides=14), dark,
                        bevel_w=0.05, seg=1, angle=35))
    for bx in (-0.45, 0.45):
        parts.append(B.part("barrel", B.bm_cyl((bx, 8.4, -2.25), (bx, 13.1, -2.25), 0.22, 0.18, sides=10),
                            hull, bevel_w=0.02, seg=1, angle=40))
        parts.append(B.part("muzzle", B.bm_cyl((bx, 12.9, -2.25), (bx, 13.35, -2.25), 0.28, 0.28, sides=10),
                            dark, wn=False))

    # ---------------- bomb bay ----------------------------------------------------------------------
    parts.append(B.part("baydoor", B.bm_box((0, -1.0, -2.02), (2.9, 5.2, 0.35)), dark, bevel_w=0.05, seg=1))
    parts.append(B.part("baycore", B.bm_box((0, -1.0, -2.22), (1.6, 3.6, 0.12)), accent, wn=False))
    for y in (-2.9, -1.0, 0.9):
        parts.append(B.part("bayrib", B.bm_box((0, y, -2.27), (2.7, 0.22, 0.14)), hull, wn=False))

    ship = B.join(parts, "Destroyer")
    for i, (ex, ez) in enumerate(eng):
        B.empty("Engine_%d" % (i + 1), (ex, -12.85, ez))
    B.empty("Gun_Main", (0, 13.45, -2.25))
    B.empty("BombBay", (0, -1.0, -2.35))
    print("destroyer tris:", B.tri_count(ship), "dims:", tuple(round(v, 2) for v in ship.dimensions))
    B.export_glb(os.path.join(B.MODEL_DIR, "destroyer.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "destroyer_front.png"), dist=42, elev=18, azim=35)
        B.preview(os.path.join(B.PREVIEW_DIR, "destroyer_headon.png"), dist=42, elev=8, azim=10)
        B.preview(os.path.join(B.PREVIEW_DIR, "destroyer_rear.png"), dist=42, elev=30, azim=150)


if __name__ == "__main__":
    build("--preview" in sys.argv)
