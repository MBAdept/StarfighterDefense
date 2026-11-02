"""
blib.py - small procedural hard-surface modelling toolkit on top of bpy/bmesh (Blender 5.2 as module).

Conventions used by all model scripts (see ASSET_SPEC.md):
  * metres, +Z up, ship nose points to +Y (glTF/Godot: -Z forward)
  * every part is built directly in object/world space with the object origin at (0,0,0)
  * parts are later joined into one mesh object; empties stay separate, unparented
"""
import math
import os
import random

import bpy  # must be imported before bmesh/mathutils when using bpy as a module
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODEL_DIR = os.path.join(ROOT, "assets", "models")
PREVIEW_DIR = os.path.join(ROOT, "tools", "blender", "previews")


# ------------------------------------------------------------------------------------------------
# scene / materials
# ------------------------------------------------------------------------------------------------
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import addon_utils
    addon_utils.enable("cycles", default_set=True, persistent=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.textures,
                 bpy.data.images, bpy.data.lights, bpy.data.cameras, bpy.data.worlds):
        for item in list(coll):
            coll.remove(item)


_MATS = {}


def mat(name, base=(0.5, 0.5, 0.5), metallic=0.0, roughness=0.5, emission=None, strength=0.0,
        alpha=1.0, coat=0.0, spec=0.5):
    """Create (or fetch) a Principled BSDF material with a given name."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            bsdf = n
    if bsdf is None:
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    if coat > 0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = (*base, 1.0)
    _MATS[name] = m
    return m


# ------------------------------------------------------------------------------------------------
# object helpers
# ------------------------------------------------------------------------------------------------
def obj_from_bm(name, bm, material=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        if isinstance(material, (list, tuple)):
            for m in material:
                me.materials.append(m)
        else:
            me.materials.append(material)
    return ob


def empty(name, loc, size=0.3):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = size
    e.location = Vector(loc)
    bpy.context.scene.collection.objects.link(e)
    return e


def apply_mods(ob):
    """Bake all modifiers into the mesh (robust in background mode)."""
    if not ob.modifiers:
        return ob
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = ob.name
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def bevel(ob, width, segments=2, angle=30.0, harden=False, clamp=True):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = clamp
    m.harden_normals = harden
    m.miter_outer = "MITER_ARC"
    return m


def weighted_normals(ob):
    m = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    m.keep_sharp = True
    m.mode = "FACE_AREA"
    m.weight = 50
    return m


def mirror_x(ob, merge=False):
    m = ob.modifiers.new("Mirror", "MIRROR")
    m.use_axis = (True, False, False)
    m.use_mirror_merge = merge
    m.use_clip = merge
    return m


def solidify(ob, thickness, offset=-1.0):
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    return m


def smooth_by_angle(ob, angle=35.0):
    me = ob.data
    try:
        me.set_sharp_from_angle(angle=math.radians(angle))
    except Exception:
        for p in me.polygons:
            p.use_smooth = True


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def finish(ob, bevel_w=None, seg=2, angle=30.0, smooth_angle=35.0, wn=True):
    """bevel + weighted normals, applied; smooth-by-angle shading."""
    if bevel_w:
        bevel(ob, bevel_w, seg, angle)
    if wn:
        weighted_normals(ob)
    smooth_by_angle(ob, smooth_angle)
    apply_mods(ob)
    smooth_by_angle(ob, smooth_angle)
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ------------------------------------------------------------------------------------------------
# geometry generators (return bmesh)
# ------------------------------------------------------------------------------------------------
def bm_loft(sections, cap_start=True, cap_end=True, closed=True):
    """Loft through 3D point loops. sections: list of lists of Vector/tuples (same length)."""
    bm = bmesh.new()
    rings = []
    for sec in sections:
        rings.append([bm.verts.new(Vector(p)) for p in sec])
    n = len(sections[0])
    rng = range(n) if closed else range(n - 1)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in rng:
            j = (i + 1) % n
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    if closed:
        if cap_start:
            bm.faces.new(list(reversed(rings[0])))
        if cap_end:
            bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def sec_y(y, pts):
    """Cross-section in the XZ plane at a given y. pts: [(x, z), ...] loop."""
    return [(x, y, z) for (x, z) in pts]


def oct_pts(w, zt, zb, zm=0.0, ts=0.55, bs=0.6):
    """Angular 8-point hull section: half width w, top zt, bottom zb, waist zm.
    ts/bs = top/bottom shoulder width factors. Counter-clockwise seen from +Y."""
    return [(0.0, zt), (-w * ts, zt * 0.9 + zm * 0.1), (-w, zm), (-w * bs, zb * 0.75 + zm * 0.25),
            (0.0, zb), (w * bs, zb * 0.75 + zm * 0.25), (w, zm), (w * ts, zt * 0.9 + zm * 0.1)]


def hex_pts(w, zt, zb, ts=0.6, bs=0.6):
    return [(-w * ts, zt), (-w, (zt + zb) * 0.5), (-w * bs, zb), (w * bs, zb), (w, (zt + zb) * 0.5), (w * ts, zt)]


def bm_box(center, size, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
    if rot is not None:
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def bm_cyl(p0, p1, r0, r1=None, sides=12, cap=True):
    """Cylinder/cone from point p0 to p1 with radii r0 (at p0) and r1 (at p1)."""
    if r1 is None:
        r1 = r0
    p0 = Vector(p0)
    p1 = Vector(p1)
    axis = (p1 - p0)
    L = axis.length
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=sides, radius1=r0, radius2=r1, depth=L)
    # cone is along Z centred at origin -> rotate to axis and move
    q = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=q.to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(p0 + p1) * 0.5, verts=bm.verts)
    return bm


def bm_sphere(center, radius, subdiv=3, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def bm_uvsphere(center, radius, segs=24, rings=12, hemi=False, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    if hemi:
        geom = [v for v in bm.verts if v.co.z < -1e-4]
        bmesh.ops.delete(bm, geom=geom, context="VERTS")
        # close the open bottom ring
        edges = [e for e in bm.edges if e.is_boundary]
        if edges:
            bmesh.ops.edgeloop_fill(bm, edges=edges)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def bm_prism(poly_xy, z0, z1):
    """Extrude a 2D polygon (XY, CCW) from z0 to z1."""
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in poly_xy]
    top = [bm.verts.new((x, y, z1)) for x, y in poly_xy]
    n = len(poly_xy)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_torus_rect(radius, width_y, thick_r, segs=32, axis="Y"):
    """Ring with rectangular cross-section around the Y axis (centre line radius `radius`)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        loop = []
        for (dr, dy) in ((-thick_r / 2, -width_y / 2), (thick_r / 2, -width_y / 2),
                         (thick_r / 2, width_y / 2), (-thick_r / 2, width_y / 2)):
            r = radius + dr
            loop.append(bm.verts.new((r * c, dy, r * s)))
        rings.append(loop)
    for i in range(segs):
        a = rings[i]
        b = rings[(i + 1) % segs]
        for k in range(4):
            kk = (k + 1) % 4
            bm.faces.new((a[k], a[kk], b[kk], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def merge_bm(dst, src):
    """Append bmesh src into dst (src freed)."""
    me = bpy.data.meshes.new("tmp_merge")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)
    return dst


def inset_panels(bm, min_area, thickness, depth, normal_filter=None, frac=1.0, seed=0, mat_index=None):
    """Inset individual large faces to create panel lines (recessed panels)."""
    rnd = random.Random(seed)
    faces = [f for f in bm.faces if f.calc_area() > min_area and
             (normal_filter is None or normal_filter(f.normal)) and rnd.random() < frac]
    if not faces:
        return []
    res = bmesh.ops.inset_individual(bm, faces=faces, thickness=thickness, depth=depth,
                                     use_even_offset=True, use_relative_offset=False)
    if mat_index is not None:
        for f in faces:
            f.material_index = mat_index
    return faces


def greebles(bm_target_obj_faces, count, size_min, size_max, seed=0, height=(0.3, 1.0), filt=None):
    """Return a bmesh with small boxes scattered on the given faces (list of (center, normal, area))."""
    rnd = random.Random(seed)
    faces = [f for f in bm_target_obj_faces if filt is None or filt(f)]
    if not faces:
        return bmesh.new()
    areas = [f[2] for f in faces]
    tot = sum(areas)
    out = bmesh.new()
    for _ in range(count):
        r = rnd.random() * tot
        acc = 0
        for f in faces:
            acc += f[2]
            if acc >= r:
                break
        c, n, a = f
        sx = rnd.uniform(size_min, size_max)
        sy = rnd.uniform(size_min, size_max)
        sz = rnd.uniform(*height) * min(sx, sy)
        jitter = Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0)) * math.sqrt(a) * 0.6
        q = Vector((0, 0, 1)).rotation_difference(n)
        rot = q.to_matrix()
        b = bm_box((0, 0, 0), (sx, sy, sz))
        bmesh.ops.translate(b, vec=Vector((0, 0, sz * 0.5)) + Vector((jitter.x, jitter.y, 0)), verts=b.verts)
        bmesh.ops.rotate(b, cent=Vector((0, 0, 0)), matrix=rot, verts=b.verts)
        bmesh.ops.translate(b, vec=c, verts=b.verts)
        merge_bm(out, b)
    return out


def face_samples(ob):
    """(center, normal, area) for every polygon of an object (world space == object space here)."""
    me = ob.data
    return [(p.center.copy(), p.normal.copy(), p.area) for p in me.polygons]


def part(name, bm, material, bevel_w=None, seg=2, angle=30.0, mirror=False, wn=True, smooth=35.0):
    ob = obj_from_bm(name, bm, material)
    if mirror:
        mirror_x(ob)
    if bevel_w:
        bevel(ob, bevel_w, seg, angle)
    if wn:
        weighted_normals(ob)
    smooth_by_angle(ob, smooth)
    apply_mods(ob)
    smooth_by_angle(ob, smooth)
    return ob


# ------------------------------------------------------------------------------------------------
# export / preview
# ------------------------------------------------------------------------------------------------
def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(filepath=path, export_format="GLB", use_selection=False, export_apply=True,
              export_yup=True, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("export_lights", None)
        bpy.ops.export_scene.gltf(**kw)
    print("exported", path, os.path.getsize(path) // 1024, "KB")


def preview(path, target=(0, 0, 0), dist=12.0, elev=22.0, azim=35.0, size=512, samples=48,
            lens=50.0, bg=(0.012, 0.014, 0.022), sun_strength=3.0, extra_lights=True, transparent=False):
    """Cycles CPU preview render from a 3/4 view. Lights/camera are removed afterwards."""
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    try:
        scn.cycles.device = "CPU"
    except Exception:
        pass
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    try:
        scn.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    scn.render.resolution_x = size
    scn.render.resolution_y = size
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = transparent
    try:
        scn.view_settings.view_transform = "AgX"
    except Exception:
        pass
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bgn = world.node_tree.nodes.get("Background")
    bgn.inputs[0].default_value = (*bg, 1.0)
    bgn.inputs[1].default_value = 1.0
    scn.world = world

    tgt = Vector(target)
    el = math.radians(elev)
    az = math.radians(azim)
    # camera position: azimuth measured from +Y (front) toward +X
    cam_pos = tgt + Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el))) * dist
    cam_data = bpy.data.cameras.new("PrevCam")
    cam_data.lens = lens
    cam_data.clip_end = dist * 10
    cam = bpy.data.objects.new("PrevCam", cam_data)
    scn.collection.objects.link(cam)
    cam.location = cam_pos
    direction = tgt - cam_pos
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    created = [cam]
    # key light (sun), rim light, fill
    def add_light(name, kind, energy, loc_dir, color=(1, 1, 1), size=1.0):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "SUN":
            ld.angle = math.radians(3)
        else:
            ld.shadow_soft_size = size
        lo = bpy.data.objects.new(name, ld)
        scn.collection.objects.link(lo)
        lo.location = tgt + Vector(loc_dir) * dist
        lo.rotation_euler = (tgt - lo.location).to_track_quat("-Z", "Y").to_euler()
        created.append(lo)

    add_light("Key", "SUN", sun_strength, (0.6, 0.3, 0.8), (1.0, 0.96, 0.9))
    if extra_lights:
        add_light("Rim", "SUN", sun_strength * 0.8, (-0.5, -0.9, 0.3), (0.55, 0.75, 1.0))
        add_light("Fill", "SUN", sun_strength * 0.15, (-0.8, 0.5, -0.4), (0.8, 0.85, 1.0))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in created:
        d = o.data
        bpy.data.objects.remove(o)
        if isinstance(d, bpy.types.Camera):
            bpy.data.cameras.remove(d)
        elif d is not None:
            bpy.data.lights.remove(d)
    print("preview", path)
