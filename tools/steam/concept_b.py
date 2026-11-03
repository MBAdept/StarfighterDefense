"""
concept_b.py - Steam library artwork, concept B "Das Flaggschiff" (Starfighter Defense).

One Cycles scene, three cameras / framings:
  hero      final 3840x1240 (preview 1920x620)  wide banner; calm, dark left / lower-left third for the Steam logo
  wide      final 1840x860  (preview  920x430)  wide capsule; left ~40 % kept free for the title
  portrait  final 1200x1800 (preview  600x900)  portrait capsule; lower third kept free for the title

Scene: the colossal enemy flagship (assets/models/flagship.glb) seen from below-front, nose slightly down
and banked, so it looms over the camera. Its pink weak point (vivid pink, white-hot core, faint retro
scanlines) is the focal point; a violet-white ion ball (core + additive halos + plasma tendrils) with a
comet trail and spiral ribbons is about to hit it. Three destroyers (destroyer.glb, Accent tinted in the
game colours) in hexagon shield bubbles (blue / red / green) escort it from above, two enemy fighters
with amber exhaust plumes give a scale reference. Scene-only extra detail on the flagship: triplanar
panel lines, rows of lit windows, ~1500 greeble boxes (the asset files are only read, never written).
Lighting: warm sun rim light from behind / upper right (off frame), cyan kicker from the lower left,
faint teal "planet shine" from below, pink spill from the weak point, violet light from the ion ball.
Background (nebula + crisp stars + sun haze) is generated per camera in numpy from the 3D view
directions (so all framings share one sky and stars stay sharp at any resolution) and composited
under the transparent Cycles render. Compositor: mist-based aerial haze (sells the size), Glare bloom,
very subtle horizontal streaks on the hottest highlights, vignette. AgX, Medium High Contrast.
No text is rendered.

Run (bpy 5.2 as module, from the project root or anywhere):
  /opt/tools/venv/bin/python tools/steam/concept_b.py            # previews -> tools/steam/previews/concept_b_*.png
  /opt/tools/venv/bin/python tools/steam/concept_b.py --final    # full res -> tools/steam/final/ (+ Steam sizes)
Options:
  --only hero,wide,portrait   render a subset
  --samples N                 override sample count (preview 64, final 384; adaptive + OpenImageDenoise)
  --threads N                 CPU threads (preview default 2, final default 0 = all cores)
  --scale F                   extra resolution factor (quick layout tests, e.g. 0.5)
  --out DIR                   output directory
  --probe                     print screen positions of key objects per camera (no render)
  --bgonly / --border x0,y0,x1,y1   debugging helpers (background only / render a region)
"""
import argparse
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
sys.path.insert(0, os.path.join(ROOT, "tools", "textures"))
import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402
from noiselib import Fractal3, smoothstep  # noqa: E402
from scipy.special import erf  # noqa: E402

MODELS = os.path.join(ROOT, "assets", "models")


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


# ------------------------------------------------------------------------------------------------
# scene layout (Blender units = metres, +Z up, flagship nose -> +Y)
# ------------------------------------------------------------------------------------------------
FLAG_ROT = (-8.0, 8.0, -10.0)         # flagship root rotation (deg, XYZ euler): nose slightly down, banked

SHIELD = {  # game colours (ui_theme.gd DESTROYER_COLORS) -> linear
    "blue": srgb2lin((0.25, 0.55, 1.0)),
    "green": srgb2lin((0.25, 1.0, 0.45)),
    "red": srgb2lin((1.0, 0.22, 0.18)),
}
DESTROYERS = [  # colour, normalised screen position in the HERO camera (x right, y down), distance (m), rotation (deg XYZ)
    ("red", (0.655, 0.11), 600.0, (4.0, 14.0, 26.0)),
    ("blue", (0.44, 0.17), 340.0, (-10.0, 18.0, -22.0)),
    ("green", (0.835, 0.16), 430.0, (12.0, -16.0, -4.0)),
]
SHIELD_AXES = (11.5, 16.0, 8.0)       # bubble semi-axes x (side), y (front), z (up)

GREEBLES = 1500         # extra scene-only hull detail boxes on the flagship

FIGHTERS = [  # hero screen position, distance (m), heading (world direction the nose points to), bank (deg)
    ((0.805, 0.27), 260.0, (0.85, 0.35, -0.10), 25.0),
    ((0.822, 0.33), 255.0, (0.85, 0.35, -0.10), 30.0),
]

SUN_SCREEN = (1.30, -0.30)    # sun position in hero-camera screen space (off-frame, upper right, behind the ship)
SUN_DIR = Vector((-0.40, -0.80, 0.50)).normalized()     # direction towards the sun (recomputed from SUN_SCREEN)
KICK_DIR = Vector((0.70, -0.40, -0.55)).normalized()    # cool kicker (from the lower left, behind)
SHINE_DIR = Vector((-0.25, 0.10, -0.96)).normalized()   # faint teal "planet shine" from straight below

WP_EMIT = (12.0, 3.2, 2.6)    # weak point emission: hot-core boost, base, inner ring boost
LIGHTS = dict(sun=14.0, kicker=3.2, shine=0.9, fill=0.12, wp=3500.0, ion=9000.0, shield=1200.0, world=0.35)

ION_DIST = 14.0         # ion ball distance in front of the weak point (m, along its flight path)
ION_LAUNCH_CAM = (95.0, -70.0, -30.0)  # launch point in hero-camera space (right, up, back) metres
ION_SCALE = 1.0         # size of ball / halos / trail
ION_TRAIL_LEN = 45.0

CAMERAS = {
    # orbit: camera position around the weak point (azimuth deg, >0 = viewer's right / ship's -X side;
    # elevation deg, <0 = below; distance m). aim: world point ("WP" = weak point centre) that is placed
    # at normalised screen position `screen` (x right, y down). lens: mm on a 36 mm sensor (larger side).
    "hero": dict(preview=(1920, 620), final=(3840, 1240),
                 orbit=(14.0, -22.0, 160.0), aim="WP", screen=(0.62, 0.48), lens=50.0, roll=0.0),
    "wide": dict(preview=(920, 430), final=(1840, 860),
                 orbit=(14.0, -22.0, 160.0), aim="WP", screen=(0.675, 0.52), lens=62.0, roll=0.0),
    "portrait": dict(preview=(600, 900), final=(1200, 1800),
                     orbit=(16.0, -16.0, 140.0), aim="WP", screen=(0.48, 0.40), lens=60.0, roll=0.0),
}


# ------------------------------------------------------------------------------------------------
# small node helpers
# ------------------------------------------------------------------------------------------------
def new_mat(name):
    m = bpy.data.materials.new(name)
    if not m.node_tree:
        m.use_nodes = True
    m.node_tree.nodes.clear()
    return m, m.node_tree


def math_node(nt, op, a=None, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def principled(mat):
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def emission_add_transparent(nt, color_socket_or_value, strength_socket, backface_transparent=True):
    """Additive emission on a fully transparent surface; returns the shader output socket."""
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    if isinstance(color_socket_or_value, tuple):
        em.inputs["Color"].default_value = (*color_socket_or_value[:3], 1.0)
    else:
        nt.links.new(color_socket_or_value, em.inputs["Color"])
    nt.links.new(strength_socket, em.inputs["Strength"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(tr.outputs[0], add.inputs[0])
    nt.links.new(em.outputs[0], add.inputs[1])
    sh = add.outputs[0]
    if backface_transparent:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mix = nt.nodes.new("ShaderNodeMixShader")
        tr2 = nt.nodes.new("ShaderNodeBsdfTransparent")
        nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
        nt.links.new(sh, mix.inputs[1])
        nt.links.new(tr2.outputs[0], mix.inputs[2])
        sh = mix.outputs[0]
    nt.links.new(sh, out.inputs["Surface"])
    return out


def facing_center(nt, power):
    """|N.V| ** power  (1 in the middle of a sphere/tube, 0 at the silhouette)."""
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = math_node(nt, "SUBTRACT", 1.0, lw.outputs["Facing"], clamp=True)
    return math_node(nt, "POWER", inv, power)


def facing_edge(nt, power):
    """(1 - |N.V|) ** power  (fresnel-like rim)."""
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    return math_node(nt, "POWER", lw.outputs["Facing"], power)


def set_ray_vis(ob, camera=True, diffuse=True, glossy=True, transmission=True, shadow=True, volume=False):
    ob.visible_camera = camera
    ob.visible_diffuse = diffuse
    ob.visible_glossy = glossy
    ob.visible_transmission = transmission
    ob.visible_shadow = shadow
    ob.visible_volume_scatter = volume


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_obj(name, bm, mat=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    if smooth:
        try:
            me.shade_smooth()
        except Exception:
            for p in me.polygons:
                p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    link(ob)
    if mat is not None:
        me.materials.append(mat)
    return ob


def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    return [o for o in bpy.data.objects if o not in before]


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
def add_hull_variation(mat, scale=0.045, amount=0.22, rough=(0.30, 0.52), fine=0.55):
    """Large-scale tone/roughness variation + fine grime so big hull plates do not look CG-flat."""
    nt = mat.node_tree
    bsdf = principled(mat)
    base = tuple(bsdf.inputs["Base Color"].default_value)[:3]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = scale
    n1.inputs["Detail"].default_value = 4.0
    n1.inputs["Roughness"].default_value = 0.55
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = fine
    n2.inputs["Detail"].default_value = 8.0
    n2.inputs["Roughness"].default_value = 0.65
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.32
    ramp.color_ramp.elements[0].color = (*[c * (1 - amount) for c in base], 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (*[min(1.0, c * (1 + amount)) for c in base], 1)
    nt.links.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    # fine grime darkening
    g = math_node(nt, "MULTIPLY_ADD", n2.outputs["Fac"], 0.35)
    g.node.inputs[2].default_value = 0.80
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    nt.links.new(g, mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.3
    mr.inputs["From Max"].default_value = 0.7
    mr.inputs["To Min"].default_value = rough[0]
    mr.inputs["To Max"].default_value = rough[1]
    nt.links.new(n2.outputs["Fac"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], bsdf.inputs["Roughness"])


def add_panel_detail(mat, sizes=((7.0, 2.6), (2.2, 1.1)), mortar=(0.07, 0.05), darken=0.55, bump=0.6):
    """Triplanar procedural hull plating: two brick layers (big plates + sub panels) projected along the
    object axes and blended by the object-space normal; mortar lines darken the base colour and bump."""
    nt = mat.node_tree
    bsdf = principled(mat)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nsep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Normal"], nsep.inputs[0])
    X, Y, Z = sep.outputs["X"], sep.outputs["Y"], sep.outputs["Z"]
    planes = ((Y, Z, nsep.outputs["X"]), (X, Z, nsep.outputs["Y"]), (X, Y, nsep.outputs["Z"]))
    # weights |n|^4, normalised
    ws = [math_node(nt, "POWER", math_node(nt, "ABSOLUTE", n), 4.0) for (_, _, n) in planes]
    wsum = math_node(nt, "ADD", math_node(nt, "ADD", ws[0], ws[1]), ws[2])
    total = None
    for li, ((bw, rh), msize) in enumerate(zip(sizes, mortar)):
        layer = None
        for pi, (u, v, _) in enumerate(planes):
            cmb = nt.nodes.new("ShaderNodeCombineXYZ")
            nt.links.new(u, cmb.inputs[0])
            nt.links.new(v, cmb.inputs[1])
            cmb.inputs[2].default_value = 17.3 * li + 5.1 * pi
            br = nt.nodes.new("ShaderNodeTexBrick")
            br.offset = 0.5 if li == 0 else 0.35
            br.inputs["Scale"].default_value = 1.0
            br.inputs["Brick Width"].default_value = bw
            br.inputs["Row Height"].default_value = rh
            br.inputs["Mortar Size"].default_value = msize
            br.inputs["Mortar Smooth"].default_value = 0.2
            nt.links.new(cmb.outputs[0], br.inputs["Vector"])
            term = math_node(nt, "MULTIPLY", br.outputs["Fac"], ws[pi])
            layer = term if layer is None else math_node(nt, "ADD", layer, term)
        layer = math_node(nt, "DIVIDE", layer, wsum)
        total = layer if total is None else math_node(nt, "MAXIMUM", total, math_node(nt, "MULTIPLY", layer, 0.7))
    # darken base colour along the seams
    base_link = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].is_linked else None
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    nt.links.new(math_node(nt, "MULTIPLY", total, darken), mix.inputs["Factor"])
    if base_link is not None:
        nt.links.new(base_link, mix.inputs[6])
    else:
        mix.inputs[6].default_value = bsdf.inputs["Base Color"].default_value
    mix.inputs[7].default_value = (0.05, 0.05, 0.06, 1.0)
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    bp.inputs["Distance"].default_value = 0.05
    bp.invert = True
    nt.links.new(total, bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])


def add_hull_lights(mat, row=2.4, band=0.22, dash=1.3, duty=0.45, color=(1.0, 0.80, 0.55), strength=5.0,
                    cluster=0.05, coverage=(0.52, 0.62)):
    """Rows of tiny lit windows on the vertical-ish hull faces (object space z bands, dashed along x+y),
    switched on in irregular clusters by low-frequency noise -> sense of scale."""
    nt = mat.node_tree
    bsdf = principled(mat)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nsep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Normal"], nsep.inputs[0])
    # horizontal bands
    fz = math_node(nt, "FRACT", math_node(nt, "DIVIDE", sep.outputs["Z"], row))
    bandm = math_node(nt, "LESS_THAN", fz, band / row)
    # dashes along the hull
    along = math_node(nt, "ADD", sep.outputs["X"], math_node(nt, "MULTIPLY", sep.outputs["Y"], 0.83))
    fd = math_node(nt, "FRACT", math_node(nt, "DIVIDE", along, dash))
    dashm = math_node(nt, "LESS_THAN", fd, duty)
    # only on vertical-ish faces
    vert = math_node(nt, "LESS_THAN", math_node(nt, "ABSOLUTE", nsep.outputs["Z"]), 0.45)
    # clusters + per-row random brightness
    cl = nt.nodes.new("ShaderNodeTexNoise")
    cl.inputs["Scale"].default_value = cluster
    cl.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], cl.inputs["Vector"])
    clm = nt.nodes.new("ShaderNodeMapRange")
    clm.inputs["From Min"].default_value = coverage[0]
    clm.inputs["From Max"].default_value = coverage[1]
    nt.links.new(cl.outputs["Fac"], clm.inputs["Value"])
    wn = nt.nodes.new("ShaderNodeTexWhiteNoise")
    wn.noise_dimensions = "3D"
    cmb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(math_node(nt, "FLOOR", math_node(nt, "DIVIDE", along, dash)), cmb.inputs[0])
    nt.links.new(math_node(nt, "FLOOR", math_node(nt, "DIVIDE", sep.outputs["Z"], row)), cmb.inputs[1])
    nt.links.new(cmb.outputs[0], wn.inputs["Vector"])
    lit = math_node(nt, "GREATER_THAN", wn.outputs["Value"], 0.35)
    e = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", bandm, dashm), math_node(nt, "MULTIPLY", vert, lit))
    e = math_node(nt, "MULTIPLY", e, clm.outputs["Result"])
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    nt.links.new(math_node(nt, "MULTIPLY", e, strength), bsdf.inputs["Emission Strength"])


def weakpoint_material():
    """Vivid pink square with a white-hot core, an inner ring and faint retro scanlines."""
    m, nt = new_mat("WP_Render")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ax = math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", sep.outputs["X"], 0.5))
    az = math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", sep.outputs["Z"], 0.5))
    d = math_node(nt, "MULTIPLY", math_node(nt, "MAXIMUM", ax, az), 2.0)   # 0 centre .. 1 edge (square)
    r = math_node(nt, "MULTIPLY", math_node(nt, "SQRT", math_node(nt, "ADD", math_node(nt, "MULTIPLY", ax, ax),
                                                                     math_node(nt, "MULTIPLY", az, az))), 2.0)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    el = ramp.color_ramp.elements
    el[0].position = 0.0
    el[0].color = (1.0, 0.90, 0.97, 1)
    el[1].position = 1.0
    el[1].color = (1.0, 0.10, 0.60, 1)
    for pos, col in ((0.28, (1.0, 0.52, 0.86)), (0.62, (1.0, 0.22, 0.70))):
        e = el.new(pos)
        e.color = (*col, 1)
    nt.links.new(math_node(nt, "MINIMUM", r, 1.0), ramp.inputs["Fac"])
    ring = math_node(nt, "SUBTRACT", 1.0, math_node(nt, "MULTIPLY", math_node(
        nt, "ABSOLUTE", math_node(nt, "SUBTRACT", d, 0.72)), 26.0), clamp=True)
    core = math_node(nt, "POWER", math_node(nt, "SUBTRACT", 1.0, math_node(nt, "MINIMUM", r, 1.0)), 2.0)
    scan = math_node(nt, "MULTIPLY_ADD", math_node(nt, "SINE", math_node(nt, "MULTIPLY", sep.outputs["Z"], 2 * math.pi * 15.0)), 0.10)
    scan.node.inputs[2].default_value = 0.90
    strength = math_node(nt, "ADD", math_node(nt, "MULTIPLY", core, WP_EMIT[0]),
                         math_node(nt, "ADD", WP_EMIT[1], math_node(nt, "MULTIPLY", ring, WP_EMIT[2])))
    strength = math_node(nt, "MULTIPLY", strength, scan)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(strength, em.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def shield_material(name, color, strength=1.0):
    """Shield bubble like shaders/shield.gdshader: fresnel rim + hexagon lines, additive."""
    m, nt = new_mat(name)
    fres = facing_edge(nt, 2.6)
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "hexd"
    hexm = nt.nodes.new("ShaderNodeMapRange")
    hexm.interpolation_type = "SMOOTHSTEP"
    hexm.inputs["From Min"].default_value = 0.90
    hexm.inputs["From Max"].default_value = 0.98
    nt.links.new(attr.outputs["Fac"], hexm.inputs["Value"])
    hx = hexm.outputs["Result"]
    fres2 = math_node(nt, "POWER", fres, 0.6)           # wider falloff for the hex lines
    a = math_node(nt, "ADD", fres, math_node(nt, "MULTIPLY", hx, math_node(nt, "ADD", math_node(nt, "MULTIPLY", fres2, 0.55), 0.025)))
    a = math_node(nt, "ADD", a, 0.006)
    s = math_node(nt, "MULTIPLY", a, 1.8 * strength)
    emission_add_transparent(nt, tuple(color), s, backface_transparent=True)
    try:
        m.emission_sampling = "NONE"
    except Exception:
        pass
    return m


def glow_material(name, color, strength, center_power=None, edge_power=None, t_fade=None, t_color=None):
    """Additive transparent glow. center_power: |N.V|^p falloff; t_fade: (power) fade along UV.x."""
    m, nt = new_mat(name)
    s = None
    if center_power is not None:
        s = facing_center(nt, center_power)
    if edge_power is not None:
        e = facing_edge(nt, edge_power)
        s = e if s is None else math_node(nt, "MULTIPLY", s, e)
    col = tuple(color)
    t = None
    if t_fade is not None or t_color is not None:
        uv = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(uv.outputs["UV"], sep.inputs[0])
        t = sep.outputs["X"]
    if t_fade is not None:
        f = math_node(nt, "POWER", math_node(nt, "SUBTRACT", 1.0, t, clamp=True), t_fade)
        s = f if s is None else math_node(nt, "MULTIPLY", s, f)
    if s is None:
        s = math_node(nt, "ADD", 0.0, 1.0)
    s = math_node(nt, "MULTIPLY", s, strength)
    if t_color is not None:
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        el = ramp.color_ramp.elements
        el[0].position = t_color[0][0]
        el[0].color = (*t_color[0][1], 1)
        el[1].position = t_color[-1][0]
        el[1].color = (*t_color[-1][1], 1)
        for p, c in t_color[1:-1]:
            e = el.new(p)
            e.color = (*c, 1)
        nt.links.new(t, ramp.inputs["Fac"])
        col = ramp.outputs["Color"]
    emission_add_transparent(nt, col, s, backface_transparent=False)
    try:
        m.emission_sampling = "NONE"
    except Exception:
        pass
    return m


def emit_material(name, color, strength):
    m, nt = new_mat(name)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


# ------------------------------------------------------------------------------------------------
# procedural geometry
# ------------------------------------------------------------------------------------------------
def bm_hex_bubble(subdiv=3):
    """Unit sphere made of hexagons (dual of an icosphere), every cell fan-triangulated from its centre.
    Vertex attribute 'hexd' = 0 at cell centres, 1 on cell borders -> crisp hex lines in the shader."""
    ico = bmesh.new()
    bmesh.ops.create_icosphere(ico, subdivisions=subdiv, radius=1.0)
    ico.verts.ensure_lookup_table()
    ico.faces.ensure_lookup_table()
    out = bmesh.new()
    lay = out.verts.layers.float.new("hexd")
    fverts = []
    for f in ico.faces:
        v = out.verts.new(f.calc_center_median().normalized())
        v[lay] = 1.0
        fverts.append(v)
    for v in ico.verts:
        n = v.co.normalized()
        t1 = n.orthogonal().normalized()
        t2 = n.cross(t1)
        lf = sorted(v.link_faces, key=lambda f: math.atan2((f.calc_center_median() - v.co).dot(t2),
                                                           (f.calc_center_median() - v.co).dot(t1)))
        c = out.verts.new(n)
        c[lay] = 0.0
        ring = [fverts[f.index] for f in lf]
        for i in range(len(ring)):
            out.faces.new((c, ring[i], ring[(i + 1) % len(ring)]))
    bmesh.ops.recalc_face_normals(out, faces=out.faces)
    ico.free()
    return out


def frames_along(points):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline."""
    pts = [Vector(p) for p in points]
    tans = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tans.append((b - a).normalized())
    n = tans[0].orthogonal().normalized()
    frames = []
    for i, t in enumerate(tans):
        if i > 0:
            n = (n - t * n.dot(t)).normalized()
        frames.append((t, n, t.cross(n)))
    return pts, frames


def bm_tube(points, radii, sides=16, uv=True):
    pts, frames = frames_along(points)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap") if uv else None
    rings = []
    L = len(pts)
    for i, (p, (t, n, b)) in enumerate(zip(pts, frames)):
        r = radii[i]
        rings.append([bm.verts.new(p + (n * math.cos(2 * math.pi * k / sides) + b * math.sin(2 * math.pi * k / sides)) * r)
                      for k in range(sides)])
    for i in range(L - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            if uvl is not None:
                u0, u1 = i / (L - 1), (i + 1) / (L - 1)
                v0, v1 = k / sides, (k + 1) / sides
                for loop, uvv in zip(f.loops, ((u0, v0), (u0, v1), (u1, v1), (u1, v0))):
                    loop[uvl].uv = uvv
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_uv_sphere(radius, segs=48, rings=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    return bm


# ------------------------------------------------------------------------------------------------
# scene
# ------------------------------------------------------------------------------------------------
class Scene:
    pass


def build_scene():
    B.reset()
    S = Scene()
    scn = bpy.context.scene

    # ---------------- flagship ----------------------------------------------------------------
    objs = import_glb("flagship")
    flag = next(o for o in objs if o.name.startswith("Flagship"))
    wp = next(o for o in objs if o.name.startswith("WeakPoint"))
    for o in objs:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    root = bpy.data.objects.new("FlagRoot", None)
    link(root)
    for o in (flag, wp):
        o.parent = root
    root.rotation_euler = [math.radians(a) for a in FLAG_ROT]
    hull = flag.data.materials["Hull"]
    principled(hull).inputs["Base Color"].default_value = (0.135, 0.14, 0.155, 1.0)
    add_hull_variation(hull, scale=0.045, amount=0.25, rough=(0.30, 0.50))
    add_panel_detail(hull, sizes=((5.0, 3.2), (1.7, 1.2)), mortar=(0.035, 0.025), darken=0.28, bump=0.25)
    add_hull_lights(hull)
    add_hull_variation(flag.data.materials["HullDark"], scale=0.06, amount=0.3, rough=(0.35, 0.6))
    acc = principled(flag.data.materials["Accent"])
    acc.inputs["Emission Strength"].default_value = 6.0
    wp.data.materials[0] = weakpoint_material()
    S.flag, S.wp, S.root = flag, wp, root

    # ---------------- destroyers --------------------------------------------------------------
    dobjs = import_glb("destroyer")
    dsrc = next(o for o in dobjs if o.name.startswith("Destroyer"))
    for o in dobjs:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    for m in dsrc.data.materials:
        if m.name.startswith("Hull") and not m.name.startswith("HullDark"):
            add_hull_variation(m, scale=0.12, amount=0.22, rough=(0.28, 0.48), fine=1.4)
    S.destroyers = []
    for i, (cname, loc, dist, rot) in enumerate(DESTROYERS):
        col = SHIELD[cname]
        d = dsrc.copy()
        d.data = dsrc.data.copy()
        d.name = "Destroyer_" + cname
        link(d)
        for si, m in enumerate(d.data.materials):
            if m.name.startswith("AccentPaint"):
                mm = m.copy()
                b = principled(mm)
                b.inputs["Base Color"].default_value = (*[0.18 + 0.55 * c for c in col], 1)
                d.data.materials[si] = mm
            elif m.name.startswith("Accent"):
                mm = m.copy()
                b = principled(mm)
                b.inputs["Base Color"].default_value = (*col, 1)
                b.inputs["Emission Color"].default_value = (*col, 1)
                b.inputs["Emission Strength"].default_value = 5.0
                d.data.materials[si] = mm
        d.location = (0.0, 0.0, 0.0)
        d["screen"], d["dist"] = loc, dist
        d.rotation_euler = [math.radians(a) for a in rot]
        # shield bubble
        bm = bm_hex_bubble(3)
        for v in bm.verts:
            v.co = Vector((v.co.x * SHIELD_AXES[0], v.co.y * SHIELD_AXES[1], v.co.z * SHIELD_AXES[2]))
        sh = mesh_obj("Shield_" + cname, bm, shield_material("ShieldMat_" + cname, col, 1.0))
        sh.parent = d
        set_ray_vis(sh, diffuse=False, shadow=False, transmission=False)
        # coloured light from the shield onto its own hull (bubble emission itself is not sampled)
        ld = bpy.data.lights.new("ShieldLight_" + cname, "POINT")
        ld.energy = LIGHTS["shield"]
        ld.color = col
        ld.shadow_soft_size = 4.0
        lo = bpy.data.objects.new("ShieldLight_" + cname, ld)
        link(lo)
        lo.parent = d
        lo.location = (0.0, 4.0, 9.0)
        S.destroyers.append(d)
    bpy.data.objects.remove(dsrc)

    # ---------------- fighters (scale reference, amber engine glows) ---------------------------------
    fobjs = import_glb("fighter")
    S.fsrc = next(o for o in fobjs if o.name.startswith("Fighter"))
    for o in fobjs:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    S.fsrc.hide_render = True
    for m in S.fsrc.data.materials:
        if m.name.startswith("Accent"):
            principled(m).inputs["Emission Strength"].default_value = 2.5

    bpy.context.view_layer.update()
    S.wp_pos = wp.matrix_world.translation.copy()
    S.wp_n = (root.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()

    # ---------------- cameras + ion ball / trail -------------------------------------------------
    S.cams = {}
    for name, c in CAMERAS.items():
        S.cams[name] = make_camera(name, c, S)
    bpy.context.view_layer.update()
    for d in S.destroyers:
        d.location = hero_point(S, d["screen"], d["dist"])
    build_fighters(S)
    bpy.context.view_layer.update()
    global SUN_DIR
    SUN_DIR = hero_point(S, SUN_SCREEN, 1.0) - S.cams["hero"].location
    SUN_DIR.normalize()
    NEB_DIRS[:] = [tuple((hero_point(S, nb[0], 1.0) - S.cams["hero"].location).normalized()) for nb in NEBULAE]
    add_greebles(S, GREEBLES)
    build_ion(S)

    # ---------------- lights ------------------------------------------------------------------
    def sun(name, direction, energy, color, angle=0.6):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = color
        ld.angle = math.radians(angle)
        lo = bpy.data.objects.new(name, ld)
        link(lo)
        lo.rotation_mode = "QUATERNION"
        lo.rotation_quaternion = (-direction).to_track_quat("-Z", "Y")
        return lo

    sun("Sun", SUN_DIR, LIGHTS["sun"], (1.0, 0.86, 0.66))
    sun("Kicker", KICK_DIR, LIGHTS["kicker"], srgb2lin((0.40, 0.85, 1.0)))
    sun("Shine", SHINE_DIR, LIGHTS["shine"], srgb2lin((0.35, 0.75, 0.85)), angle=30.0)
    cam_dir = (S.cams["hero"].location - S.wp_pos).normalized()   # soft fill from the viewer
    sun("Fill", cam_dir, LIGHTS["fill"], srgb2lin((0.55, 0.55, 0.85)), angle=20.0)
    # weak point spill
    ld = bpy.data.lights.new("WPLight", "AREA")
    ld.shape = "SQUARE"
    ld.size = 7.0
    ld.energy = LIGHTS["wp"]
    ld.color = (1.0, 0.35, 0.80)
    lo = bpy.data.objects.new("WPLight", ld)
    link(lo)
    lo.location = S.wp_pos + S.wp_n * 1.2
    lo.rotation_mode = "QUATERNION"
    lo.rotation_quaternion = (-S.wp_n).to_track_quat("Z", "Y")   # area light shines along local -Z -> +wp_n

    # ---------------- world (lighting / reflections only; camera sees the composited sky) -------
    world = bpy.data.worlds.new("World")
    if not world.node_tree:
        world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    env = sky_equirect(512, 256)
    img = numpy_to_image("SkyEnv", env)
    tex = nt.nodes.new("ShaderNodeTexEnvironment")
    tex.image = img
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = LIGHTS["world"]
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tex.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    scn.world = world

    bpy.context.view_layer.update()
    return S


def aim_quat(loc, target, screen, lens, res, roll):
    """Camera rotation that puts `target` at normalised screen position `screen` (x right, y down)."""
    w, h = res
    hw = 18.0 / lens if w >= h else 18.0 / lens * w / h      # tan(half fov) on the frame plane z=-1
    hh = hw * h / w
    v_d = Vector(((screen[0] - 0.5) * 2 * hw, (0.5 - screen[1]) * 2 * hh, -1.0)).normalized()
    t_w = (Vector(target) - Vector(loc)).normalized()
    q0 = t_w.to_track_quat("-Z", "Y")
    q_off = v_d.rotation_difference(Vector((0.0, 0.0, -1.0)))
    q_roll = Quaternion(t_w, math.radians(roll))
    return q_roll @ q0 @ q_off


def hero_point(S, screen, dist):
    """World point at `dist` metres along the hero camera ray through normalised screen position."""
    c = CAMERAS["hero"]
    w, h = c["preview"]
    hw = 18.0 / c["lens"]
    hh = hw * h / w
    v = Vector(((screen[0] - 0.5) * 2 * hw, (0.5 - screen[1]) * 2 * hh, -1.0)).normalized()
    cam = S.cams["hero"]
    return cam.location + cam.rotation_quaternion @ v * dist


def make_camera(name, c, S):
    cd = bpy.data.cameras.new("Cam_" + name)
    cd.lens = c["lens"]
    cd.sensor_width = 36.0
    cd.sensor_fit = "AUTO"
    cd.clip_start = 0.5
    cd.clip_end = 20000.0
    co = bpy.data.objects.new("Cam_" + name, cd)
    link(co)
    target = S.wp_pos if c["aim"] == "WP" else Vector(c["aim"])
    if "orbit" in c:
        az, el, R = (math.radians(c["orbit"][0]), math.radians(c["orbit"][1]), c["orbit"][2])
        loc = S.wp_pos + Vector((-math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el))) * R
    else:
        loc = Vector(c["loc"])
    co.location = loc
    co.rotation_mode = "QUATERNION"
    co.rotation_quaternion = aim_quat(loc, target, c["screen"], c["lens"], c["preview"], c["roll"])
    return co


def add_greebles(S, n, seed=11):
    """Scatter extra hull detail (boxes / pipes) over the camera-facing hull of the flagship (scene only,
    the asset is untouched). Kept away from the weak point so the focal area stays clean."""
    flag = S.flag
    me = flag.data
    names = [m.name for m in me.materials]
    polys = []
    for p in me.polygons:
        mname = names[p.material_index] if p.material_index < len(names) else ""
        if not mname.startswith("Hull"):
            continue
        c = p.center
        if p.normal.z > 0.55:                       # top surfaces are hardly visible from below
            continue
        if (S.root.matrix_world.to_3x3() @ p.normal).dot(SUN_DIR) > 0.2:   # avoid a sparkle carpet in the sun
            continue
        if (c - Vector((0.0, 46.45, 0.0))).length < 13.0:
            continue
        polys.append(p)
    rng = np.random.default_rng(seed)
    areas = np.array([p.area for p in polys])
    idx = rng.choice(len(polys), size=n, p=areas / areas.sum())
    bm_a = bmesh.new()
    bm_b = bmesh.new()
    for i in idx:
        p = polys[i]
        vs = [me.vertices[v].co for v in p.vertices]
        # random point in the polygon (fan triangle, barycentric)
        t = rng.integers(1, len(vs) - 1)
        a, b2, c2 = vs[0], vs[t], vs[t + 1]
        r1, r2 = rng.random(), rng.random()
        if r1 + r2 > 1:
            r1, r2 = 1 - r1, 1 - r2
        pt = a + (b2 - a) * r1 + (c2 - a) * r2
        nrm = p.normal.copy()
        # tangent aligned with the ship's long axis where possible
        tng = (Vector((0, 1, 0)) - nrm * nrm.y)
        if tng.length < 1e-3:
            tng = Vector((1, 0, 0)) - nrm * nrm.x
        tng.normalize()
        bit = nrm.cross(tng)
        sx = rng.uniform(0.35, 1.7) * (1.0 + 0.8 * (rng.random() < 0.12))
        sy = rng.uniform(0.5, 2.8) * (1.0 + 0.8 * (rng.random() < 0.12))
        sz = rng.uniform(0.10, 0.55)
        rot = Matrix((bit, tng, nrm)).transposed()
        g = B.bm_box((0, 0, sz * 0.5 - 0.05), (sx, sy, sz))
        bmesh.ops.rotate(g, cent=Vector((0, 0, 0)), matrix=rot, verts=g.verts)
        bmesh.ops.translate(g, vec=pt, verts=g.verts)
        B.merge_bm(bm_a if rng.random() < 0.8 else bm_b, g)
    for bm, mat in ((bm_a, me.materials["Hull"]), (bm_b, me.materials["HullDark"])):
        o = mesh_obj("FlagGreebles", bm, mat, smooth=False)
        o.parent = S.root


def build_fighters(S):
    plume = glow_material("PlumeMat", (1.0, 0.5, 0.15), 7.0, center_power=1.2, t_fade=1.6,
                          t_color=[(0.0, (1.0, 0.85, 0.6)), (0.3, (1.0, 0.45, 0.12)), (1.0, (0.9, 0.15, 0.05))])
    for i, (scr, dist, heading, bank) in enumerate(FIGHTERS):
        f = S.fsrc.copy()
        f.name = "FighterR%d" % i
        f.hide_render = False
        link(f)
        f.location = hero_point(S, scr, dist)
        hd = Vector(heading).normalized()
        q = hd.to_track_quat("Y", "Z")                    # model nose = +Y
        q = q @ Quaternion((0, 1, 0), math.radians(bank))
        f.rotation_mode = "QUATERNION"
        f.rotation_quaternion = q
        for sx in (-0.95, 0.95):
            a = Vector((sx, -3.70, -0.04))
            pts = [a + Vector((0, -6.0 * (j / 11), 0)) for j in range(12)]
            o = mesh_obj("Plume%d" % i, bm_tube(pts, [0.42 * (1 - j / 11) ** 0.8 + 0.04 for j in range(12)], 12), plume)
            o.parent = f
            set_ray_vis(o, diffuse=False, shadow=False, transmission=False)


def build_ion(S):
    """Violet-white ion ball close in front of the weak point, glowing trail back to the launch point."""
    cam = S.cams["hero"]
    cloc = cam.location.copy()
    cq = cam.rotation_quaternion.copy()
    right = cq @ Vector((1, 0, 0))
    up = cq @ Vector((0, 1, 0))
    back = cq @ Vector((0, 0, 1))
    launch = cloc + right * ION_LAUNCH_CAM[0] + up * ION_LAUNCH_CAM[1] + back * ION_LAUNCH_CAM[2]
    W = S.wp_pos
    ball = W + (launch - W).normalized() * ION_DIST
    axis = (launch - ball).normalized()        # trail direction (from the ball back towards the launch)
    S.ion_pos, S.ion_axis = ball, axis
    k = ION_SCALE
    violet = (0.62, 0.42, 1.0)

    core = mesh_obj("IonCore", bm_uv_sphere(1.1 * k, 32, 16), emit_material("IonCoreMat", (1.0, 0.95, 1.0), 15.0))
    core.location = ball
    set_ray_vis(core, diffuse=False, shadow=False)
    for name, r, col, st, p in (("IonHalo1", 2.2, (0.86, 0.74, 1.0), 3.2, 2.0),
                                ("IonHalo2", 4.2, violet, 1.0, 3.0),
                                ("IonHalo3", 8.0, (0.42, 0.30, 1.0), 0.22, 3.5)):
        h = mesh_obj(name, bm_uv_sphere(r * k, 48, 24), glow_material(name + "Mat", col, st, center_power=p))
        h.location = ball
        set_ray_vis(h, diffuse=False, shadow=False, transmission=False)

    # trail: bright inner core + wide soft outer sheath
    L = ION_TRAIL_LEN
    n = 90
    pts = [ball + axis * (L * (i / (n - 1)) ** 1.15) for i in range(n)]
    tt = [i / (n - 1) for i in range(n)]
    tcol = [(0.0, (1.0, 0.95, 1.0)), (0.12, (0.80, 0.64, 1.0)), (0.5, (0.48, 0.30, 1.0)), (1.0, (0.20, 0.16, 0.85))]
    inner = mesh_obj("TrailInner", bm_tube(pts, [(0.08 + 0.80 * (1 - t) ** 1.5) * k for t in tt], 20),
                     glow_material("TrailInnerMat", (1, 1, 1), 5.0, center_power=1.6, t_fade=2.2, t_color=tcol))
    outer = mesh_obj("TrailOuter", bm_tube(pts, [(0.30 + 2.3 * (1 - t) ** 1.3) * k for t in tt], 24),
                     glow_material("TrailOuterMat", (1, 1, 1), 0.8, center_power=2.5, t_fade=1.6, t_color=tcol))
    for o in (inner, outer):
        set_ray_vis(o, diffuse=False, shadow=False, transmission=False)

    # two helix ribbons spiralling around the trail
    _, frames = frames_along(pts)
    rng = np.random.default_rng(7)
    for h in range(2):
        hp = []
        hr = []
        ph = h * math.pi
        for i, (p, (t_, nn, bb)) in enumerate(zip(pts, frames)):
            t = tt[i]
            ang = ph + t * 2 * math.pi * 2.2
            rad = (0.7 + 1.6 * t) * k
            hp.append(p + (nn * math.cos(ang) + bb * math.sin(ang)) * rad)
            hr.append((0.035 + 0.03 * (1 - t)) * k)
        o = mesh_obj("Helix%d" % h, bm_tube(hp, hr, 8),
                     glow_material("HelixMat%d" % h, (1, 1, 1), 4.0, center_power=0.6, t_fade=3.0, t_color=tcol))
        set_ray_vis(o, diffuse=False, shadow=False, transmission=False)

    # sparks around the trail
    sbm = bmesh.new()
    for _ in range(45):
        t = rng.random() ** 1.6
        p = ball + axis * (L * 0.6 * t)
        off = Vector(rng.normal(size=3))
        off = (off - axis * off.dot(axis)).normalized() * (0.6 + 2.8 * t) * k * rng.uniform(0.4, 1.2)
        r = rng.uniform(0.04, 0.11) * (1.2 - 0.6 * t) * k
        sb = bm_uv_sphere(r, 8, 4)
        bmesh.ops.translate(sb, vec=p + off, verts=sb.verts)
        B.merge_bm(sbm, sb)
    sp = mesh_obj("Sparks", sbm, emit_material("SparkMat", (0.85, 0.75, 1.0), 30.0))
    set_ray_vis(sp, diffuse=False, shadow=False)

    # plasma tendrils crawling over the ball
    for j0 in range(7):
        d = Vector(rng.normal(size=3)).normalized()
        pts_t = []
        rad_t = []
        p = d * 0.9 * k
        v = Vector(rng.normal(size=3)).normalized()
        m = 14
        for j in range(m):
            pts_t.append(ball + p)
            rad_t.append((0.05 * (1 - j / m) + 0.012) * k)
            v = (v + Vector(rng.normal(size=3)) * 0.7).normalized()
            p = p + v * 0.26 * k
            p = p.normalized() * min(0.95 + 0.16 * j, 2.5) * k
        o = mesh_obj("Tendril%d" % j0, bm_tube(pts_t, rad_t, 6),
                     glow_material("TendrilMat%d" % j0, (0.9, 0.8, 1.0), 22.0, t_fade=1.2))
        set_ray_vis(o, diffuse=False, shadow=False, transmission=False)

    # light from the ball onto the flagship face
    ld = bpy.data.lights.new("IonLight", "POINT")
    ld.energy = LIGHTS["ion"]
    ld.color = (0.78, 0.66, 1.0)
    ld.shadow_soft_size = 1.5
    lo = bpy.data.objects.new("IonLight", ld)
    link(lo)
    lo.location = ball


# ------------------------------------------------------------------------------------------------
# background: nebula + stars from 3D directions (numpy)
# ------------------------------------------------------------------------------------------------
NEBULAE = [  # hero-camera screen position (direction), radius deg, inner colour, outer colour, strength
    ((0.84, 0.18), 19.0, (0.95, 0.16, 0.80), (0.30, 0.05, 0.62), 1.15),    # magenta/violet glow behind the ship
    ((1.05, 0.90), 15.0, (0.06, 0.60, 0.75), (0.03, 0.16, 0.45), 0.8),     # teal, lower right
    ((0.30, 0.05), 13.0, (0.40, 0.14, 0.85), (0.12, 0.05, 0.38), 0.35),    # faint violet upper left
    ((0.50, 2.10), 16.0, (0.10, 0.45, 0.70), (0.20, 0.08, 0.50), 0.55),    # below the hero frame (portrait bottom)
]
NEB_DIRS = []
SKY_SEED = 1983
NEB_GAIN = 0.26


def nebula_rgb(d):
    """d: (..., 3) float32 unit directions (Blender world space). Returns linear RGB (..., 3)."""
    fr = [Fractal3(SKY_SEED + 11 * k) for k in range(8)]
    out = np.zeros(d.shape, np.float32)
    # faint large-scale dust everywhere so space is never a dead flat black
    g = fr[0].fbm(d, 1.6, 4) * 0.5 + 0.5
    out += (0.0006 + 0.0016 * g ** 2)[..., None] * np.array((0.30, 0.34, 0.75), np.float32)
    q = d + 0.30 * np.stack([fr[1].fbm(d, 2.0, 4), fr[2].fbm(d, 2.0, 4), fr[3].fbm(d, 2.0, 4)], -1)
    dens = smoothstep(0.30, 0.95, fr[4].fbm(q, 3.2, 7) * 0.5 + 0.5) ** 1.25
    fil = fr[5].ridged(q, 5.0, 6, sharp=4.0)
    dark = 1.0 - 0.7 * smoothstep(0.55, 0.85, fr[6].fbm(q, 7.0, 5) * 0.5 + 0.5)
    mixv = np.clip(fr[7].fbm(q, 2.5, 4) * 0.6 + 0.5, 0, 1)[..., None]
    for (c, (_, rad, cin, cout, st)) in zip(NEB_DIRS, NEBULAE):
        c = np.array(c, np.float32)
        c /= np.linalg.norm(c)
        ang = np.arccos(np.clip((d * c).sum(-1), -1, 1))
        edge = np.radians(rad) * (1.0 + 0.4 * fr[1].fbm(q * 1.3, 1.4, 3))
        mask = np.exp(-(ang / np.maximum(edge, 1e-3)) ** 2 * 1.2)
        col = np.array(cin, np.float32) * mixv + np.array(cout, np.float32) * (1 - mixv)
        inten = mask * (0.55 * dens + 0.9 * dens * fil) * dark + 0.16 * mask ** 2.5
        out += (NEB_GAIN * st * inten)[..., None] * col
    # sun haze
    sd = np.array(SUN_DIR, np.float32)
    sa = np.arccos(np.clip((d * sd).sum(-1), -1, 1))
    out += (0.6 * np.exp(-sa / 0.06) + 0.06 * np.exp(-sa / 0.25))[..., None] * np.array((1.0, 0.80, 0.55), np.float32)
    return out


def sky_equirect(w, h):
    lon = (np.arange(w) + 0.5) / w * 2 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(h) + 0.5) / h * np.pi
    lon, lat = np.meshgrid(lon, lat)
    # Blender environment mapping: u=0.5 looks along -Y ... direction = (-cos(lat)*sin(lon)?)
    # Equirect in Blender: dir = (cos(lat)*cos(phi), cos(lat)*sin(phi), sin(lat)) with phi = -(u-0.5)*2pi
    phi = -lon
    d = np.stack([np.cos(lat) * np.cos(phi), np.cos(lat) * np.sin(phi), np.sin(lat)], -1).astype(np.float32)
    rgb = nebula_rgb(d)
    rgba = np.concatenate([rgb, np.ones(rgb.shape[:2] + (1,), np.float32)], -1)
    return rgba


def numpy_to_image(name, rgba_top_down):
    h, w = rgba_top_down.shape[:2]
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba_top_down[::-1]).astype(np.float32).ravel())
    return img


def camera_frame(cam_obj):
    scn = bpy.context.scene
    fr = [Vector(v) for v in cam_obj.data.view_frame(scene=scn)]
    xs = [v.x for v in fr]
    ys = [v.y for v in fr]
    return min(xs), max(xs), min(ys), max(ys), fr[0].z


def camera_dirs(cam_obj, w, h):
    x0, x1, y0, y1, z = camera_frame(cam_obj)
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    X = (x0 + (x1 - x0) * u)[None, :].repeat(h, 0)
    Y = (y1 - (y1 - y0) * v)[:, None].repeat(w, 1)
    D = np.stack([X, Y, np.full_like(X, z)], -1)
    R = np.array(cam_obj.matrix_world.to_3x3())
    D = D @ R.T
    D /= np.linalg.norm(D, axis=-1, keepdims=True)
    return D.astype(np.float32)


STAR_FLUX = 0.030


def star_catalog(n=340000, seed=SKY_SEED):
    rng = np.random.default_rng(seed)
    v = rng.normal(size=(n, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    u = rng.random(n)
    flux = STAR_FLUX * u ** (-1.0 / 1.6)        # in "preview pixel" units (sum of pixel values)
    flux = np.minimum(flux, 9.0)
    tsel = rng.random(n)
    temp = np.where(tsel < 0.5, rng.uniform(5200, 7000, n),
                    np.where(tsel < 0.8, rng.uniform(7000, 15000, n),
                             np.where(tsel < 0.95, rng.uniform(3900, 5200, n), rng.uniform(3000, 3900, n))))
    t = temp / 100.0
    r = np.where(t <= 66, 255.0, 329.698727446 * np.power(np.maximum(t - 60, 1e-6), -0.1332047592))
    g = np.where(t <= 66, 99.4708025861 * np.log(t) - 161.1195681661,
                 288.1221695283 * np.power(np.maximum(t - 60, 1e-6), -0.0755148492))
    b = np.where(t >= 66, 255.0, 138.5177312231 * np.log(np.maximum(t - 10, 1e-6)) - 305.0447927307)
    col = (np.stack([r, g, b], -1).clip(0, 255) / 255.0) ** 2.2
    col = col / col.max(-1, keepdims=True)
    col = 0.55 * col + 0.45
    col /= col.max(-1, keepdims=True)
    return v.astype(np.float32), flux.astype(np.float32), col.astype(np.float32)


def splat_stars(img, cam_obj, k_res):
    """Pixel-integrated gaussian splats. k_res = render width / preview width (flux scaling)."""
    h, w = img.shape[:2]
    dirs, flux, col = star_catalog()
    x0, x1, y0, y1, z = camera_frame(cam_obj)
    R = np.array(cam_obj.matrix_world.to_3x3())
    loc = dirs @ R            # world -> camera (R orthonormal: R.T applied on the right)
    front = loc[:, 2] < -1e-6
    loc, flux, col = loc[front], flux[front], col[front]
    t = z / loc[:, 2]
    px = (loc[:, 0] * t - x0) / (x1 - x0) * w
    py = (y1 - loc[:, 1] * t) / (y1 - y0) * h
    pad = 12
    ok = (px > -pad) & (px < w + pad) & (py > -pad) & (py < h + pad)
    px, py, flux, col = px[ok], py[ok], flux[ok], col[ok]
    # star core: sigma ~0.45 px at final resolution (k=2) -> crisp, never aliased (erf integration)

    def splat(px, py, fl, cl, sigma, rad):
        if len(px) == 0:
            return
        cx = np.floor(px).astype(np.int64)
        cy = np.floor(py).astype(np.int64)
        offs = np.arange(-rad, rad + 1)
        xs = cx[:, None] + offs[None, :]
        ys = cy[:, None] + offs[None, :]
        s2 = sigma * math.sqrt(2.0)
        gx = 0.5 * (erf((xs + 1 - px[:, None]) / s2) - erf((xs - px[:, None]) / s2))
        gy = 0.5 * (erf((ys + 1 - py[:, None]) / s2) - erf((ys - py[:, None]) / s2))
        wgt = gy[:, :, None] * gx[:, None, :]            # (N, ry, rx)
        X = np.broadcast_to(xs[:, None, :], wgt.shape)
        Y = np.broadcast_to(ys[:, :, None], wgt.shape)
        m = (X >= 0) & (X < w) & (Y >= 0) & (Y < h)
        val = (wgt * fl[:, None, None])[m]
        cols = np.broadcast_to(cl[:, None, None, :], wgt.shape + (3,))[m]
        for c in range(3):
            np.add.at(img[..., c], (Y[m], X[m]), val * cols[:, c])

    kk = k_res * k_res
    splat(px, py, flux * kk, col, 0.45 * k_res / 2.0 + 0.25, 2)
    big = flux > 0.35
    splat(px[big], py[big], flux[big] * kk * 0.06, col[big], 3.0 * k_res, int(10 * k_res))
    return img


def background(cam_obj, w, h, k_res):
    t0 = time.time()
    lw, lh = max(32, w // 4), max(32, h // 4)
    d = camera_dirs(cam_obj, lw, lh)
    neb = nebula_rgb(d)
    # upsample (bilinear) to full res
    from PIL import Image
    up = np.stack([np.asarray(Image.fromarray(neb[..., c]).resize((w, h), Image.BILINEAR)) for c in range(3)], -1)
    img = up.astype(np.float32)
    splat_stars(img, cam_obj, k_res)
    rgba = np.concatenate([img, np.ones((h, w, 1), np.float32)], -1)
    print("  background %dx%d in %.1fs" % (w, h, time.time() - t0))
    return rgba


def vignette(w, h, strength=0.38, cx=0.5, cy=0.5):
    x = (np.arange(w) + 0.5) / w - cx
    y = (np.arange(h) + 0.5) / h - cy
    a = w / h
    X, Y = np.meshgrid(x * min(a, 1.6), y)
    r = np.sqrt(X * X + Y * Y) / 0.75
    v = 1.0 - strength * smoothstep(0.35, 1.25, r)
    rgba = np.stack([v, v, v, np.ones_like(v)], -1).astype(np.float32)
    return rgba


# ------------------------------------------------------------------------------------------------
# render setup / compositor
# ------------------------------------------------------------------------------------------------
def setup_render(samples, threads):
    scn = bpy.context.scene
    r = scn.render
    r.engine = "CYCLES"
    c = scn.cycles
    c.device = "CPU"
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.015
    c.use_denoising = True
    try:
        c.denoiser = "OPENIMAGEDENOISE"
        c.denoising_input_passes = "RGB_ALBEDO_NORMAL"
        c.denoising_prefilter = "ACCURATE"
    except Exception:
        pass
    c.max_bounces = 8
    c.diffuse_bounces = 2
    c.glossy_bounces = 3
    c.transmission_bounces = 2
    c.transparent_max_bounces = 24
    c.volume_bounces = 0
    c.sample_clamp_indirect = 8.0
    c.blur_glossy = 1.0
    c.caustics_reflective = False
    c.caustics_refractive = False
    try:
        c.use_light_tree = True
    except Exception:
        pass
    r.film_transparent = True
    r.use_compositing = True
    bpy.context.view_layer.use_pass_mist = True
    ms = scn.world.mist_settings
    ms.start, ms.depth, ms.falloff = MIST[0], MIST[1], "LINEAR"
    r.threads_mode = "FIXED" if threads > 0 else "AUTO"
    if threads > 0:
        r.threads = threads
    r.resolution_percentage = 100
    r.pixel_aspect_x = r.pixel_aspect_y = 1.0
    r.dither_intensity = 1.0
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    r.image_settings.compression = 40
    vs = scn.view_settings
    vs.view_transform = "AgX"
    vs.look = LOOK
    vs.exposure = EXPOSURE
    vs.gamma = 1.0


LOOK = "AgX - Medium High Contrast"
EXPOSURE = 0.25
HAZE_COLOR = (0.060, 0.050, 0.110)
HAZE_AMOUNT = 0.45
MIST = (140.0, 220.0)       # mist start / depth (m) measured from the camera


def setup_compositor(bg_img, vig_img, k_res):
    scn = bpy.context.scene
    ng = bpy.data.node_groups.get("Comp_B")
    if ng is not None:
        bpy.data.node_groups.remove(ng)
    ng = bpy.data.node_groups.new("Comp_B", "CompositorNodeTree")
    ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    N = ng.nodes
    Lk = ng.links
    rl = N.new("CompositorNodeRLayers")
    bg = N.new("CompositorNodeImage")
    bg.image = bg_img
    # aerial-perspective haze: far hull parts drift towards a dim violet (sells the size of the flagship)
    hz = N.new("CompositorNodeRGB")
    hz.outputs[0].default_value = (*HAZE_COLOR, 1.0)
    hpre = N.new("ShaderNodeMix")
    hpre.data_type = "RGBA"
    hpre.blend_type = "MULTIPLY"
    hpre.inputs["Factor"].default_value = 1.0
    Lk.new(hz.outputs[0], hpre.inputs[6])
    Lk.new(rl.outputs["Alpha"], hpre.inputs[7])
    fmist = N.new("ShaderNodeMath")
    fmist.operation = "MULTIPLY"
    fmist.inputs[1].default_value = HAZE_AMOUNT
    Lk.new(rl.outputs["Mist"], fmist.inputs[0])
    hmix = N.new("ShaderNodeMix")
    hmix.data_type = "RGBA"
    hmix.blend_type = "MIX"
    Lk.new(fmist.outputs[0], hmix.inputs["Factor"])
    Lk.new(rl.outputs["Image"], hmix.inputs[6])
    Lk.new(hpre.outputs[2], hmix.inputs[7])
    ao = N.new("CompositorNodeAlphaOver")
    ao.inputs["Straight Alpha"].default_value = False
    Lk.new(bg.outputs["Image"], ao.inputs["Background"])
    Lk.new(hmix.outputs[2], ao.inputs["Foreground"])
    # wide soft bloom for every emissive / bright highlight
    g1 = N.new("CompositorNodeGlare")
    g1.inputs["Type"].default_value = "Bloom"
    g1.inputs["Quality"].default_value = "High"
    g1.inputs["Threshold"].default_value = 1.0
    g1.inputs["Smoothness"].default_value = 0.4
    g1.inputs["Strength"].default_value = 0.45
    g1.inputs["Size"].default_value = 0.7
    Lk.new(ao.outputs["Image"], g1.inputs["Image"])
    # subtle horizontal anamorphic streaks on the hottest highlights (weak point, ion core)
    g2 = N.new("CompositorNodeGlare")
    g2.inputs["Type"].default_value = "Streaks"
    g2.inputs["Quality"].default_value = "High"
    g2.inputs["Threshold"].default_value = 14.0
    g2.inputs["Streaks"].default_value = 2
    g2.inputs["Streaks Angle"].default_value = 0.0
    g2.inputs["Fade"].default_value = 0.93
    g2.inputs["Strength"].default_value = 0.12
    g2.inputs["Iterations"].default_value = 4
    Lk.new(g1.outputs["Image"], g2.inputs["Image"])
    vg = N.new("CompositorNodeImage")
    vg.image = vig_img
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    Lk.new(g2.outputs["Image"], mix.inputs[6])
    Lk.new(vg.outputs["Image"], mix.inputs[7])
    out = N.new("NodeGroupOutput")
    Lk.new(mix.outputs[2], out.inputs[0])
    scn.compositing_node_group = ng


def render_view(S, name, final, scale, out_dir, samples):
    scn = bpy.context.scene
    c = CAMERAS[name]
    w, h = c["final"] if final else c["preview"]
    w, h = int(round(w * scale)), int(round(h * scale))
    scn.render.resolution_x, scn.render.resolution_y = w, h
    cam = S.cams[name]
    scn.camera = cam
    bpy.context.view_layer.update()
    k_res = w / c["preview"][0]
    bg = numpy_to_image("BG_" + name, background(cam, w, h, k_res))
    vg = numpy_to_image("VIG_" + name, vignette(w, h))
    setup_compositor(bg, vg, k_res)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "concept_b_%s.png" % name)
    scn.render.filepath = path
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    dt = time.time() - t0
    print("RENDERED %s %dx%d %d spp in %.1fs -> %s" % (name, w, h, samples, dt, path))
    return path, dt


def probe(S):
    """Print normalised screen positions (x right, y down; 0..1) of key points for every camera."""
    from bpy_extras.object_utils import world_to_camera_view
    scn = bpy.context.scene
    M = S.root.matrix_world
    pts = {"WP": S.wp_pos, "ION": S.ion_pos,
           "wingL(+x)": M @ Vector((35.5, 25.0, 0.0)), "wingR(-x)": M @ Vector((-35.5, 25.0, 0.0)),
           "tower": M @ Vector((0.0, -22.0, 29.0)), "keel": M @ Vector((0.0, 0.0, -16.5)),
           "gateTop": M @ Vector((0.0, 40.0, 10.0)), "rear": M @ Vector((0.0, -53.0, 0.0))}
    for d in S.destroyers:
        pts[d.name] = d.matrix_world.translation
    for o in bpy.data.objects:
        if o.name.startswith("FighterR"):
            pts[o.name] = o.matrix_world.translation
    pts["trailEnd"] = S.ion_pos + S.ion_axis * ION_TRAIL_LEN
    for name, c in CAMERAS.items():
        far = S.cams[name].location
        pts["sun@" + name] = far + SUN_DIR * 1e4
        for i, nb in enumerate(NEB_DIRS):
            pts["neb%d@%s" % (i, name)] = far + Vector(nb) * 1e4
        scn.render.resolution_x, scn.render.resolution_y = c["preview"]
        bpy.context.view_layer.update()
        cam = S.cams[name]
        print("--", name, c["preview"])
        for k, p in pts.items():
            v = world_to_camera_view(scn, cam, p)
            print("   %-18s x=%.2f y=%.2f dist=%.0f" % (k, v.x, 1 - v.y, v.z))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--bgonly", action="store_true", help="debug: hide all objects (background + compositor only)")
    ap.add_argument("--border", default="", help="debug: render region x0,y0,x1,y1 (0..1, y up) and crop")
    ap.add_argument("--final", action="store_true")
    ap.add_argument("--only", default="hero,wide,portrait")
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--threads", type=int, default=-1)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--out", default="")
    args = ap.parse_args([a for a in sys.argv[1:]])
    final = args.final
    samples = args.samples or (384 if final else 64)
    threads = args.threads if args.threads >= 0 else (0 if final else 2)
    out_dir = args.out or os.path.join(HERE, "final" if final else "previews")
    t0 = time.time()
    S = build_scene()
    if args.probe:
        probe(S)
        return
    setup_render(samples, threads)
    if args.bgonly:
        for o in bpy.data.objects:
            o.hide_render = True
    if args.border:
        b = [float(v) for v in args.border.split(",")]
        r = bpy.context.scene.render
        r.use_border, r.use_crop_to_border = True, True
        r.border_min_x, r.border_min_y, r.border_max_x, r.border_max_y = b
    print("scene built in %.1fs" % (time.time() - t0))
    times = {}
    for name in [n.strip() for n in args.only.split(",") if n.strip()]:
        path, dt = render_view(S, name, final, args.scale, out_dir, samples)
        times[name] = dt
        if final:
            export_steam_sizes(name, path, out_dir)
    print("TIMES", times)


def export_steam_sizes(name, path, out_dir):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    sizes = {"hero": [(3840, 1240), (1920, 620)], "wide": [(920, 430)], "portrait": [(600, 900)]}[name]
    for (w, h) in sizes:
        p = os.path.join(out_dir, "steam_concept_b_%s_%dx%d.png" % (name, w, h))
        (im if im.size == (w, h) else im.resize((w, h), Image.LANCZOS)).save(p, optimize=True)
        print("  wrote", p)


if __name__ == "__main__":
    main()
