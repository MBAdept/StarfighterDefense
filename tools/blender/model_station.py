"""
model_station.py - friendly space station (repair & refuel) for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_station.py [--preview]
Output: assets/models/station.glb
Diameter ~70 m (ring), solar wings span ~78 m. Front / docking port toward +Y.
Objects: "Hub" (static: core cylinder, docking collar, solar wings, antennas)
         "Ring" (rotating habitat ring + spokes + collar; origin at station centre, spins about
                 Blender Y == Godot local Z)
Empties: Beacon_1..4 (blinking lights, on static parts), DockPort (front of the docking port).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from model_fighter import strip  # noqa: E402

RING_R = 30.0


def ring_windows(radius, y, width, height, segs, gap=0.35, outer=True):
    """Segmented strip of window panels just outside the ring's outer surface (or on its front face)."""
    bm = bmesh.new()
    for i in range(segs):
        a0 = 2 * math.pi * (i + gap / 2) / segs
        a1 = 2 * math.pi * (i + 1 - gap / 2) / segs
        if outer:
            pts0 = [(radius * math.cos(a0), y - width / 2, radius * math.sin(a0)),
                    (radius * math.cos(a1), y - width / 2, radius * math.sin(a1)),
                    (radius * math.cos(a1), y + width / 2, radius * math.sin(a1)),
                    (radius * math.cos(a0), y + width / 2, radius * math.sin(a0))]
            r2 = radius - height
            pts1 = [(r2 * math.cos(a0), y - width / 2, r2 * math.sin(a0)),
                    (r2 * math.cos(a1), y - width / 2, r2 * math.sin(a1)),
                    (r2 * math.cos(a1), y + width / 2, r2 * math.sin(a1)),
                    (r2 * math.cos(a0), y + width / 2, r2 * math.sin(a0))]
        else:  # on the front face (normal +Y), radial band between radius-width/2 and radius+width/2
            ri, ro = radius - width / 2, radius + width / 2
            pts0 = [(ri * math.cos(a0), y, ri * math.sin(a0)), (ro * math.cos(a0), y, ro * math.sin(a0)),
                    (ro * math.cos(a1), y, ro * math.sin(a1)), (ri * math.cos(a1), y, ri * math.sin(a1))]
            pts1 = [(p[0], y - height, p[2]) for p in pts0]
        b = B.bm_loft([pts1, pts0])
        B.merge_bm(bm, b)
    return bm


def build(preview=False):
    B.reset()
    st = B.mat("Structure", (0.78, 0.80, 0.83), 0.45, 0.36)
    sd = B.mat("StructureDark", (0.20, 0.21, 0.24), 0.5, 0.45)
    win = B.mat("Windows", (1.0, 0.86, 0.62), 0.0, 0.3, emission=(1.0, 0.84, 0.58), strength=3.5)
    glow = B.mat("Glow", (0.2, 0.9, 1.0), 0.0, 0.3, emission=(0.2, 0.9, 1.0), strength=6.0)
    pan = B.mat("Panels", (0.035, 0.075, 0.22), 0.85, 0.18)

    hub_parts = []
    ring_parts = []

    # ================= HUB (static) ==========================================================
    hub_secs = []
    prof = [(-17.0, 5.5), (-15.5, 7.0), (-6.0, 7.0), (-5.0, 7.6), (5.0, 7.6), (6.0, 7.0), (11.5, 7.0),
            (14.5, 5.2), (16.0, 4.4)]
    for y, r in prof:
        hub_secs.append([(r * math.cos(a), y, r * math.sin(a)) for a in [2 * math.pi * k / 20 for k in range(20)]])
    bmh = B.bm_loft(hub_secs)
    B.inset_panels(bmh, 3.0, 0.18, -0.08, frac=0.6, seed=51)
    hub_parts.append(B.part("hubcore", bmh, st, bevel_w=0.12, seg=1, angle=25))
    # dark bands
    for y in (-12.0, -8.0, 8.5):
        hub_parts.append(B.part("band", B.bm_cyl((0, y - 0.6, 0), (0, y + 0.6, 0), 7.25, 7.25, sides=20), sd, wn=False))
    # hub window rows
    for y in (-10.0, 10.0):
        hub_parts.append(B.part("hubwin", ring_windows(7.18, y, 0.7, 0.3, 20, gap=0.45), win, wn=False))
    # docking collar + port
    hub_parts.append(B.part("collar", B.bm_cyl((0, 15.8, 0), (0, 17.2, 0), 4.6, 4.0, sides=20), sd,
                            bevel_w=0.08, seg=1, angle=35))
    hub_parts.append(B.part("port", B.bm_cyl((0, 17.1, 0), (0, 17.5, 0), 2.6, 2.6, sides=20), glow, wn=False))
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        hub_parts.append(B.part("portlight", B.bm_box((3.55 * math.cos(a), 17.3, 3.55 * math.sin(a)),
                                                      (0.5, 0.35, 0.5)), glow, wn=False))
    # guide arms in front of the port
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        p0 = (4.2 * math.cos(a), 16.5, 4.2 * math.sin(a))
        p1 = (5.4 * math.cos(a), 21.0, 5.4 * math.sin(a))
        hub_parts.append(B.part("guide", B.bm_cyl(p0, p1, 0.32, 0.25, sides=8), st, wn=False))
        hub_parts.append(B.part("guidelight", B.bm_box(p1, (0.5, 0.5, 0.5)), glow, wn=False))

    # rear module + antenna dish
    hub_parts.append(B.part("rear", B.bm_cyl((0, -17.0, 0), (0, -23.0, 0), 4.6, 3.6, sides=16), sd,
                            bevel_w=0.08, seg=1, angle=35))
    hub_parts.append(B.part("mast", B.bm_cyl((0, -23.0, 0), (0, -28.0, 0), 0.5, 0.4, sides=8), st, wn=False))
    dish = B.bm_uvsphere((0, 0, 0), 4.0, segs=20, rings=10, hemi=True, scale=(1, 1, 0.35))
    bmesh.ops.rotate(dish, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=dish.verts)
    bmesh.ops.translate(dish, vec=Vector((0, -28.5, 0)), verts=dish.verts)
    hub_parts.append(B.part("dish", dish, st, wn=False, smooth=60))
    # vertical antennas
    for z in (1, -1):
        hub_parts.append(B.part("ant", B.bm_cyl((0, -19.0, z * 4.4), (0, -19.0, z * 9.5), 0.25, 0.12, sides=6), sd, wn=False))

    # solar wings (truss along +-X behind the ring)
    yb = -20.0
    for sgn in (1, -1):
        hub_parts.append(B.part("truss", B.bm_box((sgn * 22.0, yb, 0), (30.0, 1.1, 1.1)), sd, bevel_w=0.05, seg=1))
        for k in range(3):
            cx = sgn * (13.0 + k * 9.0)
            for zz in (1, -1):
                pb = B.bm_box((cx, yb, zz * 4.6), (8.2, 0.22, 7.6))
                B.inset_panels(pb, 1.0, 0.25, -0.05, normal_filter=lambda n: abs(n.y) > 0.9, seed=k)
                hub_parts.append(B.part("panel", pb, pan, wn=False))
                hub_parts.append(B.part("pframe", B.bm_box((cx, yb, zz * 0.95), (8.4, 0.5, 0.4)), sd, wn=False))
        hub_parts.append(B.part("tipblock", B.bm_box((sgn * 37.6, yb, 0), (1.6, 1.6, 1.6)), sd, bevel_w=0.08, seg=1))

    hub = B.join(hub_parts, "Hub")

    # ================= RING (rotating) =======================================================
    bmr = B.bm_torus_rect(RING_R, 7.0, 4.5, segs=48)
    B.inset_panels(bmr, 6.0, 0.2, -0.08, frac=0.7, seed=52)
    ring_parts.append(B.part("ringhull", bmr, st, bevel_w=0.12, seg=1, angle=25))
    # darker rails on both sides
    for y in (-3.7, 3.7):
        ring_parts.append(B.part("rail", B.bm_torus_rect(RING_R, 0.5, 5.0, segs=48), sd, wn=False))
        ring_parts[-1].location = (0, 0, 0)
        for v in ring_parts[-1].data.vertices:
            v.co.y += y
    # windows: outer band and front face band
    ring_parts.append(B.part("ringwin_out", ring_windows(RING_R + 2.32, 0.0, 2.2, 0.25, 48, gap=0.3), win, wn=False))
    ring_parts.append(B.part("ringwin_front", ring_windows(RING_R, 4.07, 1.0, 0.15, 48, gap=0.5, outer=False), win, wn=False))
    ring_parts.append(B.part("ringwin_back", ring_windows(RING_R, -3.92, 1.0, 0.15, 48, gap=0.5, outer=False), win, wn=False))
    # habitat pods on the ring (every 30 deg)
    for k in range(12):
        a = 2 * math.pi * k / 12
        c = Vector((math.cos(a), 0, math.sin(a)))
        pod = B.bm_box((0, 0, 0), (5.0, 8.2, 2.0))
        rot = Vector((0, 0, 1)).rotation_difference(c).to_matrix()
        bmesh.ops.rotate(pod, cent=Vector((0, 0, 0)), matrix=rot, verts=pod.verts)
        bmesh.ops.translate(pod, vec=c * (RING_R + 2.6), verts=pod.verts)
        ring_parts.append(B.part("pod%d" % k, pod, sd, bevel_w=0.1, seg=1, angle=30))
        lamp = B.bm_box((0, 0, 0), (1.2, 1.2, 0.5))
        bmesh.ops.rotate(lamp, cent=Vector((0, 0, 0)), matrix=rot, verts=lamp.verts)
        bmesh.ops.translate(lamp, vec=c * (RING_R + 3.75), verts=lamp.verts)
        ring_parts.append(B.part("podlamp%d" % k, lamp, glow if k % 2 == 0 else win, wn=False))
    # spokes and inner collar
    ring_parts.append(B.part("innercollar", B.bm_torus_rect(8.6, 3.0, 2.0, segs=24), sd, bevel_w=0.06, seg=1))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        c = Vector((math.cos(a), 0, math.sin(a)))
        ring_parts.append(B.part("spoke%d" % k, B.bm_cyl(c * 9.4, c * (RING_R - 2.1), 1.1, 1.1, sides=8), st,
                                 bevel_w=0.05, seg=1, angle=35))
        ring_parts.append(B.part("spokelight%d" % k, B.bm_cyl(c * 14.0, c * 14.6, 1.25, 1.25, sides=8), glow, wn=False))
    ring = B.join(ring_parts, "Ring")

    B.empty("Beacon_1", (37.6, yb, 1.1))
    B.empty("Beacon_2", (-37.6, yb, 1.1))
    B.empty("Beacon_3", (0, -19.0, 9.7))
    B.empty("Beacon_4", (0, -19.0, -9.7))
    B.empty("DockPort", (0, 17.8, 0))
    print("station tris:", B.tri_count(hub) + B.tri_count(ring),
          "hub dims:", tuple(round(v, 1) for v in hub.dimensions), "ring dims:", tuple(round(v, 1) for v in ring.dimensions))
    B.export_glb(os.path.join(B.MODEL_DIR, "station.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "station_front.png"), dist=120, elev=18, azim=30)
        B.preview(os.path.join(B.PREVIEW_DIR, "station_headon.png"), dist=110, elev=4, azim=4)
        B.preview(os.path.join(B.PREVIEW_DIR, "station_side.png"), dist=120, elev=10, azim=95)


if __name__ == "__main__":
    build("--preview" in sys.argv)
