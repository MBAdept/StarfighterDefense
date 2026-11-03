"""
final_c.py - FINAL Steam WIDE capsule (1840x860, 2x of 920x430) from concept C "Angriff auf Vorrhal".
A copy of concept_c.py with the jury's improvements for the wide camera:
  * the attack reads at 230x108: laser target / explosion moved into the darker sky off the star's
    upper-left limb and closer (70 m); the 256 px flipbook explosion is replaced by concept A's hot
    1024 px ray-marched fireball (final_a.fireball_texture, shared cache) with flash card, shockwave ring,
    burning fragments, sparks and light (final_a.build_explosion), plus the debris.glb pieces
  * one continuous cyan beam per wing-tip cannon (0.05..0.97 of the way, core radius x1.3): the same
    converging "V" motif as the hero and the portrait
  * fighter 0 closer (80 m) as a crisp black silhouette on the star disc (no fill / bounce / fire light),
    fighters 1 and 2 with a stronger orange rim light and bigger plumes, the 420 m speck dropped
  * Vorrhal's disc 0.3 EV darker with stronger convection cells, granulation and limb darkening
  * player ship: smooth by angle + weighted normals (no triangle seams on the nose), key light 10 -> 8
    (no clipped nose), cyan plumes and wing stripes +20 %, subtler panel lines (they read as cracks)
  * the title zone (x < 0.52, y < 0.42) is kept empty: loose FX are culled there in screen space
Output: Blender writes a 16-bit TIFF (kept for compose_steam_assets.py), converted to an 8-bit PNG with
TPDF dither. No text is rendered.

Run (from the project root):
  /opt/tools/venv/bin/python tools/steam/final_c.py --final       # wide 1840x860 -> tools/steam/renders/
  /opt/tools/venv/bin/python tools/steam/final_c.py               # preview 920x430 -> tools/steam/previews/final_c/
Options: --only wide (default; hero/portrait framings of concept C still work), --samples N (final 256),
         --threads N (final: all cores), --scale F, --out DIR, --probe, --bgonly
Read-only use of assets/; caches in tools/steam/cache/ (concept_c_* maps, final_a_* fireballs).
"""
import argparse
import math
import os
import sys
import time

import numpy as np

sys.dont_write_bytecode = True      # do not leave .pyc files in the shared tools/ folders
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
sys.path.insert(0, os.path.join(ROOT, "tools", "textures"))
import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402
from noiselib import Fractal3, smoothstep  # noqa: E402
from gen_icon import player_ship  # noqa: E402
import final_a as FA  # noqa: E402  (hot fireball volume, explosion FX, shading helper - shared with the hero)

ASSETS = os.path.join(ROOT, "assets")
MODELS = os.path.join(ASSETS, "models")
TEX = os.path.join(ASSETS, "textures")
CACHE = os.path.join(HERE, "cache")
RENDERS = os.path.join(HERE, "renders")
F32 = np.float32


# ------------------------------------------------------------------------------------------------
# colours (sRGB hex -> scene linear)
# ------------------------------------------------------------------------------------------------
def srgb2lin(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


def hexlin(h):
    h = h.lstrip("#")
    return tuple(srgb2lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


CYAN = hexlin("#52E6FF")
AMBER = hexlin("#FFB838")
ALERT = hexlin("#FF4738")


# ------------------------------------------------------------------------------------------------
# layout (metres, +Z up; the cameras look roughly along +Y towards the star)
# ------------------------------------------------------------------------------------------------
STAR_AZEL = (0.0, 4.0)        # direction to Vorrhal (azimuth from +Y towards +X, elevation), degrees
STAR_R = 5.0                  # angular radius of the star disc (deg) - a red giant seen from close by
PLANET_R = 12000.0            # radius of Xhal (m)
PLANET_ALPHA = 36.0           # angular radius of Xhal seen from the scene (deg)
STAR_ABOVE = 0.22             # star centre above the limb, in star radii (0 = half disc visible)
PLANET_TILT = 0.0             # rotate the planet centre around the star direction (deg) -> horizon slope
PLANET_SPIN = (-60.0, 20.0, 75.0)   # texture orientation of Xhal (XYZ euler, deg)
ATMO_H = 0.016                # atmosphere shell thickness (fraction of the planet radius)

# Every framing is a camera on the same set (star, planet, ships, lights). The star is placed at the
# normalised screen position `star` (x right, y down), the player ship's origin at `ship`, seen from
# `dist` metres; lens in mm on a 36 mm sensor (larger image side); roll in degrees.
# The actors are blocked per shot in that camera's screen space (like a key-art layout):
#   target  - laser target (exploding fighter): screen position + distance from the camera (m)
#   roll_up - the ship's nose points at the target, its top surface faces the camera, rolled by roll_up
#   fighters- (screen x, y, distance m, bank deg, yaw deg): nose towards the player ship, turned by yaw
#   bolts   - red enemy bolts: (fighter index, start, end as fraction of the way to the ship, miss x/z m)
CAMERAS = {
    "hero": dict(preview=(1920, 620), final=(3840, 1240),
                 lens=40.0, star=(0.68, 0.46), ship=(0.425, 0.66), dist=46.0, roll=-4.0,
                 target=((0.582, 0.25), 100.0), roll_up=12.0,
                 fighters=[(0.757, 0.37, 112.0, -30.0, 12.0), (0.885, 0.26, 160.0, -40.0, 16.0),
                           (0.935, 0.50, 185.0, 30.0, -14.0), (0.83, 0.175, 420.0, -10.0, 8.0),
                           (0.972, 0.34, 520.0, 25.0, -6.0)],
                 bolts=[(1, 0.30, 0.40, (3.0, 2.0)), (1, 0.56, 0.65, (3.5, 1.5)),
                        (2, 0.36, 0.46, (-4.0, 3.0)), (0, 0.45, 0.53, (-2.5, 2.5))]),
    "wide": dict(preview=(920, 430), final=(1840, 860),
                 lens=42.0, star=(0.735, 0.42), ship=(0.59, 0.68), dist=32.0, roll=-4.0,
                 target=((0.59, 0.24), 70.0), roll_up=22.0,
                 fighters=[(0.80, 0.345, 80.0, -30.0, 12.0), (0.925, 0.235, 160.0, -40.0, 16.0),
                           (0.955, 0.53, 185.0, 30.0, -14.0)],
                 bolts=[(1, 0.30, 0.40, (3.0, 2.0)), (0, 0.45, 0.53, (3.0, 2.5))],
                 fire="volume",                 # concept A's fireball instead of the flipbook billboards
                 silhouette=[0],                # unlit black silhouette on the star disc
                 rim={1: 1.4, 2: 1.4},          # fighter index -> plume scale, + extra orange rim light
                 title_zone=(0.54, 0.44)),      # keep x < 0.54, y < 0.44 free of loose FX
    "portrait": dict(preview=(600, 900), final=(1200, 1800),
                     lens=44.0, star=(0.60, 0.30), ship=(0.42, 0.53), dist=34.0, roll=-6.0,
                     target=((0.39, 0.175), 95.0), roll_up=10.0,
                     fighters=[(0.66, 0.255, 150.0, -30.0, 12.0), (0.84, 0.20, 170.0, -40.0, 16.0),
                               (0.86, 0.37, 200.0, 30.0, -14.0)],
                     bolts=[(1, 0.32, 0.42, (3.0, 2.0)), (2, 0.36, 0.46, (-4.0, 3.0))]),
}
MAX_FIGHTERS = 5

SUN = dict(strength=8.0, color=(1.0, 0.30, 0.13))           # key light from Vorrhal (10 clipped the nose)
FIGHTER_RIM = dict(strength=9.0, color=(1.0, 0.36, 0.12))  # extra rim from the star on chosen fighters
FILL = dict(strength=3.2, color=(0.62, 0.80, 1.0))         # cool fill on the ships (artistic)
BOUNCE = dict(strength=0.35, color=(1.0, 0.25, 0.75))      # magenta city glow from below
PLANET_FILL = dict(strength=0.32, color=(0.55, 0.40, 1.0))  # reveals Xhal's night side faintly
CITY = dict(glow=1.0, micro=4.0, lines=0.12)               # emission strengths of Xhal's lights
STAR = dict(ev=-0.3, cells=0.45, gran=0.18, ld1=0.80, ld2=0.15)   # disc exposure, surface contrast, limb

LOOK = "AgX - Medium High Contrast"
EXPOSURE = 0.0


# ------------------------------------------------------------------------------------------------
# math helpers
# ------------------------------------------------------------------------------------------------
def dir_ae(az, el):
    a, e = math.radians(az), math.radians(el)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def az_el(v):
    v = v.normalized()
    return math.degrees(math.atan2(v.x, v.y)), math.degrees(math.asin(max(-1.0, min(1.0, v.z))))


def cam_tan(lens, w, h):
    t = 18.0 / lens
    return (t, t * h / w) if w >= h else (t * w / h, t)


def screen_dir_cam(sx, sy, tx, ty):
    return Vector(((2.0 * sx - 1.0) * tx, (1.0 - 2.0 * sy) * ty, -1.0)).normalized()


def cam_rot(yaw, pitch, roll):
    f = dir_ae(yaw, pitch)
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f)
    q = Quaternion(f, math.radians(roll))
    r, u = q @ r, q @ u
    return Matrix((r, u, -f)).transposed()


def solve_cam_rot(target_dir, sx, sy, tx, ty, roll):
    """Rotation that puts the world direction `target_dir` at screen position (sx, sy)."""
    d_c = screen_dir_cam(sx, sy, tx, ty)
    yaw, pitch = az_el(target_dir)
    ty_, tp_ = yaw, pitch
    for _ in range(80):
        R = cam_rot(yaw, pitch, roll)
        ca, ce = az_el(R @ d_c)
        da, de = ty_ - ca, tp_ - ce
        yaw += da
        pitch += de
        if abs(da) + abs(de) < 1e-7:
            break
    return cam_rot(yaw, pitch, roll)


def orient(fwd, bank, up=Vector((0, 0, 1))):
    """3x3 matrix: local +Y = fwd (nose), local +Z = up, banked by `bank` deg (positive = right wing down)."""
    f = fwd.normalized()
    r = f.cross(up).normalized()
    u = r.cross(f)
    q = Quaternion(f, math.radians(bank))
    r, u = q @ r, q @ u
    return Matrix((r, f, u)).transposed()


# ------------------------------------------------------------------------------------------------
# node helpers
# ------------------------------------------------------------------------------------------------
class NB:
    """Tiny shader-node builder: sockets or constants can be passed everywhere."""

    def __init__(self, nt):
        self.nt, self.N, self.L = nt, nt.nodes, nt.links

    def put(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.L.new(v, sock)
        elif v is not None:
            sock.default_value = v

    def node(self, typ, **kw):
        n = self.N.new(typ)
        for k, v in kw.items():
            setattr(n, k, v)
        return n

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.N.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if c is not None:
            self.put(n.inputs[2], c)
        return n.outputs[0]

    def vmath(self, op, a, b=None, scale=None):
        n = self.N.new("ShaderNodeVectorMath")
        n.operation = op
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if scale is not None:
            self.put(n.inputs[3], scale)
        return n

    def vec(self, op, a, b=None, scale=None):
        return self.vmath(op, a, b, scale).outputs[0]

    def val(self, op, a, b=None):
        return self.vmath(op, a, b).outputs[1]

    def maprange(self, v, a0, a1, b0=0.0, b1=1.0, smooth=True):
        n = self.N.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP" if smooth else "LINEAR"
        n.clamp = True
        self.put(n.inputs["Value"], v)
        n.inputs["From Min"].default_value = a0
        n.inputs["From Max"].default_value = a1
        n.inputs["To Min"].default_value = b0
        n.inputs["To Max"].default_value = b1
        return n.outputs[0]

    def mix(self, fac, a, b, blend="MIX"):
        n = self.N.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def sep(self, v):
        n = self.N.new("ShaderNodeSeparateXYZ")
        self.put(n.inputs[0], v)
        return n.outputs

    def comb(self, x, y, z):
        n = self.N.new("ShaderNodeCombineXYZ")
        self.put(n.inputs[0], x)
        self.put(n.inputs[1], y)
        self.put(n.inputs[2], z)
        return n.outputs[0]

    def emission(self, color, strength):
        n = self.N.new("ShaderNodeEmission")
        self.put(n.inputs[0], color)
        self.put(n.inputs[1], strength)
        return n.outputs[0]

    def add(self, a, b):
        n = self.N.new("ShaderNodeAddShader")
        self.L.new(a, n.inputs[0])
        self.L.new(b, n.inputs[1])
        return n.outputs[0]

    def mixsh(self, fac, a, b):
        n = self.N.new("ShaderNodeMixShader")
        self.put(n.inputs[0], fac)
        self.L.new(a, n.inputs[1])
        self.L.new(b, n.inputs[2])
        return n.outputs[0]

    def transparent(self):
        return self.N.new("ShaderNodeBsdfTransparent").outputs[0]

    def out(self, shader):
        o = self.N.new("ShaderNodeOutputMaterial")
        o.target = "CYCLES"
        self.L.new(shader, o.inputs[0])


def new_mat(name, emission_sampling="NONE"):
    m = bpy.data.materials.new(name)
    if not m.node_tree:
        m.use_nodes = True
    m.node_tree.nodes.clear()
    try:
        m.cycles.emission_sampling = emission_sampling
    except Exception:
        pass
    return m, NB(m.node_tree)


def link_obj(ob, coll=None):
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def obj_from_bm(name, bm, mat=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if mat is not None:
        me.materials.append(mat)
    return link_obj(bpy.data.objects.new(name, me))


def fx_only(ob):
    """Glow geometry: seen by the camera only (no shadows, no bounce light)."""
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    ob.visible_transmission = False
    ob.visible_volume_scatter = False
    return ob


def bm_tube(length, profile, sides=12):
    """Tube along local +Y from 0 to `length`; profile = [(t, radius), ...] with t in 0..1."""
    bm = bmesh.new()
    rings = []
    for t, r in profile:
        y = t * length
        if r <= 1e-6:
            rings.append([bm.verts.new((0.0, y, 0.0))])
            continue
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / sides), y, r * math.sin(2 * math.pi * i / sides)))
                      for i in range(sides)])
    for a, b in zip(rings[:-1], rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(sides):
                bm.faces.new((a[0], b[(i + 1) % sides], b[i]))
        elif len(b) == 1:
            for i in range(sides):
                bm.faces.new((a[i], a[(i + 1) % sides], b[0]))
        else:
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ------------------------------------------------------------------------------------------------
# derived planet maps (cached)
# ------------------------------------------------------------------------------------------------
def xhal_maps():
    """Split alien_home_emission.png into a soft glow layer and crisp 4x line art (conduits, nodes, rings)."""
    os.makedirs(CACHE, exist_ok=True)
    gp = os.path.join(CACHE, "concept_c_xhal_glow.png")
    lp = os.path.join(CACHE, "concept_c_xhal_lines.png")
    if os.path.exists(gp) and os.path.exists(lp):
        return gp, lp
    from PIL import Image
    from scipy import ndimage
    E = np.asarray(Image.open(os.path.join(TEX, "planets", "alien_home_emission.png")).convert("RGB")).astype(F32) / 255
    lum = E.max(axis=2)
    feat = (lum > 0.10).astype(F32)
    dens = ndimage.uniform_filter(feat, size=11, mode="wrap")
    hatch = smoothstep(0.14, 0.32, ndimage.maximum_filter(dens, size=5, mode="wrap"))
    hp = np.clip(lum - ndimage.gaussian_filter(lum, 3.0, mode="wrap"), 0, 1)
    bright = smoothstep(0.45, 0.85, lum)
    lines = np.clip(hp * 2.2 * (1 - hatch) + bright * 0.8, 0, 1)
    lab, n = ndimage.label(lines > 0.22, structure=np.ones((3, 3)))      # drop hatch fragments,
    size = ndimage.sum(np.ones_like(lines), lab, index=np.arange(1, n + 1))  # keep conduits / rings / nodes
    keep = np.concatenate([[False], size >= 14])
    lines = lines * ndimage.binary_dilation(keep[lab], iterations=1)
    up = np.asarray(Image.fromarray((lines * 255).astype(np.uint8)).resize((8192, 4096), Image.LANCZOS)).astype(F32)
    up = smoothstep(0.10, 0.42, up / 255.0)
    area = smoothstep(0.10, 0.30, ndimage.uniform_filter(feat, size=11, mode="wrap"))   # dense city areas only:
    glow = np.stack([ndimage.gaussian_filter(E[..., k] * area, 2.5, mode="wrap")         # isolated conduits and
                     for k in range(3)], -1)                                             # nodes would smear
    Image.fromarray((np.clip(glow, 0, 1) * 255 + 0.5).astype(np.uint8)).save(gp)
    Image.fromarray((up * 255 + 0.5).astype(np.uint8)).save(lp)
    return gp, lp


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
def mat_glow_tube(name, core_col, core_str, glow_col, glow_str, power=2.2, tail=0.0):
    """Additive glow for bolts / plumes. Generated Y (0 = tail end, 1 = head) fades the tail."""
    m, nb = new_mat(name)
    lw = nb.node("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    face = nb.math("SUBTRACT", 1.0, lw.outputs["Facing"], clamp=True)
    core = nb.math("POWER", face, power)
    tc = nb.node("ShaderNodeTexCoord")
    gy = nb.sep(tc.outputs["Generated"])[1]
    along = nb.maprange(gy, 0.0, 1.0, tail, 1.0, smooth=False)
    k = nb.math("MULTIPLY", core, along)
    hot = nb.math("POWER", k, 3.0)
    col = nb.mix(hot, glow_col + (1.0,), core_col + (1.0,))
    strength = nb.math("ADD", nb.math("MULTIPLY", k, glow_str), nb.math("MULTIPLY", hot, core_str))
    nb.out(nb.add(nb.transparent(), nb.emission(col, strength)))
    return m


def mat_planet(star_dir):
    m, nb = new_mat("Xhal")
    gp, lp = xhal_maps()
    base_img = bpy.data.images.load(os.path.join(TEX, "planets", "alien_home.png"), check_existing=True)
    glow_img = bpy.data.images.load(gp, check_existing=True)
    line_img = bpy.data.images.load(lp, check_existing=True)
    base_img.colorspace_settings.name = "sRGB"
    glow_img.colorspace_settings.name = "sRGB"
    line_img.colorspace_settings.name = "Non-Color"
    tc = nb.node("ShaderNodeTexCoord")
    n = nb.vec("NORMALIZE", tc.outputs["Object"])
    x, y, z = nb.sep(n)
    lon = nb.math("ARCTAN2", x, y)
    u = nb.math("MULTIPLY_ADD", lon, 1.0 / (2.0 * math.pi), 0.5)
    lat = nb.math("ARCSINE", z)
    v = nb.math("MULTIPLY_ADD", lat, 1.0 / math.pi, 0.5)
    uv = nb.comb(u, v, 0.0)
    tb = nb.node("ShaderNodeTexImage", image=base_img, interpolation="Cubic", extension="REPEAT")
    tg = nb.node("ShaderNodeTexImage", image=glow_img, interpolation="Cubic", extension="REPEAT")
    tl = nb.node("ShaderNodeTexImage", image=line_img, interpolation="Cubic", extension="REPEAT")
    for t in (tb, tg, tl):
        nb.put(t.inputs[0], uv)
    # night mask from the world-space normal vs. the star direction
    geo = nb.node("ShaderNodeNewGeometry")
    ndl = nb.val("DOT_PRODUCT", geo.outputs["Normal"], tuple(star_dir))
    night = nb.maprange(ndl, 0.06, -0.20, 0.0, 1.0)
    # density + hue of the city areas from the glow layer
    gcol = tg.outputs["Color"]
    gr, gg, gb = nb.sep(gcol)
    gmax = nb.math("MAXIMUM", nb.math("MAXIMUM", gr, gg), gb)
    dens = nb.math("MULTIPLY", gmax, 4.0, clamp=True)
    hue = nb.vec("DIVIDE", gcol, nb.comb(*(nb.math("MAXIMUM", gmax, 0.02),) * 3))
    # resolution independent micro detail inside the city areas: soft city clusters + sparse sparkles
    vc = nb.node("ShaderNodeTexVoronoi")
    vc.inputs["Scale"].default_value = 330.0
    nb.put(vc.inputs["Vector"], n)
    cr, cg, _ = nb.sep(vc.outputs["Color"])
    keep = nb.math("LESS_THAN", cr, nb.math("MULTIPLY", dens, 0.85))
    blob = nb.math("POWER", nb.maprange(vc.outputs["Distance"], 0.0, 0.42, 1.0, 0.0, smooth=False), 2.0)
    clusters = nb.math("MULTIPLY", nb.math("MULTIPLY", blob, keep), nb.math("MULTIPLY_ADD", cg, 0.8, 0.2))
    vs_ = nb.node("ShaderNodeTexVoronoi")
    vs_.inputs["Scale"].default_value = 1300.0
    nb.put(vs_.inputs["Vector"], n)
    sr, sg, _ = nb.sep(vs_.outputs["Color"])
    nz = nb.node("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 160.0
    nz.inputs["Detail"].default_value = 3.0
    nb.put(nz.inputs["Vector"], n)
    clump = nb.maprange(nz.outputs["Fac"], 0.45, 0.70, 0.0, 1.0)
    skeep = nb.math("LESS_THAN", sr, nb.math("MULTIPLY", dens, clump))
    spark = nb.math("MULTIPLY", nb.maprange(vs_.outputs["Distance"], 0.0, 0.16, 1.0, 0.0), skeep)
    spark = nb.math("MULTIPLY", spark, nb.math("MULTIPLY_ADD", sg, 0.9, 0.3))
    micro = nb.math("ADD", nb.math("MULTIPLY", clusters, 0.8), spark)
    lines = nb.sep(tl.outputs["Color"])[0]
    e_glow = nb.vec("SCALE", gcol, scale=CITY["glow"])
    e_micro = nb.vec("SCALE", hue, scale=nb.math("MULTIPLY", micro, CITY["micro"]))
    line_col = (1.0, 0.16, 0.62)               # conduits: magenta, never the red of enemy fire
    lw0 = nb.node("ShaderNodeLayerWeight")
    lw0.inputs["Blend"].default_value = 0.5
    at_limb = nb.maprange(lw0.outputs["Facing"], 0.55, 0.85, 1.0, 0.0)     # conduits foreshorten into
    lines = nb.math("MULTIPLY", lines, at_limb)                              # streaks at the very limb
    e_line = nb.vec("SCALE", line_col, scale=nb.math("MULTIPLY", lines, CITY["lines"]))
    emis = nb.vec("ADD", nb.vec("ADD", e_glow, e_micro), e_line)
    # lights fade towards the disc centre (near side, bottom of frame): keeps title / logo zones calm
    lw = nb.node("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    edge = nb.maprange(lw.outputs["Facing"], 0.35, 0.85, 0.03, 1.0)
    emis = nb.vec("SCALE", emis, scale=edge)
    bsdf = nb.node("ShaderNodeBsdfPrincipled")
    nb.put(bsdf.inputs["Base Color"], tb.outputs["Color"])
    bsdf.inputs["Roughness"].default_value = 0.72
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    nb.put(bsdf.inputs["Emission Color"], emis)
    nb.put(bsdf.inputs["Emission Strength"], night)
    nb.out(bsdf.outputs[0])
    return m


def mat_atmosphere(center, R, R_sh, star_dir):
    """Analytic rim glow: depends on the ray's closest approach to the planet centre (not on the mesh)."""
    m, nb = new_mat("XhalAtmo")
    geo = nb.node("ShaderNodeNewGeometry")
    rel = nb.vec("SUBTRACT", geo.outputs["Position"], tuple(center))
    I = geo.outputs["Incoming"]
    t = nb.val("DOT_PRODUCT", rel, I)
    perp = nb.vec("SUBTRACT", rel, nb.vec("SCALE", I, scale=t))
    b = nb.val("LENGTH", perp)
    h = nb.math("DIVIDE", nb.math("SUBTRACT", b, R), R_sh - R)          # 0 = limb, 1 = shell edge
    hpos = nb.math("MAXIMUM", h, 0.0)
    hneg = nb.math("MINIMUM", h, 0.0)
    outer = nb.math("MULTIPLY", nb.math("EXPONENT", nb.math("MULTIPLY", hpos, -4.5)),
                    nb.maprange(h, 1.0, 0.5, 0.0, 1.0))
    inner = nb.math("EXPONENT", nb.math("MULTIPLY", hneg, 7.0))
    prof = nb.math("MULTIPLY", outer, inner)
    mdir = nb.vec("NORMALIZE", perp)
    lit = nb.maprange(nb.val("DOT_PRODUCT", mdir, tuple(star_dir)), -0.5, 0.6, 0.0, 1.0)
    fw = nb.math("MAXIMUM", nb.math("MULTIPLY", nb.val("DOT_PRODUCT", I, tuple(star_dir)), -1.0), 0.0)
    phase = nb.math("ADD", nb.math("MULTIPLY", nb.math("POWER", fw, 250.0), 7.0),
                    nb.math("ADD", nb.math("MULTIPLY", nb.math("POWER", fw, 28.0), 2.2),
                            nb.math("MULTIPLY", nb.math("POWER", fw, 3.0), 0.30)))
    hot = nb.math("MULTIPLY", lit, phase)
    rim_col = (0.30, 0.05, 0.60, 1.0)       # violet night-side airglow
    sun_col = (1.0, 0.16, 0.05, 1.0)        # red-orange forward scattering near the star
    col = nb.mix(nb.math("MINIMUM", nb.math("MULTIPLY", hot, 1.5), 1.0), rim_col, sun_col)
    strength = nb.math("MULTIPLY", prof, nb.math("ADD", 0.28, nb.math("MULTIPLY", hot, 2.2)))
    strength = nb.math("MULTIPLY", strength, nb.math("SUBTRACT", 1.0, geo.outputs["Backfacing"]))
    nb.out(nb.add(nb.transparent(), nb.emission(col, strength)))
    return m


def upgrade_player_materials(ship):
    """Rename the icon ship's materials and give the hull subtle panel lines + plate tone variation."""
    for slot in ship.material_slots:
        m = slot.material
        m.name = "P_" + m.name
    hull = bpy.data.materials["P_Hull"]
    nt = hull.node_tree
    nb = NB(nt)
    bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
    tc = nb.node("ShaderNodeTexCoord")
    vor = nb.node("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.distance = "CHEBYCHEV"
    vor.inputs["Scale"].default_value = 1.7
    nb.put(vor.inputs["Vector"], tc.outputs["Object"])
    line = nb.maprange(vor.outputs["Distance"], 0.0, 0.016, 1.0, 0.0)
    vor_c = nb.node("ShaderNodeTexVoronoi")
    vor_c.distance = "CHEBYCHEV"
    vor_c.inputs["Scale"].default_value = 1.7
    nb.put(vor_c.inputs["Vector"], tc.outputs["Object"])
    tone = nb.maprange(nb.sep(vor_c.outputs["Color"])[0], 0.0, 1.0, 0.86, 1.0, smooth=False)
    base = (0.80, 0.84, 0.88, 1.0)
    col = nb.mix(1.0, base, nb.comb(tone, tone, tone), blend="MULTIPLY")
    col = nb.mix(nb.math("MULTIPLY", line, 0.14), col, (0.16, 0.18, 0.22, 1.0))   # 0.32 read as cracks at 1840 px
    nb.put(bsdf.inputs["Base Color"], col)
    bsdf.inputs["Metallic"].default_value = 0.08
    bsdf.inputs["Roughness"].default_value = 0.30
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.35
    bump = nb.node("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    bump.inputs["Distance"].default_value = 0.01
    nb.put(bump.inputs["Height"], nb.math("SUBTRACT", 1.0, line))
    nb.L.new(bump.outputs[0], bsdf.inputs["Normal"])
    acc = bpy.data.materials["P_Accent"]
    ab = [n for n in acc.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
    ab.inputs["Emission Color"].default_value = (*CYAN, 1.0)
    ab.inputs["Emission Strength"].default_value = 4.8


# ------------------------------------------------------------------------------------------------
# scene
# ------------------------------------------------------------------------------------------------
class Scene:
    pass


def setup_render(samples, threads):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_adaptive_sampling = True
    scn.cycles.adaptive_threshold = 0.012
    scn.cycles.adaptive_min_samples = 16
    scn.cycles.use_denoising = True
    scn.cycles.denoiser = "OPENIMAGEDENOISE"
    try:
        scn.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
        scn.cycles.denoising_quality = "HIGH"
    except Exception:
        pass
    scn.cycles.max_bounces = 8
    scn.cycles.diffuse_bounces = 2
    scn.cycles.glossy_bounces = 3
    scn.cycles.transmission_bounces = 2
    scn.cycles.transparent_max_bounces = 32
    scn.cycles.sample_clamp_indirect = 6.0
    scn.cycles.blur_glossy = 0.6
    scn.render.film_transparent = True
    scn.render.compositor_device = "CPU"       # the GPU default produced intermittent garbage headless
    scn.render.compositor_precision = "FULL"
    scn.render.threads_mode = "FIXED" if threads > 0 else "AUTO"
    if threads > 0:
        scn.render.threads = threads
    scn.render.resolution_percentage = 100
    # 16-bit uncompressed TIFF out of Blender (view transform applied, no ordered dither pattern),
    # converted to 8-bit PNG with random TPDF dither in tiff16_to_png()
    scn.render.image_settings.file_format = "TIFF"
    scn.render.image_settings.color_mode = "RGB"
    scn.render.image_settings.color_depth = "16"
    scn.render.image_settings.tiff_codec = "NONE"
    scn.render.dither_intensity = 0.0
    vs = scn.view_settings
    vs.view_transform = "AgX"
    vs.look = LOOK
    vs.exposure = EXPOSURE
    vs.gamma = 1.0


def sun_lamp(name, toward_light, strength, color, angle=2.0, receivers=None):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = strength
    ld.color = color
    ld.angle = math.radians(angle)
    lo = link_obj(bpy.data.objects.new(name, ld))
    lo.rotation_euler = (-toward_light).to_track_quat("-Z", "Y").to_euler()
    if receivers is not None:
        lo.light_linking.receiver_collection = receivers
    return lo


def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    objs = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in objs if o.type == "MESH"]
    for o in objs:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    return meshes


def planet_geometry():
    star = dir_ae(*STAR_AZEL)
    down = (Vector((0, 0, -1)) - star * star.z).normalized()
    beta = math.radians(PLANET_ALPHA + STAR_ABOVE * STAR_R)
    pdir = (star * math.cos(beta) + down * math.sin(beta)).normalized()
    pdir = Quaternion(star, math.radians(PLANET_TILT)) @ pdir
    dist = PLANET_R / math.sin(math.radians(PLANET_ALPHA))
    return star, pdir, pdir * dist


def build_static(S):
    """Everything that does not depend on the framing: ships, planet, lights, materials."""
    star, pdir, center = planet_geometry()
    S.star, S.pdir, S.planet_center = star, pdir, center
    # --- the player's ship (gen_icon.player_ship resets the file, so it comes first) -----------
    ship = player_ship()
    FA.smooth_weighted(ship, 30.0)          # no triangle shading seams on the nose at 1840 px
    upgrade_player_materials(ship)
    S.ship = ship
    scn = bpy.context.scene
    S.ships_coll = bpy.data.collections.new("ShipsRecv")      # light linking: fill/bounce only on ships
    S.planet_coll = bpy.data.collections.new("PlanetRecv")
    S.rim_coll = bpy.data.collections.new("RimRecv")           # fighters with the extra rim light
    S.ships_coll.objects.link(ship)
    ship_details(S, ship)

    # --- planet Xhal ----------------------------------------------------------------------------
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=384, v_segments=192, radius=PLANET_R)
    planet = obj_from_bm("Xhal", bm)
    planet.location = center
    planet.rotation_euler = tuple(math.radians(a) for a in PLANET_SPIN)
    planet.data.materials.append(mat_planet(star))
    planet.visible_shadow = False
    S.planet_coll.objects.link(planet)
    R_sh = PLANET_R * (1.0 + ATMO_H)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=384, v_segments=192, radius=R_sh)
    atmo = obj_from_bm("XhalAtmo", bm)
    atmo.location = center
    atmo.data.materials.append(mat_atmosphere(center, PLANET_R, R_sh, star))
    fx_only(atmo)
    S.planet, S.atmo = planet, atmo

    # --- lights ---------------------------------------------------------------------------------
    # Vorrhal lights the ships only: on Xhal it would add thin sunlit terminator slivers along the limb
    # (bright coast lines streaking into the title zones); the atmosphere shader carries the limb light
    sun_lamp("Vorrhal", star, SUN["strength"], SUN["color"], angle=2 * STAR_R, receivers=S.ships_coll)
    sun_lamp("FighterRim", star, FIGHTER_RIM["strength"], FIGHTER_RIM["color"], angle=2 * STAR_R,
             receivers=S.rim_coll)
    up = Vector((0, 0, 1))
    right = star.cross(up).normalized()
    fill_dir = (-star * 0.55 - right * 0.65 + up * 0.55).normalized()
    sun_lamp("Fill", fill_dir, FILL["strength"], FILL["color"], angle=8.0, receivers=S.ships_coll)
    sun_lamp("Bounce", pdir, BOUNCE["strength"], BOUNCE["color"], angle=30.0, receivers=S.ships_coll)
    sun_lamp("PlanetFill", (-star * 0.8 + up * 0.2).normalized(), PLANET_FILL["strength"], PLANET_FILL["color"],
             angle=10.0, receivers=S.planet_coll)
    world = bpy.data.worlds.new("Space")
    if not world.node_tree:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.006, 0.004, 0.012, 1.0)
    bg.inputs[1].default_value = 1.0
    scn.world = world

    # --- enemy fighters (positions are set in layout) --------------------------------------------
    proto = import_glb("fighter")[0]
    for slot in proto.material_slots:
        slot.material.name = "F_" + slot.material.name.split(".")[0]
        slot.material.cycles.emission_sampling = "NONE"
    S.fighters = []
    for i in range(MAX_FIGHTERS):
        ob = proto if i == 0 else link_obj(bpy.data.objects.new("Fighter%d" % i, proto.data))
        ob.name = "Fighter%d" % i
        S.ships_coll.objects.link(ob)
        add_plumes(ob, [(-0.95, -3.66, -0.04), (0.95, -3.66, -0.04)], 0.36, 5.0, "FighterPlume")
        S.fighters.append(ob)
    S.debris_src = import_glb("debris")
    for o in S.debris_src:
        o.hide_render = True
    S.dynamic = []


def add_plumes(ship, nozzles, radius, length, kind):
    if kind == "FighterPlume":
        mat = bpy.data.materials.get(kind) or mat_glow_tube(kind, (1.0, 0.72, 0.40), 7.0, (1.0, 0.30, 0.05), 2.4,
                                                           power=1.8)
    else:
        mat = bpy.data.materials.get(kind) or mat_glow_tube(kind, (0.80, 1.0, 1.0), 4.8, CYAN, 1.56, power=2.0)
    for (x, y, z) in nozzles:
        prof = [(0.0, radius * 0.25), (0.55, radius * 0.75), (0.93, radius), (1.0, radius * 0.92)]
        ob = obj_from_bm(kind, bm_tube(length, prof, sides=16), mat)
        # tube runs along local +Y from 0 (tail) to length (nozzle) -> place the nozzle at (x, y, z)
        ob.parent = ship
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.location = (x, y - length, z)
        ob["nozzle"] = (x, y, z)
        ob["length"] = length
        fx_only(ob)


def ship_details(S, ship):
    """Scene-only extras on the icon ship: wing-tip cannons and engine plumes."""
    dark = bpy.data.materials["P_HullDark"]
    acc = bpy.data.materials["P_Accent"]
    parts = []
    for sx in (-1, 1):
        parts.append(obj_from_bm("cannon", B.bm_cyl((sx * 3.42, -1.6, -0.08), (sx * 3.42, 0.9, -0.08), 0.09, 0.065,
                                                    sides=10), dark))
        parts.append(obj_from_bm("cannon_tip", B.bm_cyl((sx * 3.42, 0.9, -0.08), (sx * 3.42, 1.05, -0.08), 0.05, 0.05,
                                                        sides=10), acc))
    for p in parts:
        p.parent = ship
        p.matrix_parent_inverse = Matrix.Identity(4)
        S.ships_coll.objects.link(p)
    add_plumes(ship, [(-0.75, -3.36, -0.05), (0.75, -3.36, -0.05)], 0.26, 2.6, "PlayerPlume")


def place_tube(S, name, p0, p1, profile, mat, sides=12):
    """Glow tube from p0 (tail) to p1 (head)."""
    d = p1 - p0
    ob = obj_from_bm(name, bm_tube(d.length, profile, sides), mat)
    ob.matrix_world = Matrix.Translation(p0) @ orient(d, 0.0).to_4x4()
    S.dynamic.append(ob)
    return fx_only(ob)


def clear_dynamic(S):
    for ob in S.dynamic:
        me = ob.data if ob.type == "MESH" else None
        lt = ob.data if ob.type == "LIGHT" else None
        bpy.data.objects.remove(ob)
        if me is not None and me.users == 0 and not me.name.startswith("Debris"):
            bpy.data.meshes.remove(me)
        if lt is not None and lt.users == 0:
            bpy.data.lights.remove(lt)
    S.dynamic = []


def make_cameras(S):
    for c in list(getattr(S, "cams", {}).values()):
        bpy.data.objects.remove(c)
    S.cams = {}
    for name, c in CAMERAS.items():
        w, h = c["preview"]
        tx, ty = cam_tan(c["lens"], w, h)
        R = solve_cam_rot(S.star, c["star"][0], c["star"][1], tx, ty, c["roll"])
        cd = bpy.data.cameras.new("Cam_" + name)
        cd.lens = c["lens"]
        cd.sensor_fit = "AUTO"
        cd.sensor_width = 36.0
        cd.clip_start = 0.3
        cd.clip_end = 400000.0
        cam = link_obj(bpy.data.objects.new("Cam_" + name, cd))
        ray = R @ screen_dir_cam(c["ship"][0], c["ship"][1], tx, ty)
        cam.matrix_world = Matrix.Translation(-ray * c["dist"]) @ R.to_4x4()
        S.cams[name] = cam
    bpy.context.view_layer.update()


def layout(S, view):
    """Block the actors for one camera: ship pose, laser target + explosion, fighters, enemy bolts."""
    clear_dynamic(S)
    c = CAMERAS[view]
    cam = S.cams[view]
    tx, ty = cam_tan(c["lens"], *c["preview"])
    CR = cam.matrix_world.to_3x3()
    cpos = cam.matrix_world.translation

    def screen_point(screen, d):
        return cpos + (CR @ screen_dir_cam(screen[0], screen[1], tx, ty)) * d

    # player ship (origin): nose at the target, top surface towards the camera, rolled by roll_up
    S.target = screen_point(*c["target"])
    heading = S.target.normalized()
    to_cam = cpos.normalized()
    up = (to_cam - heading * to_cam.dot(heading)).normalized()
    up = Quaternion(heading, -math.radians(c["roll_up"])) @ up
    S.ship.matrix_world = Matrix((heading.cross(up), heading, up)).transposed().to_4x4()
    S.view_angle = math.degrees(heading.angle(-to_cam))
    bpy.context.view_layer.update()
    S.muzzles = [S.ship.matrix_world @ Vector((sx * 3.42, 1.1, -0.08)) for sx in (-1, 1)]
    # fighters (unused ones are hidden); silhouette / rim / plume scale per shot
    for i, ob in enumerate(S.fighters):
        sil = i in c.get("silhouette", [])
        if sil and ob.name in S.ships_coll.objects:
            S.ships_coll.objects.unlink(ob)
        elif not sil and ob.name not in S.ships_coll.objects:
            S.ships_coll.objects.link(ob)
        rim = c.get("rim", {})
        if i in rim and ob.name not in S.rim_coll.objects:
            S.rim_coll.objects.link(ob)
        elif i not in rim and ob.name in S.rim_coll.objects:
            S.rim_coll.objects.unlink(ob)
        ps = rim.get(i, 1.0)
        for ch in ob.children:
            if "nozzle" in ch:
                x, y, z = ch["nozzle"]
                ch.location = (x, y - ch["length"] * ps, z)
                ch.scale = (ps, ps, ps)
        if i >= len(c["fighters"]):
            ob.hide_render = True
            for ch in ob.children:
                ch.hide_render = True
            continue
        sx, sy, d, bank, yaw = c["fighters"][i]
        ob.hide_render = False
        for ch in ob.children:
            ch.hide_render = False
        pos = screen_point((sx, sy), d)
        to_player = (Vector((0, 0, 0)) - pos).normalized()
        hd = Quaternion(Vector((0, 0, 1)), math.radians(yaw)) @ to_player
        ob.matrix_world = Matrix.Translation(pos) @ orient(hd, bank).to_4x4()
    bpy.context.view_layer.update()
    S.keep = None
    if c.get("title_zone"):
        zx, zy = c["title_zone"]

        def keep(p, cpos=cpos, CR=CR, tx=tx, ty=ty):
            q = CR.transposed() @ (Vector(p) - cpos)
            if q.z > -1e-3:
                return True
            sx = 0.5 + 0.5 * (q.x / -q.z) / tx
            sy = 0.5 - 0.5 * (q.y / -q.z) / ty
            return not (sx < zx and sy < zy)
        S.keep = keep
    lasers(S)
    enemy_bolts(S, c["bolts"])
    if c.get("fire") == "volume":
        explosion_volume(S, cam)
    else:
        explosion(S)
    face_billboards(S, cam)


def lasers(S):
    flash = bpy.data.materials.get("Muzzle")
    if flash is None:
        flash, nb = new_mat("Muzzle")
        lw = nb.node("ShaderNodeLayerWeight")
        face = nb.math("POWER", nb.math("SUBTRACT", 1.0, lw.outputs["Facing"], clamp=True), 2.5)
        col = nb.mix(nb.math("POWER", face, 2.0), CYAN + (1.0,), (0.85, 1.0, 1.0, 1.0))
        nb.out(nb.add(nb.transparent(), nb.emission(col, nb.math("MULTIPLY", face, 7.0))))
    for m in S.muzzles:
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.12)
        ob = obj_from_bm("Muzzle", bm, flash)
        ob.location = m
        fx_only(ob)
        S.dynamic.append(ob)
    core = bpy.data.materials.get("LaserCore") or mat_glow_tube("LaserCore", (0.80, 1.0, 1.0), 30.0, CYAN, 7.0,
                                                                  power=1.4, tail=0.45)
    halo = bpy.data.materials.get("LaserHalo") or mat_glow_tube("LaserHalo", CYAN, 0.0, CYAN, 1.2, power=2.5,
                                                                  tail=0.6)
    tgt = S.target
    for k, m in enumerate(S.muzzles):
        d = tgt - m
        L = d.length
        dn = d.normalized()
        # one continuous beam per cannon (concept C had three short dashes that read as scattered specks);
        # it starts right at the muzzle: the cannons are close to the camera, a 5 % gap would show
        p0, p1 = m + dn * 0.15, m + dn * (0.97 * L)
        place_tube(S, "Laser", p0, p1, [(0.0, 0.0), (0.012, 0.052), (0.5, 0.0715), (0.985, 0.0715), (1.0, 0.0)],
                   core, sides=12)
        place_tube(S, "LaserHalo", p0, p1, [(0.0, 0.0), (0.02, 0.20), (0.5, 0.26), (0.98, 0.26), (1.0, 0.0)],
                   halo, sides=14)


def enemy_bolts(S, bolts):
    core = bpy.data.materials.get("BoltCore") or mat_glow_tube("BoltCore", (1.0, 0.70, 0.45), 26.0, ALERT, 7.0,
                                                                 power=1.4, tail=0.2)
    halo = bpy.data.materials.get("BoltHalo") or mat_glow_tube("BoltHalo", ALERT, 0.0, ALERT, 1.2, power=2.5)
    for (fi, a, b, miss) in bolts:
        f = S.fighters[fi]
        src = f.matrix_world @ Vector((0.0, 4.0, -0.16))
        dst = Vector((miss[0], 0.0, miss[1]))
        d = dst - src
        p0, p1 = src + d * a, src + d * b
        place_tube(S, "Bolt", p0, p1, [(0, 0), (0.08, 0.10), (0.9, 0.12), (1, 0)], core, sides=10)
        place_tube(S, "BoltHalo", p0, p1, [(0, 0), (0.1, 0.45), (0.9, 0.55), (1, 0)], halo, sides=14)


def explosion(S):
    """Fireball billboards (flipbook frames), a hot flash, sparks and tumbling debris at the target."""
    c = S.target
    img = bpy.data.images.load(os.path.join(TEX, "fx", "explosion_flipbook.png"), check_existing=True)
    img.colorspace_settings.name = "sRGB"
    S.billboards = []
    rng = np.random.default_rng(7)
    layers = [(15, 7.5, 1.8), (12, 5.5, 2.3), (9, 3.6, 3.0)]   # frame, size (m), strength
    for i, (frame, size, strength) in enumerate(layers):
        m = bpy.data.materials.get("Fireball%d" % i)
        if m is None:
            m, nb = new_mat("Fireball%d" % i)
            tx = nb.node("ShaderNodeTexImage", image=img, interpolation="Linear", extension="CLIP")
            tc = nb.node("ShaderNodeTexCoord")
            nb.put(tx.inputs[0], tc.outputs["UV"])
            em = nb.emission(nb.mix(1.0, tx.outputs["Color"], (1.0, 0.62, 0.42, 1.0), blend="MULTIPLY"), strength)
            nb.out(nb.mixsh(tx.outputs["Alpha"], nb.transparent(), em))
        col, row = frame % 8, frame // 8
        u0, u1 = col / 8.0, (col + 1) / 8.0
        v0, v1 = 1.0 - (row + 1) / 8.0, 1.0 - row / 8.0
        bm = bmesh.new()
        vs = [bm.verts.new((-0.5, -0.5, 0)), bm.verts.new((0.5, -0.5, 0)), bm.verts.new((0.5, 0.5, 0)),
              bm.verts.new((-0.5, 0.5, 0))]
        f = bm.faces.new(vs)
        uvl = bm.loops.layers.uv.new("UVMap")
        for loop, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            loop[uvl].uv = uv
        ob = obj_from_bm("Fireball%d" % i, bm, m, smooth=False)
        fx_only(ob)
        S.dynamic.append(ob)
        off = Vector(rng.normal(0, 0.5, 3))
        S.billboards.append((ob, c + off, size, rng.uniform(0, 360), i * 0.4))
    m = bpy.data.materials.get("Flash")
    if m is None:
        m, nb = new_mat("Flash")
        lw = nb.node("ShaderNodeLayerWeight")
        face = nb.math("POWER", nb.math("SUBTRACT", 1.0, lw.outputs["Facing"], clamp=True), 2.0)
        nb.out(nb.add(nb.transparent(), nb.emission((1.0, 0.62, 0.32, 1.0), nb.math("MULTIPLY", face, 6.0))))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.7)
    fl = obj_from_bm("Flash", bm, m)
    fl.location = c
    fx_only(fl)
    S.dynamic.append(fl)
    ld = bpy.data.lights.new("FireLight", "POINT")
    ld.energy = 3.5e4
    ld.color = (1.0, 0.40, 0.12)
    ld.shadow_soft_size = 3.0
    lo = link_obj(bpy.data.objects.new("FireLight", ld))
    lo.location = c
    S.dynamic.append(lo)
    spark = bpy.data.materials.get("Spark") or mat_glow_tube("Spark", (1.0, 0.85, 0.6), 14.0, AMBER, 3.5,
                                                               power=1.5)
    for k in range(10):
        d = Vector(rng.normal(0, 1, 3)).normalized()
        p0 = c + d * rng.uniform(1.8, 3.5)
        place_tube(S, "Spark", p0, p0 + d * rng.uniform(1.2, 3.0), [(0, 0), (0.1, 0.02), (0.85, 0.04), (1, 0)],
                   spark, sides=6)
    for k in range(5):
        src = S.debris_src[k % len(S.debris_src)]
        ob = link_obj(bpy.data.objects.new("Debris%d" % k, src.data))
        d = Vector(rng.normal(0, 1, 3)).normalized()
        ob.location = c + d * rng.uniform(2.5, 5.0)
        ob.rotation_euler = tuple(rng.uniform(0, 6.28, 3))
        s = rng.uniform(0.45, 0.75)
        ob.scale = (s, s, s)
        S.ships_coll.objects.link(ob)
        S.dynamic.append(ob)


def explosion_volume(S, cam):
    """Concept A's hot fireball card + flash + shockwave ring + fragments + sparks + light (final_a), facing
    this camera, culled out of the title zone; plus three debris.glb pieces. Fighter 0 (the silhouette)
    is not lit by the fire: the explosion light is linked to the ships collection only."""
    c = S.target
    cpos = cam.matrix_world.translation
    before = set(bpy.data.objects)
    fwd = (Vector((0, 0, 0)) - c).normalized()      # the exploding fighter was flying at the player
    FA.build_explosion(c, fwd, seed=3, keep=S.keep, eye=cpos)
    for ob in bpy.data.objects:
        if ob in before:
            continue
        S.dynamic.append(ob)
        if ob.type == "LIGHT":
            ob.light_linking.receiver_collection = S.ships_coll
    S.billboards = []
    rng = np.random.default_rng(7)
    for k in range(3):
        src = S.debris_src[k % len(S.debris_src)]
        d = Vector(rng.normal(0, 1, 3)).normalized()
        p = c + d * rng.uniform(4.0, 7.0)
        if S.keep is not None and not S.keep(p):
            continue
        ob = link_obj(bpy.data.objects.new("Debris%d" % k, src.data))
        ob.location = p
        ob.rotation_euler = tuple(rng.uniform(0, 6.28, 3))
        s_ = rng.uniform(0.55, 0.9)
        ob.scale = (s_, s_, s_)
        S.ships_coll.objects.link(ob)
        S.dynamic.append(ob)


def face_billboards(S, cam):
    cp = cam.matrix_world.translation
    for ob, pos, size, spin, push in S.billboards:
        d = (cp - pos).normalized()
        q = d.to_track_quat("Z", "Y") @ Quaternion(Vector((0, 0, 1)), math.radians(spin))
        ob.matrix_world = Matrix.LocRotScale(pos + d * push, q, Vector((size, size, size)))


# ------------------------------------------------------------------------------------------------
# numpy background: nebula + stars + the star Vorrhal with corona
# ------------------------------------------------------------------------------------------------
def nebula_map():
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "concept_c_nebula.npy")
    if os.path.exists(path):
        return np.load(path).astype(F32)
    from PIL import Image
    from scipy import ndimage
    im = np.asarray(Image.open(os.path.join(TEX, "sky", "space_panorama_enemy.png")).convert("RGB")).astype(F32) / 255
    lin = np.where(im <= 0.04045, im / 12.92, ((im + 0.055) / 1.055) ** 2.4).astype(F32)
    small = lin.reshape(512, 4, 1024, 4, 3).mean(axis=(1, 3))       # 1024 x 512, stars shrink to ~1-5 px
    out = np.empty_like(small)
    yy, xx = np.mgrid[-3:4, -3:4]
    disk = (xx * xx + yy * yy) <= 10           # round footprint: no axis-aligned plateaus (grid lines)
    for k in range(3):     # opening + median remove the point stars and their halos, keep the gas
        o = ndimage.grey_opening(small[..., k], footprint=disk, mode="wrap")
        o = ndimage.median_filter(o, footprint=disk, mode="wrap")
        out[..., k] = ndimage.gaussian_filter(o, 3.0, mode="wrap")
    np.save(path, out.astype(np.float16))
    return out.astype(F32)


def view_dirs(cam, w, h, lens):
    tx, ty = cam_tan(lens, w, h)
    R = np.array(cam.matrix_world.to_3x3(), dtype=np.float64)
    xs = ((np.arange(w) + 0.5) / w * 2.0 - 1.0) * tx
    ys = (1.0 - (np.arange(h) + 0.5) / h * 2.0) * ty
    X, Y = np.meshgrid(xs, ys)
    d = np.stack([X, Y, -np.ones_like(X)], axis=-1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    return (d @ R.T).astype(F32), tx, ty


def star_field(cam, w, h, lens, k_res):
    """Crisp procedural stars (same sky for every camera), splatted as small gaussians."""
    rng = np.random.default_rng(1986)
    n = 110000
    v = rng.normal(size=(n, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    u = rng.uniform(1e-4, 1.0, n)
    mag = np.clip(0.008 * u ** -0.9, 0, 6.0)
    tint = rng.uniform(0, 1, n)
    cols = np.array([[0.70, 0.80, 1.00], [1.00, 0.97, 0.92], [1.00, 0.80, 0.55], [1.00, 0.55, 0.40]], F32)
    col = cols[np.digitize(tint, [0.30, 0.72, 0.90])]
    R = np.array(cam.matrix_world.to_3x3(), dtype=np.float64)
    c = v @ R               # camera space
    front = c[:, 2] < -1e-3
    c, mag, col = c[front], mag[front], col[front]
    tx, ty = cam_tan(lens, w, h)
    px = ((c[:, 0] / -c[:, 2]) / tx + 1.0) * 0.5 * w - 0.5
    py = (1.0 - (c[:, 1] / -c[:, 2]) / ty) * 0.5 * h - 0.5
    ok = (px > -4) & (px < w + 3) & (py > -4) & (py < h + 3)
    px, py, mag, col = px[ok], py[ok], mag[ok], col[ok]
    img = np.zeros((h, w, 3), F32)
    sig = (0.55 + 0.20 * np.sqrt(mag)) * k_res
    ix0, iy0 = np.floor(px).astype(int), np.floor(py).astype(int)
    rad = min(int(math.ceil(3 * sig.max())), 6)
    for dy in range(-rad, rad + 2):
        for dx in range(-rad, rad + 2):
            xx, yy = ix0 + dx, iy0 + dy
            wgt = np.exp(-((xx - px) ** 2 + (yy - py) ** 2) / (2 * sig ** 2)) / (2 * np.pi * sig ** 2) * k_res ** 2
            m = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h) & (wgt > 1e-5)
            np.add.at(img, (yy[m], xx[m]), (col[m] * (mag[m] * wgt[m])[:, None]).astype(F32))
    return img


NEB_YAW = 3.30      # rotate the panorama: violet gas on the left, red around the star
NEB_GAIN = (1.25, 0.80, 2.1)


def background(S, cam, w, h, lens, k_res):
    from scipy import ndimage
    t0 = time.time()
    d, tx, ty = view_dirs(cam, w, h, lens)
    img = np.zeros((h, w, 3), F32)
    # nebula (panorama in Godot convention: lon = atan2(x, y_blender), lat = asin(z))
    neb = nebula_map()
    lon = np.arctan2(d[..., 0], d[..., 1])
    lat = np.arcsin(np.clip(d[..., 2], -1, 1))
    uu = ((lon + NEB_YAW) / (2 * np.pi) + 0.5) % 1.0 * neb.shape[1] - 0.5
    vv = (0.5 - lat / np.pi) * neb.shape[0] - 0.5
    for k in range(3):
        img[..., k] = ndimage.map_coordinates(neb[..., k], [vv.ravel(), uu.ravel()], order=3,   # cubic: no
                                              mode="grid-wrap").reshape(h, w) * NEB_GAIN[k]       # texel grid
    img += star_field(cam, w, h, lens, k_res)
    # star Vorrhal: disc + corona
    s = np.array(S.star, F32)
    e1 = np.array(S.star.cross(Vector((0, 0, 1))).normalized(), F32)
    e2 = np.cross(e1, s)
    theta = np.arccos(np.clip(d @ s, -1, 1))
    rs = math.radians(STAR_R)
    rho = theta / rs
    phi = np.arctan2(d @ e2, d @ e1)
    px_per_rad = w / (2 * math.atan(tx))
    # angular height above Xhal's limb (in star radii) -> extinction / reddening near the horizon
    pang = np.arccos(np.clip(d @ np.array(S.pdir, F32), -1, 1))
    above = (pang - math.radians(PLANET_ALPHA)) / rs
    fr = Fractal3(seed=11)
    disc = rho < 1.0 + 3.0 / (rs * px_per_rad)
    if disc.any():
        r_ = rho[disc]
        mu = np.sqrt(np.clip(1.0 - r_ ** 2, 0, 1))
        q = np.stack([r_ * np.cos(phi[disc]), r_ * np.sin(phi[disc]), mu], -1).astype(F32)
        # big convection cells (red giant) + finer granulation, cell borders darker
        cells = fr.ridged(q, 2.2, 3, sharp=1.6)
        gran = fr.fbm(q + 7.3, 7.0, 4)
        ld = np.clip(1.0 - STAR["ld1"] * (1.0 - mu) - STAR["ld2"] * (1.0 - mu) ** 2, 0.02, 1.0)
        inten = np.clip(ld * (0.80 - 0.1 * STAR["cells"] + STAR["cells"] * cells + STAR["gran"] * gran), 0, 1.35)[:, None]
        limb_c = np.array([1.0, 0.030, 0.010], F32) * 0.50
        mid_c = np.array([1.0, 0.075, 0.020], F32) * 0.80
        hot_c = np.array([1.0, 0.20, 0.050], F32) * 1.90
        white_c = np.array([1.0, 0.38, 0.13], F32) * 2.8
        t1 = np.clip(inten / 0.55, 0, 1)
        t2 = np.clip((inten - 0.55) / 0.35, 0, 1)
        t3 = np.clip((inten - 0.92) / 0.25, 0, 1)
        col = limb_c + (mid_c - limb_c) * t1 + (hot_c - mid_c) * t2 ** 1.3 + (white_c - hot_c) * t3 ** 1.5
        ext = smoothstep(0.0, 0.8, above[disc])[:, None]          # seen through Xhal's atmosphere
        col = col * (0.5 + 0.5 * ext) * np.array([1.0, 0.45, 0.4], F32) ** (1.0 - ext) * F32(2.0 ** STAR["ev"])
        edge = np.clip((1.0 - r_) * rs * px_per_rad + 0.5, 0, 1)[:, None]
        img[disc] = img[disc] * (1 - edge) + col * edge
    # corona: chromosphere glow, streamers with fine filaments, wide warm haze
    q = np.maximum(rho - 1.0, 0.0)
    pc = np.stack([np.cos(phi) * 2.0, np.sin(phi) * 2.0, np.log1p(q * 2.0) * 1.3], -1).astype(F32)
    ray = fr.ridged(pc, 1.8, 5, sharp=2.6)
    fil = fr.ridged(pc * np.array([3.0, 3.0, 0.6], F32) + 5.0, 2.0, 3, sharp=4.0)
    soft = fr.fbm(pc * 0.6 + 3.1, 1.0, 3) * 0.5 + 0.5
    streak = 0.25 + 1.5 * ray * soft + 0.6 * fil * soft
    chrom = np.exp(-q / 0.045)
    mid = np.exp(-q / 0.28) * streak
    outer = np.exp(-q / 0.9) * (0.6 + 0.6 * soft)
    halo = 1.0 / (1.0 + (q / 2.2) ** 2)
    ext = (0.35 + 0.65 * smoothstep(-0.2, 0.9, above))[..., None]
    out_mask = np.clip((rho - 1.0) * rs * px_per_rad + 0.5, 0, 1)[..., None]   # anti-aliased, complements the disc
    cor = (chrom[..., None] * np.array([1.0, 0.09, 0.03], F32) * 0.30 +
           mid[..., None] * np.array([1.0, 0.07, 0.03], F32) * 0.55 +
           outer[..., None] * np.array([0.85, 0.05, 0.09], F32) * 0.10 +
           halo[..., None] * np.array([0.30, 0.025, 0.14], F32) * 0.035)
    ramp = (0.45 + 0.55 * smoothstep(0.0, 0.12, q))[..., None]
    img += cor * out_mask * ext * ramp
    rgba = np.concatenate([img, np.ones((h, w, 1), F32)], -1)
    print("  background %dx%d in %.1fs" % (w, h, time.time() - t0))
    return rgba


def vignette(w, h, strength=0.40):
    y, x = np.mgrid[0:h, 0:w].astype(F32)
    nx = (x + 0.5) / w * 2 - 1
    ny = (y + 0.5) / h * 2 - 1
    r = np.sqrt((nx * 0.92) ** 2 + (ny * 0.92) ** 2)
    v = 1.0 - strength * smoothstep(0.55, 1.35, r)
    return np.dstack([v, v, v, np.ones_like(v)]).astype(F32)


def numpy_to_image(name, arr):
    h, w = arr.shape[:2]
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Linear Rec.709"
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).ravel())
    img.update()
    return img


# ------------------------------------------------------------------------------------------------
# compositor
# ------------------------------------------------------------------------------------------------
GLARE = dict(bloom_threshold=0.9, bloom_strength=0.55, bloom_size=0.85,
             fog_threshold=2.5, fog_strength=0.25, fog_size=0.35)


def setup_compositor(bg_img, vig_img):
    scn = bpy.context.scene
    ng = bpy.data.node_groups.get("Comp_C")
    if ng is not None:
        bpy.data.node_groups.remove(ng)
    ng = bpy.data.node_groups.new("Comp_C", "CompositorNodeTree")
    ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    N, L = ng.nodes, ng.links
    rl = N.new("CompositorNodeRLayers")
    bg = N.new("CompositorNodeImage")
    bg.image = bg_img
    ao = N.new("CompositorNodeAlphaOver")
    ao.inputs["Straight Alpha"].default_value = False
    L.new(bg.outputs["Image"], ao.inputs["Background"])
    L.new(rl.outputs["Image"], ao.inputs["Foreground"])
    g1 = N.new("CompositorNodeGlare")
    g1.inputs["Type"].default_value = "Bloom"
    g1.inputs["Quality"].default_value = "High"
    g1.inputs["Threshold"].default_value = GLARE["bloom_threshold"]
    g1.inputs["Smoothness"].default_value = 0.5
    g1.inputs["Strength"].default_value = GLARE["bloom_strength"]
    g1.inputs["Size"].default_value = GLARE["bloom_size"]
    L.new(ao.outputs["Image"], g1.inputs["Image"])
    g2 = N.new("CompositorNodeGlare")
    g2.inputs["Type"].default_value = "Fog Glow"
    g2.inputs["Quality"].default_value = "High"
    g2.inputs["Threshold"].default_value = GLARE["fog_threshold"]
    g2.inputs["Smoothness"].default_value = 0.4
    g2.inputs["Strength"].default_value = GLARE["fog_strength"]
    g2.inputs["Size"].default_value = GLARE["fog_size"]
    L.new(g1.outputs["Image"], g2.inputs["Image"])
    vg = N.new("CompositorNodeImage")
    vg.image = vig_img
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    L.new(g2.outputs["Image"], mix.inputs[6])
    L.new(vg.outputs["Image"], mix.inputs[7])
    out = N.new("NodeGroupOutput")
    L.new(mix.outputs[2], out.inputs[0])
    scn.compositing_node_group = ng


# ------------------------------------------------------------------------------------------------
# render / probe
# ------------------------------------------------------------------------------------------------
STEAM_SIZES = {"hero": (1920, 620), "wide": (920, 430), "portrait": (600, 900)}


def render_view(S, name, final, scale, out_dir, samples, bgonly=False, path=None):
    scn = bpy.context.scene
    c = CAMERAS[name]
    w, h = c["final"] if final else c["preview"]
    w, h = int(round(w * scale)), int(round(h * scale))
    scn.render.resolution_x, scn.render.resolution_y = w, h
    cam = S.cams[name]
    scn.camera = cam
    layout(S, name)
    bpy.context.view_layer.update()
    k_res = w / c["preview"][0]
    bg = background(S, cam, w, h, c["lens"], k_res)
    os.makedirs(out_dir, exist_ok=True)
    if bgonly:      # background through the scene's view transform (no bloom)
        p = os.path.join(out_dir, "final_c_%s_bg.png" % name)
        st = scn.render.image_settings
        fmt = (st.file_format, st.color_depth)
        st.file_format, st.color_depth = "PNG", "8"
        numpy_to_image("BGONLY", bg).save_render(p, scene=scn)
        st.file_format, st.color_depth = fmt
        print("BG", p)
        return p, 0.0
    setup_compositor(numpy_to_image("BG_" + name, bg), numpy_to_image("VIG_" + name, vignette(w, h)))
    path = path or os.path.join(out_dir, "final_c_%s.png" % name)
    tif = os.path.splitext(path)[0] + "_16bit.tif"
    scn.render.filepath = tif
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    dt = time.time() - t0
    tiff16_to_png(tif, path, None)          # the 16-bit TIFF is kept: compose_steam_assets.py reads it
    print("RENDERED %s %dx%d %d spp in %.1fs -> %s" % (name, w, h, scn.cycles.samples, dt, path))
    return path, dt


def read_tiff16(path):
    """Minimal reader for the uncompressed, chunky 16-bit RGB TIFF that Blender writes."""
    import struct
    data = open(path, "rb").read()
    bo = "<" if data[:2] == b"II" else ">"
    ifd = struct.unpack(bo + "I", data[4:8])[0]
    n = struct.unpack(bo + "H", data[ifd:ifd + 2])[0]
    tags = {}
    for i in range(n):
        e = data[ifd + 2 + 12 * i: ifd + 14 + 12 * i]
        tag, typ, cnt = struct.unpack(bo + "HHI", e[:8])
        fmt = {3: "H", 4: "I"}.get(typ)
        if fmt is None:
            continue
        size = struct.calcsize(fmt) * cnt
        raw = e[8:8 + size] if size <= 4 else data[struct.unpack(bo + "I", e[8:12])[0]:][:size]
        tags[tag] = struct.unpack(bo + fmt * cnt, raw)
    w, h, spp = tags[256][0], tags[257][0], tags[277][0]
    assert tags[258][0] == 16 and tags[259][0] == 1 and tags.get(284, (1,))[0] == 1, "unexpected TIFF layout"
    buf = b"".join(data[o:o + c] for o, c in zip(tags[273], tags[279]))
    return np.frombuffer(buf, dtype=bo + "u2").reshape(h, w, spp)[..., :3]


def save_dithered(x, dst, seed=5):
    """x: display-referred float RGB in 0..255 -> 8-bit PNG with TPDF dither (no pattern, no banding)."""
    from PIL import Image
    rng = np.random.default_rng(seed)
    x = x + rng.random(x.shape) - rng.random(x.shape)
    Image.fromarray(np.clip(np.rint(x), 0, 255).astype(np.uint8), "RGB").save(dst, optimize=True)


def tiff16_to_png(src, dst, steam=None):
    """16-bit render -> 8-bit PNG; optionally also a Lanczos downscale (done in float, then dithered)."""
    from PIL import Image
    x = read_tiff16(src).astype(np.float32) * (255.0 / 65535.0)
    save_dithered(x, dst)
    if steam is not None:
        size, sdst = steam
        small = np.dstack([np.asarray(Image.fromarray(np.ascontiguousarray(x[..., k]), "F").resize(size, Image.LANCZOS))
                           for k in range(3)])
        save_dithered(small, sdst, seed=6)


def probe(S):
    from bpy_extras.object_utils import world_to_camera_view
    scn = bpy.context.scene
    for name, c in CAMERAS.items():
        layout(S, name)
        scn.render.resolution_x, scn.render.resolution_y = c["preview"]
        bpy.context.view_layer.update()
        cam = S.cams[name]
        pts = {"ship": Vector((0, 0, 0)), "target": S.target}
        for f in S.fighters:
            if not f.hide_render:
                pts[f.name] = f.matrix_world.translation
        print("--", name, c["preview"], "cam at", tuple(round(v, 1) for v in cam.matrix_world.translation),
              "view angle onto ship %.1f deg" % S.view_angle)
        for k, p in pts.items():
            v = world_to_camera_view(scn, cam, p)
            print("   %-10s x=%.3f y=%.3f d=%.1f" % (k, v.x, 1 - v.y, v.z))
        v = world_to_camera_view(scn, cam, cam.matrix_world.translation + S.star * 1e5)
        print("   %-10s x=%.3f y=%.3f" % ("star", v.x, 1 - v.y))
        tz = c.get("title_zone")
        if tz:
            bad = []
            for ob in S.dynamic + [f for f in S.fighters if not f.hide_render]:
                v = world_to_camera_view(scn, cam, ob.matrix_world.translation)
                if v.z > 0 and v.x < tz[0] and (1 - v.y) < tz[1]:
                    bad.append("%s(%.2f,%.2f)" % (ob.name, v.x, 1 - v.y))
            print("   title zone x<%.2f y<%.2f: %s" % (tz[0], tz[1], ", ".join(bad) or "empty"))


def build(samples=64, threads=2):
    S = Scene()
    t0 = time.time()
    build_static(S)
    make_cameras(S)
    setup_render(samples, threads)
    print("scene built in %.1fs" % (time.time() - t0))
    return S


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--final", action="store_true")
    ap.add_argument("--only", default="wide")
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--threads", type=int, default=-1)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--out", default="")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--bgonly", action="store_true")
    args = ap.parse_args()
    samples = args.samples or (256 if args.final else 64)
    threads = args.threads if args.threads >= 0 else (0 if args.final else 2)
    out_dir = args.out or (RENDERS if args.final else os.path.join(HERE, "previews", "final_c"))
    S = build(samples, threads)
    if args.probe:
        probe(S)
        return
    times = {}
    for name in [n.strip() for n in args.only.split(",") if n.strip()]:
        path, dt = render_view(S, name, args.final, args.scale, out_dir, samples, bgonly=args.bgonly)
        times[name] = dt
    print("TIMES", {k: round(v, 1) for k, v in times.items()})


if __name__ == "__main__":
    main()
