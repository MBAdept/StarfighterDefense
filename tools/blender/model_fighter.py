"""
model_fighter.py - enemy fighter ("Raider") for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_fighter.py [--preview]
Output: assets/models/fighter.glb
Length ~7.2 m (nose +Y), span ~6.2 m.
Design: central armoured pod with red-glowing canopy, two forward "mandible" gun prongs,
forward-swept wings with down-bent claw tips (menacing silhouette head-on), twin engines with
canted fins. Orange-red emissive accents on leading edges, prong tips and fin tips.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402


def strip(p0, p1, width, thick, up=(0, 0, 1)):
    """Thin box from p0 to p1 (centre line), `width` across, `thick` along `up`."""
    p0, p1, up = Vector(p0), Vector(p1), Vector(up).normalized()
    d = (p1 - p0)
    side = d.cross(up).normalized() * (width * 0.5)
    upv = up * (thick * 0.5)
    pts0 = [p0 - side - upv, p0 + side - upv, p0 + side + upv, p0 - side + upv]
    pts1 = [p1 - side - upv, p1 + side - upv, p1 + side + upv, p1 - side + upv]
    return B.bm_loft([pts0, pts1])


def diamond_secs(stations, rear_bias=0.58, bottom=0.55):
    """stations along an axis: (x, y_le, y_te, z, half_thickness) -> diamond sections."""
    secs = []
    for x, yle, yte, z, t in stations:
        ym = yle * (1 - rear_bias) + yte * rear_bias
        secs.append([(x, yle, z), (x, ym, z + t), (x, yte, z), (x, ym, z - t * bottom)])
    return secs


def build(preview=False):
    B.reset()
    hull = B.mat("Hull", (0.30, 0.31, 0.345), 0.55, 0.36)
    dark = B.mat("HullDark", (0.05, 0.05, 0.06), 0.5, 0.45)
    accent = B.mat("Accent", (0.95, 0.22, 0.05), 0.0, 0.4, emission=(1.0, 0.27, 0.05), strength=5.0)
    glow = B.mat("Glow", (1.0, 0.62, 0.25), 0.0, 0.3, emission=(1.0, 0.52, 0.14), strength=9.0)
    glass = B.mat("Glass", (0.05, 0.008, 0.008), 0.2, 0.05, emission=(0.85, 0.07, 0.03), strength=1.2)

    parts = []

    # ---------------- central pod -----------------------------------------------------------
    pod = [  # y, half width, top, bottom, waist
        (2.95, 0.05, 0.05, -0.03, 0.0),
        (2.45, 0.30, 0.22, -0.18, 0.0),
        (1.60, 0.52, 0.40, -0.30, 0.03),
        (0.40, 0.66, 0.50, -0.38, 0.05),
        (-1.00, 0.70, 0.46, -0.40, 0.05),
        (-2.30, 0.60, 0.36, -0.36, 0.03),
        (-3.05, 0.44, 0.26, -0.28, 0.00),
    ]
    secs = [B.sec_y(y, B.oct_pts(w, zt, zb, zm, ts=0.5, bs=0.62)) for (y, w, zt, zb, zm) in pod]
    bm = B.bm_loft(secs)
    B.inset_panels(bm, 0.12, 0.03, -0.012, frac=0.8, seed=5)
    parts.append(B.part("pod", bm, hull, bevel_w=0.03, seg=1, angle=28))

    # dark armour saddle on top of the pod, behind the canopy
    sad = [(0.30, 0.42, 0.53, 0.40), (-1.0, 0.50, 0.50, 0.36), (-2.4, 0.40, 0.40, 0.28)]
    secs = [B.sec_y(y, [(-w, zb), (-w * 0.55, zt), (w * 0.55, zt), (w, zb)]) for (y, w, zt, zb) in sad]
    parts.append(B.part("saddle", B.bm_loft(secs), dark, bevel_w=0.02, seg=1, angle=30))

    # ---------------- canopy ----------------------------------------------------------------
    can = [(2.35, 0.06, 0.25, 0.20), (1.95, 0.24, 0.44, 0.30), (1.30, 0.33, 0.60, 0.38),
           (0.70, 0.31, 0.60, 0.44), (0.35, 0.16, 0.53, 0.46)]
    secs = []
    for y, w, zt, zb in can:
        secs.append(B.sec_y(y, [(-w, zb), (-w * 0.72, zb + (zt - zb) * 0.78), (0.0, zt),
                                (w * 0.72, zb + (zt - zb) * 0.78), (w, zb)]))
    parts.append(B.part("canopy", B.bm_loft(secs), glass, bevel_w=0.012, seg=1, angle=25, smooth=50))
    parts.append(B.part("canopy_rib", strip((0, 2.08, 0.46), (0, 0.45, 0.61), 0.05, 0.035), dark, wn=False))
    parts.append(B.part("spine_glow", strip((0, 0.25, 0.545), (0, -2.35, 0.415), 0.06, 0.03), accent, wn=False))

    # ---------------- mandible prongs (right, mirrored) -------------------------------------
    # long forward prongs carrying the guns; give the head-on view its pincer silhouette
    pr = [  # y, centre x, centre z, half width, half height
        (-0.60, 0.70, -0.10, 0.22, 0.20),
        (0.80, 0.74, -0.12, 0.20, 0.18),
        (2.40, 0.68, -0.14, 0.14, 0.13),
        (3.55, 0.60, -0.15, 0.05, 0.05),
    ]
    secs = []
    for y, cx, cz, w, h in pr:
        secs.append([(cx, y, cz + h), (cx - w, y, cz + h * 0.1), (cx - w * 0.6, y, cz - h),
                     (cx + w * 0.6, y, cz - h), (cx + w, y, cz + h * 0.1)])
    parts.append(B.part("prong", B.bm_loft(secs), dark, bevel_w=0.015, seg=1, angle=30, mirror=True))
    parts.append(B.part("prong_glow", strip((0.70, 1.2, 0.045), (0.64, 2.75, -0.03), 0.07, 0.025),
                        accent, mirror=True, wn=False))
    # gun barrels sticking out of the prong tips
    gx, gz = 0.62, -0.16
    parts.append(B.part("gun", B.bm_cyl((gx, 2.9, gz), (gx, 3.85, gz), 0.055, 0.045, sides=8),
                        hull, mirror=True))
    parts.append(B.part("gun_tip", B.bm_cyl((gx, 3.80, gz), (gx, 3.92, gz), 0.07, 0.07, sides=8),
                        accent, mirror=True, wn=False))

    # ---------------- wings (right, mirrored) ------------------------------------------------
    wst = [  # x, y_le, y_te, z, half thickness
        (0.55, 0.55, -2.30, -0.02, 0.17),
        (1.95, 0.95, -0.95, -0.10, 0.11),
        (2.75, 1.45, 0.05, -0.30, 0.07),
        (3.10, 1.95, 0.85, -0.62, 0.045),
    ]
    parts.append(B.part("wing", B.bm_loft(diamond_secs(wst)), hull, bevel_w=0.02, seg=1, angle=30, mirror=True))
    # leading edge glow strips (just above the leading edge on the top surface)
    le = [(0.95, 0.62, 0.05), (1.95, 0.86, -0.02), (2.75, 1.36, -0.24), (3.04, 1.80, -0.52)]
    for a, b in zip(le[:-1], le[1:]):
        parts.append(B.part("le_glow", strip(a, b, 0.10, 0.03), accent, mirror=True, wn=False))
    # dark claw tip caps
    parts.append(B.part("claw", B.bm_loft(diamond_secs([(2.92, 1.70, 0.45, -0.46, 0.06),
                                                         (3.12, 2.02, 0.95, -0.66, 0.05),
                                                         (3.16, 2.30, 1.60, -0.95, 0.03)])),
                        dark, bevel_w=0.01, seg=1, angle=30, mirror=True))

    # ---------------- engine nacelles (right, mirrored) -------------------------------------
    nx, nz = 0.95, -0.04
    nac = [(-0.30, 0.16), (-0.75, 0.33), (-2.55, 0.39), (-3.25, 0.37), (-3.42, 0.34)]
    secs = []
    for y, r in nac:
        secs.append([(nx + r * math.cos(a), y, nz + r * math.sin(a)) for a in [2 * math.pi * k / 10 for k in range(10)]])
    bmn = B.bm_loft(secs)
    B.inset_panels(bmn, 0.10, 0.025, -0.01, frac=0.6, seed=11)
    parts.append(B.part("nacelle", bmn, hull, bevel_w=0.015, seg=1, angle=35, mirror=True))
    parts.append(B.part("nozzle", B.bm_cyl((nx, -3.36, nz), (nx, -3.62, nz), 0.36, 0.31, sides=16),
                        dark, bevel_w=0.012, seg=1, angle=40, mirror=True))
    parts.append(B.part("engine_glow", B.bm_cyl((nx, -3.622, nz), (nx, -3.64, nz), 0.255, 0.255, sides=16),
                        glow, mirror=True, wn=False))
    parts.append(B.part("intake", B.bm_cyl((nx, -0.20, nz), (nx, -0.55, nz), 0.15, 0.29, sides=10),
                        dark, mirror=True, wn=False))

    # ---------------- tail fins (right, mirrored, canted outward) ---------------------------
    fin_st = [(0.22, -1.40, -3.30, 0.06), (1.18, -2.55, -3.48, 0.03)]
    secs = []
    for z, yle, yte, t in fin_st:
        ym = yle * 0.45 + yte * 0.55
        secs.append([(0.0, yle, z), (t, ym, z), (0.0, yte, z), (-t, ym, z)])
    bmf = B.bm_loft(secs)
    cant = Matrix.Rotation(math.radians(-20), 3, "Y")
    bmesh.ops.rotate(bmf, cent=Vector((0, 0, 0.22)), matrix=cant, verts=bmf.verts)
    bmesh.ops.translate(bmf, vec=Vector((nx, 0, nz + 0.1)), verts=bmf.verts)
    parts.append(B.part("fin", bmf, hull, bevel_w=0.012, seg=1, angle=30, mirror=True))
    st = strip((0.0, -2.62, 1.16), (0.0, -3.42, 1.16), 0.05, 0.05, up=(1, 0, 0))
    bmesh.ops.rotate(st, cent=Vector((0, 0, 0.22)), matrix=cant, verts=st.verts)
    bmesh.ops.translate(st, vec=Vector((nx, 0, nz + 0.1)), verts=st.verts)
    parts.append(B.part("fin_glow", st, accent, mirror=True, wn=False))

    # ventral sensor eye + small vents
    parts.append(B.part("eye", B.bm_box((0, 2.1, -0.27), (0.26, 0.34, 0.05)), accent, wn=False))
    for y in (-0.6, -1.0, -1.4):
        parts.append(B.part("vent", B.bm_box((0.38, y, 0.43), (0.18, 0.12, 0.05)), dark, mirror=True, wn=False))

    ship = B.join(parts, "Fighter")
    B.empty("Engine_L", (-nx, -3.66, nz))
    B.empty("Engine_R", (nx, -3.66, nz))
    B.empty("Gun_L", (-gx, 3.95, gz))
    B.empty("Gun_R", (gx, 3.95, gz))
    print("fighter tris:", B.tri_count(ship), "dims:", tuple(round(v, 2) for v in ship.dimensions))
    B.export_glb(os.path.join(B.MODEL_DIR, "fighter.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "fighter_front.png"), dist=10, elev=18, azim=35)
        B.preview(os.path.join(B.PREVIEW_DIR, "fighter_headon.png"), dist=10, elev=8, azim=8)
        B.preview(os.path.join(B.PREVIEW_DIR, "fighter_rear.png"), dist=10, elev=28, azim=150)


if __name__ == "__main__":
    build("--preview" in sys.argv)
