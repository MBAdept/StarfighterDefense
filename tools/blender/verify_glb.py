"""
verify_glb.py - re-import .glb files with bpy and print what a game integration needs to know.
Run:  /opt/tools/venv/bin/python tools/blender/verify_glb.py assets/models/alien_city_a.glb [...]
Per file: every node (name, type, location), mesh triangle counts, material names (+ emission strength),
bounding box in Blender axes (Z up) and in Godot axes (Y up, -Z forward), plus two automated checks:
  * inverted normals: signed volume of every closed (manifold) mesh island must be positive
  * z-fighting: exactly coincident faces (same centre, parallel plane) on different islands
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402


def islands(bm):
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        comp = []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(comp)
    return out


def check_mesh(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    # coincident faces (exact duplicates in the same plane -> z-fighting)
    buckets = {}
    dup = 0
    for f in bm.faces:
        if f.calc_area() < 1e-6:
            continue
        cen = f.calc_center_median()
        key = (round(cen.x, 3), round(cen.y, 3), round(cen.z, 3))
        for g_n in buckets.get(key, []):
            if abs(g_n.dot(f.normal)) > 0.999:
                dup += 1
        buckets.setdefault(key, []).append(f.normal.copy())
    # weld (the importer splits vertices at sharp/material seams), then judge every island
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    closed = inverted = open_ = 0
    for comp in islands(bm):
        edges = set(e for f in comp for e in f.edges)
        if not all(len(e.link_faces) == 2 for e in edges):
            open_ += 1
            continue
        closed += 1
        vol = 0.0
        for f in comp:
            a, b, c = (v.co for v in f.verts)
            vol += a.dot(b.cross(c)) / 6.0
        if vol <= 0:
            inverted += 1
    bm.free()
    return closed, inverted, open_, dup


def verify(path):
    B.reset()
    bpy.ops.import_scene.gltf(filepath=path)
    print("=" * 100)
    print(os.path.basename(path), "%.0f KB" % (os.path.getsize(path) / 1024))
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    total = 0
    for ob in sorted(bpy.context.scene.objects, key=lambda o: (o.type, o.name)):
        loc = tuple(round(v, 3) for v in ob.matrix_world.translation)
        if ob.type == "MESH":
            me = ob.data
            me.calc_loop_triangles()
            tris = len(me.loop_triangles)
            total += tris
            for v in me.vertices:
                w = ob.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
            mats = []
            for m in me.materials:
                es = ""
                if m and m.node_tree:
                    for n in m.node_tree.nodes:
                        if n.type == "BSDF_PRINCIPLED" and n.inputs["Emission Strength"].default_value > 0:
                            col = n.inputs["Emission Color"].default_value
                            if max(col[:3]) > 0:
                                es = " (emission %.1f)" % n.inputs["Emission Strength"].default_value
                mats.append((m.name if m else "None") + es)
            closed, inverted, open_, dup = check_mesh(ob)
            print("  MESH  %-18s tris %5d  loc %s" % (ob.name, tris, loc))
            print("        materials: %s" % ", ".join(mats))
            print("        islands closed %d (inverted %d), open %d, coincident faces %d" % (closed, inverted, open_, dup))
        else:
            print("  %-5s %-18s loc %s  (Godot: %s)" % (ob.type, ob.name, loc,
                                                      (round(loc[0], 3), round(loc[2], 3), round(-loc[1], 3))))
    size = hi - lo
    print("  total tris %d" % total)
    print("  bbox Blender min %s max %s size %s" % (tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
                                                    tuple(round(v, 3) for v in size)))
    print("  bbox centre %s ; footprint diameter (max of x/y extent) %.2f m ; height %.2f m" % (
        tuple(round(v, 3) for v in (lo + hi) / 2), max(size.x, size.y), hi.z))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        verify(p)
