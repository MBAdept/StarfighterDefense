"""
model_flagship.py - enemy flagship (dreadnought) for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_flagship.py [--preview]
Output: assets/models/flagship.glb
Length ~100 m (front toward +Y), width ~72 m. Broad "manta fortress" whose front faces the player.
A recessed square weak point (own object "WeakPoint", 7 x 7 m, emissive pink) sits in the centre
of the front face, framed by dark bars and flanked by two armoured "gate" blocks.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from model_fighter import strip  # noqa: E402

WP_Y = 46.45      # weak point centre (y)
WP_Z = 0.0        # weak point centre (z)
WP_HALF = 3.5     # 7 x 7 m


def build(preview=False):
    B.reset()
    hull = B.mat("Hull", (0.21, 0.20, 0.25), 0.6, 0.40)
    dark = B.mat("HullDark", (0.045, 0.04, 0.055), 0.5, 0.5)
    accent = B.mat("Accent", (0.55, 0.20, 1.0), 0.0, 0.35, emission=(0.62, 0.22, 1.0), strength=4.0)
    glow = B.mat("Glow", (0.85, 0.55, 1.0), 0.0, 0.3, emission=(0.80, 0.50, 1.0), strength=8.0)
    weak = B.mat("WeakPoint", (1.0, 0.31, 0.82), 0.0, 0.25, emission=(1.0, 0.31, 0.82), strength=3.0)

    parts = []

    # ---------------- central hull ------------------------------------------------------------
    core = [  # y, half width, top, bottom, waist
        (46.0, 10.0, 8.5, -8.5, 0.0),
        (40.0, 14.0, 11.0, -10.5, 0.0),
        (22.0, 15.5, 12.5, -11.0, 0.0),
        (-8.0, 13.5, 11.5, -10.0, 0.0),
        (-34.0, 16.5, 10.5, -10.0, 0.0),
        (-47.0, 15.5, 9.5, -9.5, 0.0),
        (-50.0, 13.0, 8.0, -8.0, 0.0),
    ]
    secs = [B.sec_y(y, B.oct_pts(w, zt, zb, zm, ts=0.55, bs=0.55)) for (y, w, zt, zb, zm) in core]
    bm = B.bm_loft(secs)
    B.inset_panels(bm, 25.0, 0.45, -0.18, frac=0.9, seed=41)
    parts.append(B.part("core", bm, hull, bevel_w=0.3, seg=1, angle=28))

    # ---------------- manta wings (right, mirrored) -----------------------------------------
    def wsec(x, y_back, y_front, z_bot, z_top):
        d = y_front - y_back
        return [(x, y_front, (z_top + z_bot) * 0.4), (x, y_front - d * 0.25, z_top),
                (x, y_back + d * 0.1, z_top * 0.7), (x, y_back, (z_top + z_bot) * 0.5),
                (x, y_back + d * 0.1, z_bot * 0.7), (x, y_front - d * 0.3, z_bot)]
    ws = [wsec(11.0, -24.0, 40.0, -4.5, 5.5), wsec(24.0, -10.0, 33.0, -3.2, 3.8),
          wsec(33.0, 6.0, 30.0, -2.0, 2.4), wsec(36.0, 14.0, 34.0, -1.2, 1.4)]
    bmw = B.bm_loft(ws)
    B.inset_panels(bmw, 20.0, 0.4, -0.15, frac=0.8, seed=42)
    parts.append(B.part("wing", bmw, hull, bevel_w=0.25, seg=1, angle=28, mirror=True))
    # leading-edge glow
    parts.append(B.part("wing_le", strip((12.0, 40.2, -0.35), (24.0, 33.2, 0.25), 0.7, 0.35, up=(0, 0.3, 1)),
                        accent, mirror=True, wn=False))
    parts.append(B.part("wing_le2", strip((24.0, 33.2, 0.25), (35.6, 33.4, 0.05), 0.6, 0.3, up=(0, 0.3, 1)),
                        accent, mirror=True, wn=False))
    # wingtip weapon pods ("horns")
    parts.append(B.part("horn", B.bm_cyl((35.5, 10.0, 0.0), (35.5, 40.0, 0.0), 2.4, 1.0, sides=8), dark,
                        bevel_w=0.15, seg=1, angle=35, mirror=True))
    parts.append(B.part("horn_glow", B.bm_cyl((35.5, 40.0, 0.0), (35.5, 40.6, 0.0), 0.9, 0.6, sides=8), accent,
                        mirror=True, wn=False))

    # ---------------- front gate blocks around the weak point ---------------------------------
    # two vertical armour blocks left/right of the weak point, protruding forward
    gate = []
    for y, x0, x1, zt, zb in ((40.0, 5.5, 13.0, 10.0, -9.5), (49.5, 5.2, 10.5, 8.0, -7.5), (51.0, 5.0, 8.0, 6.0, -5.5)):
        gate.append([(x0, y, zt), (x1, y, zt * 0.8), (x1, y, zb * 0.8), (x0, y, zb)])
    bmg = B.bm_loft(gate)
    B.inset_panels(bmg, 6.0, 0.35, -0.15, frac=1.0, seed=43)
    parts.append(B.part("gate", bmg, hull, bevel_w=0.2, seg=1, angle=28, mirror=True))
    # vertical glow slit on the gates
    parts.append(B.part("gate_glow", strip((5.6, 49.0, 6.0), (5.6, 49.0, -5.5), 0.5, 0.35, up=(0, 1, 0)),
                        accent, mirror=True, wn=False))
    # brow (top) and chin (bottom) plates between the gates
    parts.append(B.part("brow", B.bm_prism([(-5.6, 40.0), (5.6, 40.0), (5.6, 49.2), (-5.6, 49.2)], 5.3, 8.6), dark,
                        bevel_w=0.18, seg=1, angle=30))
    parts.append(B.part("chin", B.bm_prism([(-5.6, 40.0), (5.6, 40.0), (5.6, 48.6), (-5.6, 48.6)], -8.2, -5.3), dark,
                        bevel_w=0.18, seg=1, angle=30))
    # frame bars directly around the weak point (protrude ~1.6 m in front of it)
    fh, ft = WP_HALF, 1.1
    fy0, fy1 = WP_Y - 0.6, WP_Y + 1.6
    frame = [((0, WP_Z + fh + ft / 2), (2 * fh + 2 * ft, ft)), ((0, WP_Z - fh - ft / 2), (2 * fh + 2 * ft, ft)),
             ((fh + ft / 2, WP_Z), (ft, 2 * fh)), ((-fh - ft / 2, WP_Z), (ft, 2 * fh))]
    for (cx, cz), (sx, sz) in frame:
        parts.append(B.part("frame", B.bm_box((cx, (fy0 + fy1) / 2, cz), (sx, fy1 - fy0, sz)), dark,
                            bevel_w=0.12, seg=1, angle=30))
    # back plate behind the weak point (so the recess has a floor)
    parts.append(B.part("wp_back", B.bm_box((0, WP_Y - 0.9, WP_Z), (2 * fh + 0.4, 0.6, 2 * fh + 0.4)), dark, wn=False))

    # ---------------- dorsal command tower ----------------------------------------------------
    tw = [(-6.0, 3.0, 13.0, 9.0), (-10.0, 6.0, 19.5, 9.0), (-24.0, 7.0, 21.5, 9.5), (-32.0, 4.5, 17.0, 9.0)]
    secs = [B.sec_y(y, [(-w, zb), (-w, zt - 2.0), (-w * 0.6, zt), (w * 0.6, zt), (w, zt - 2.0), (w, zb)])
            for (y, w, zt, zb) in tw]
    bmt = B.bm_loft(secs)
    B.inset_panels(bmt, 6.0, 0.3, -0.12, frac=0.8, seed=44)
    parts.append(B.part("tower", bmt, hull, bevel_w=0.2, seg=1, angle=28))
    parts.append(B.part("tower_win", strip((-5.4, -9.6, 17.8), (5.4, -9.6, 17.8), 0.5, 0.8, up=(0, 0.5, 1)),
                        accent, wn=False))
    parts.append(B.part("tower_win2", strip((-4.0, -9.0, 15.0), (4.0, -9.0, 15.0), 0.35, 0.5, up=(0, 0.5, 1)),
                        accent, wn=False))
    for x, h in ((-2.5, 27.0), (2.0, 25.0), (0.0, 29.0)):
        parts.append(B.part("antenna", B.bm_cyl((x, -22.0, 21.0), (x, -22.0, h), 0.3, 0.1, sides=6), dark, wn=False))

    # ---------------- ventral keel ------------------------------------------------------------
    keel = [(20.0, 1.5, -9.5, -11.0), (0.0, 3.0, -9.0, -16.5), (-30.0, 3.0, -9.0, -15.5), (-42.0, 1.5, -9.0, -11.0)]
    secs = [B.sec_y(y, [(-w, zt), (-w, zb + 1.5), (0.0, zb), (w, zb + 1.5), (w, zt)]) for (y, w, zt, zb) in keel]
    parts.append(B.part("keel", B.bm_loft(secs), dark, bevel_w=0.2, seg=1, angle=28))
    parts.append(B.part("keel_glow", strip((0, 14.0, -12.2), (0, -34.0, -14.0), 0.5, 0.5, up=(1, 0, 0)), accent,
                        wn=False))

    # ---------------- turrets ------------------------------------------------------------------
    turrets = [(-7.0, 28.0, 11.6), (7.0, 28.0, 11.6), (0.0, 8.0, 12.2), (19.0, 18.0, 3.2), (-19.0, 18.0, 3.2),
               (27.0, 22.0, 2.4), (-27.0, 22.0, 2.4)]
    for i, (tx, ty, tz) in enumerate(turrets):
        parts.append(B.part("turret%d" % i, B.bm_cyl((tx, ty, tz - 0.4), (tx, ty, tz + 1.4), 2.1, 1.7, sides=12), dark,
                            bevel_w=0.1, seg=1, angle=35))
        for bx in (-0.6, 0.6):
            parts.append(B.part("barrel%d" % i, B.bm_cyl((tx + bx, ty + 0.5, tz + 0.7), (tx + bx, ty + 6.0, tz + 0.9),
                                                         0.32, 0.26, sides=8), hull, wn=False))

    # ---------------- engines --------------------------------------------------------------------
    eng = [(-9.0, 4.0), (0.0, 4.0), (9.0, 4.0), (-9.0, -4.0), (0.0, -4.0), (9.0, -4.0)]
    for i, (ex, ez) in enumerate(eng):
        parts.append(B.part("nozzle%d" % i, B.bm_cyl((ex, -49.0, ez), (ex, -53.0, ez), 3.5, 3.1, sides=18), dark,
                            bevel_w=0.12, seg=1, angle=40))
        parts.append(B.part("eglow%d" % i, B.bm_cyl((ex, -53.02, ez), (ex, -53.1, ez), 2.6, 2.6, sides=18), glow,
                            wn=False))

    # ---------------- greebles on the hull top and wings -----------------------------------------
    gf = []
    for x in range(-10, 11, 4):
        for y in range(-44, 36, 6):
            if -34 < y < -4 and abs(x) < 8:
                continue   # tower area
            gf.append((Vector((x, y, 11.3 if y > -30 else 10.3)), Vector((0, 0, 1)), 4.0))
    for x in (15, 19, 23, 27, 31):
        for y in range(0 if x > 25 else -14, 30, 6):
            for sgn in (-1, 1):
                gf.append((Vector((sgn * x, y, 4.6 - (x - 15) * 0.12)), Vector((0, 0, 1)), 3.0))
    gb = B.greebles(gf, 95, 0.8, 2.0, seed=45, height=(0.25, 0.7))
    parts.append(B.part("greebles", gb, dark, wn=False))
    # extra glow detail on the face: brow / chin eye-lines and gate outer slits
    parts.append(B.part("brow_glow", strip((-5.0, 49.25, 7.0), (5.0, 49.25, 7.0), 0.45, 0.4, up=(0, 1, 0)), accent, wn=False))
    parts.append(B.part("chin_glow", strip((-5.0, 48.65, -6.8), (5.0, 48.65, -6.8), 0.45, 0.4, up=(0, 1, 0)), accent, wn=False))
    for zz in (4.5, 1.5, -1.5, -4.5):
        parts.append(B.part("gate_slit", strip((7.2, 50.2, zz), (9.6, 49.6, zz * 0.95), 0.35, 0.3, up=(0, 1, 0)),
                            accent, mirror=True, wn=False))
    # side glow lines along the hull
    parts.append(B.part("side_glow", strip((15.3, 30.0, -1.0), (13.4, -30.0, -1.0), 0.6, 0.6, up=(1, 0, 0)), accent,
                        mirror=True, wn=False))

    ship = B.join(parts, "Flagship")

    # ---------------- weak point (separate object!) ----------------------------------------------
    wp = B.part("WeakPoint", B.bm_box((0, WP_Y, WP_Z), (2 * WP_HALF, 0.5, 2 * WP_HALF)), weak, bevel_w=0.08, seg=1)
    wp.name = "WeakPoint"
    wp.data.name = "WeakPoint"
    # put the WeakPoint origin at its own centre -> Godot node position == weak point centre
    centre = Vector((0.0, WP_Y, WP_Z))
    for v in wp.data.vertices:
        v.co -= centre
    wp.location = centre

    for i, (ex, ez) in enumerate(eng):
        B.empty("Engine_%d" % (i + 1), (ex, -53.3, ez))
    B.empty("Gun_Main", (0, WP_Y + 1.8, WP_Z))
    print("flagship tris:", B.tri_count(ship) + B.tri_count(wp), "dims:", tuple(round(v, 2) for v in ship.dimensions))
    print("weakpoint centre:", tuple(round(v, 3) for v in wp.location),
          "bbox centre approx (0, %.2f, %.2f)" % (WP_Y, WP_Z))
    B.export_glb(os.path.join(B.MODEL_DIR, "flagship.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "flagship_front.png"), target=(0, 0, 0), dist=150, elev=20, azim=35)
        B.preview(os.path.join(B.PREVIEW_DIR, "flagship_headon.png"), target=(0, 0, 0), dist=150, elev=6, azim=6)
        B.preview(os.path.join(B.PREVIEW_DIR, "flagship_rear.png"), target=(0, 0, 0), dist=150, elev=30, azim=150)


if __name__ == "__main__":
    build("--preview" in sys.argv)
