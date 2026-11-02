"""
model_props.py - rocks (planet surface props) and debris chunks (explosions) for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/model_props.py [--preview]
Output: assets/models/rocks.glb  (objects Rock_0..Rock_4, origin = ground centre, material "Rock")
        assets/models/debris.glb (objects Debris_0..Debris_3, origin = centre, materials Hull/Charred)
Objects are laid out side by side along X for the preview; use each node's mesh (vertices are
relative to its own origin).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402


def displace(bm, amp, freq, octaves=4, seed=0, ridge=False):
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    bm.normal_update()
    for v in bm.verts:
        p = v.co * freq + off
        n = noise.fractal(p, 0.8, 2.0, octaves)
        if ridge:
            n = 1.0 - abs(n) * 2.0
        v.co += v.normal * n * amp


def flatten_bottom(bm, z_cut=0.0):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=Vector((0, 0, z_cut)), plane_no=Vector((0, 0, -1)),
                           clear_outer=True)
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        bmesh.ops.edgeloop_fill(bm, edges=edges)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -z_cut)), verts=bm.verts)


def decimate(ob, ratio):
    m = ob.modifiers.new("Dec", "DECIMATE")
    m.ratio = ratio
    B.apply_mods(ob)


def rock_obj(name, bm, mat, x_offset, dec=0.5, smooth=32):
    ob = B.obj_from_bm(name, bm, mat)
    decimate(ob, dec)
    B.smooth_by_angle(ob, smooth)
    ob.location = (x_offset, 0, 0)
    return ob


def rocks(preview=False):
    B.reset()
    rk = B.mat("Rock", (0.36, 0.33, 0.30), 0.0, 0.85)
    objs = []
    # Rock_0: rounded cracked boulder (~3.2 x 2.6 x 2.2 m)
    bm = B.bm_sphere((0, 0, 0), 1.0, subdiv=4, scale=(1.6, 1.3, 1.25))
    displace(bm, 0.35, 0.9, 5, seed=1)
    displace(bm, 0.08, 4.0, 3, seed=2, ridge=True)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.75)), verts=bm.verts)
    flatten_bottom(bm, 0.0)
    objs.append(rock_obj("Rock_0", bm, rk, 0.0, 0.35))
    # Rock_1: flat slab (~5.5 x 4 x 1.3 m)
    bm = B.bm_sphere((0, 0, 0), 1.0, subdiv=4, scale=(2.8, 2.1, 0.75))
    displace(bm, 0.30, 0.6, 5, seed=3)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.45)), verts=bm.verts)
    flatten_bottom(bm, 0.0)
    objs.append(rock_obj("Rock_1", bm, rk, 8.0, 0.35))
    # Rock_2: tall jagged spire (~2.6 x 2.4 x 9 m)
    bm = B.bm_cyl((0, 0, -0.5), (0, 0, 9.0), 1.4, 0.15, sides=9)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1.0],
                              cuts=8, use_grid_fill=False)
    displace(bm, 0.45, 0.7, 4, seed=4)
    displace(bm, 0.12, 3.0, 3, seed=5, ridge=True)
    flatten_bottom(bm, 0.0)
    objs.append(rock_obj("Rock_2", bm, rk, 15.0, 0.6, smooth=25))
    # Rock_3: mesa / layered pillar (~4.5 x 4 x 6 m)
    bm = bmesh.new()
    z = -0.4
    for k, (r, h) in enumerate(((2.3, 1.6), (2.1, 1.4), (2.15, 1.5), (1.85, 1.4), (1.7, 0.6))):
        layer = B.bm_cyl((0, 0, z), (0, 0, z + h), r * (1.0 + 0.05 * (k % 2)), r * 0.97, sides=11)
        bmesh.ops.rotate(layer, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(0.4 * k, 3, "Z"), verts=layer.verts)
        B.merge_bm(bm, layer)
        z += h
    displace(bm, 0.22, 0.8, 4, seed=6)
    flatten_bottom(bm, 0.0)
    objs.append(rock_obj("Rock_3", bm, rk, 22.0, 0.7, smooth=28))
    # Rock_4: basalt column cluster (hexagonal prisms, ~3.5 m wide, up to 4.5 m)
    rnd = random.Random(9)
    bm = bmesh.new()
    cols = [(0, 0, 4.4), (0.95, 0.55, 3.6), (-0.95, 0.55, 3.0), (0, 1.1, 2.4), (0.95, -0.55, 2.8), (-0.95, -0.55, 3.9),
            (0, -1.1, 2.0), (1.9, 0, 1.5), (-1.9, 0, 1.2)]
    for (x, y, h) in cols:
        c = B.bm_cyl((x, y, -0.3), (x, y, h + rnd.uniform(-0.2, 0.2)), 0.52, 0.52, sides=6)
        top = [v for v in c.verts if v.co.z > h - 0.5]
        tilt = Vector((rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), 0))
        for v in top:
            v.co.z += tilt.x * (v.co.x - x) + tilt.y * (v.co.y - y)
        B.merge_bm(bm, c)
    flatten_bottom(bm, 0.0)
    objs.append(rock_obj("Rock_4", bm, rk, 29.0, 1.0, smooth=20))
    for o in objs:
        print(o.name, "tris", B.tri_count(o), "dims", tuple(round(v, 2) for v in o.dimensions))
    B.export_glb(os.path.join(B.MODEL_DIR, "rocks.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "rocks.png"), target=(14.5, 0, 2.0), dist=42, elev=22, azim=10)


def debris(preview=False):
    B.reset()
    hull = B.mat("Hull", (0.30, 0.31, 0.345), 0.55, 0.4)
    ch = B.mat("Charred", (0.035, 0.032, 0.03), 0.1, 0.92)
    rnd = random.Random(21)
    objs = []
    # Debris_0: bent armour plate with jagged outline
    poly = []
    for k in range(14):
        a = 2 * math.pi * k / 14
        r = rnd.uniform(0.7, 1.15)
        poly.append((r * math.cos(a) * 1.3, r * math.sin(a) * 0.8))
    bm = B.bm_prism(poly, -0.06, 0.06)
    for v in bm.verts:
        if v.co.x > 0.2:
            v.co.z += (v.co.x - 0.2) * 0.45
    for f in bm.faces:
        f.material_index = 0 if abs(f.normal.z) > 0.6 else 1
    ob = B.obj_from_bm("Debris_0", bm, [hull, ch])
    B.smooth_by_angle(ob, 30)
    objs.append(ob)
    # Debris_1: torn pipe section
    bm = B.bm_cyl((0, -0.9, 0), (0, 0.9, 0), 0.26, 0.26, sides=10)
    for v in bm.verts:
        if abs(v.co.y) > 0.85:
            v.co.y += rnd.uniform(-0.35, 0.1) * (1 if v.co.y > 0 else -1)
    for f in bm.faces:
        f.material_index = 1 if abs(f.normal.y) > 0.5 else 0
    ob = B.obj_from_bm("Debris_1", bm, [hull, ch])
    B.solidify(ob, 0.04)
    B.apply_mods(ob)
    B.smooth_by_angle(ob, 40)
    objs.append(ob)
    # Debris_2: twisted I-beam fragment (~2.6 m)
    bm = bmesh.new()
    for (sx, sz, cz) in ((0.5, 0.08, 0.26), (0.5, 0.08, -0.26), (0.08, 0.5, 0.0)):
        B.merge_bm(bm, B.bm_box((0, 0, cz), (sx, 2.6, sz)))
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) > 1.0], cuts=6)
    for v in bm.verts:
        ang = v.co.y * 0.25
        x, z = v.co.x, v.co.z
        v.co.x = x * math.cos(ang) - z * math.sin(ang)
        v.co.z = x * math.sin(ang) + z * math.cos(ang)
        if v.co.y > 1.2:
            v.co.y += rnd.uniform(-0.3, 0.0)
    ob = B.obj_from_bm("Debris_2", bm, [hull, ch])
    B.smooth_by_angle(ob, 30)
    objs.append(ob)
    # Debris_3: irregular chunk
    pts = [Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.5, 0.5), rnd.uniform(-0.4, 0.4))) for _ in range(18)]
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    for f in bm.faces:
        f.material_index = 0 if f.normal.z > 0.3 else 1
    ob = B.obj_from_bm("Debris_3", bm, [hull, ch])
    B.smooth_by_angle(ob, 25)
    objs.append(ob)
    for i, o in enumerate(objs):
        o.location = (i * 3.5, 0, 0)
        print(o.name, "tris", B.tri_count(o), "dims", tuple(round(v, 2) for v in o.dimensions))
    B.export_glb(os.path.join(B.MODEL_DIR, "debris.glb"))
    if preview:
        B.preview(os.path.join(B.PREVIEW_DIR, "debris.png"), target=(5.25, 0, 0), dist=13, elev=30, azim=15)


if __name__ == "__main__":
    pv = "--preview" in sys.argv
    rocks(pv)
    debris(pv)
