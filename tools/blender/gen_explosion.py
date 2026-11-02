"""
gen_explosion.py - explosion flipbook rendered with Cycles volumes (bpy as module).
Run:  /opt/tools/venv/bin/python tools/blender/gen_explosion.py [--test N]
Output: assets/textures/fx/explosion_flipbook.png (8x8 frames, 256 px each, straight alpha)
Frames are row-major from the top-left: frame 0 = flash/ignition ... frame 63 = faded smoke.

Volume model (object space of a 2x2x2 domain cube):
  radius R(t) grows fast then slows; 4D noise (animated through W) breaks up the surface;
  temperature is highest in the core early on and decays -> Blackbody emission colour;
  density decays over time so the smoke thins out; alpha comes from the transparent film.
"""
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import numpy as np  # noqa: E402

FRAMES = 64
RES = 256
OUT = os.path.join(B.ROOT, "assets", "textures", "fx", "explosion_flipbook.png")
TMP = os.path.join(B.ROOT, "tools", "blender", "explosion_frames")


def node(nt, kind, **props):
    n = nt.nodes.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


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


def setup():
    B.reset()
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = 48
    scn.cycles.use_denoising = True
    try:
        scn.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    for attr, val in (("volume_bounces", 1), ("max_bounces", 3), ("volume_step_rate", 1.5),
                      ("volume_max_steps", 256)):
        try:
            setattr(scn.cycles, attr, val)
        except Exception:
            pass
    scn.render.resolution_x = RES
    scn.render.resolution_y = RES
    scn.render.film_transparent = True
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    try:
        scn.view_settings.view_transform = "Standard"
    except Exception:
        pass
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.06, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scn.world = world

    # domain cube
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0, 0, 0))
    dom = bpy.context.active_object
    dom.name = "Domain"
    m = bpy.data.materials.new("ExplosionVolume")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = node(nt, "ShaderNodeOutputMaterial")
    vol = node(nt, "ShaderNodeVolumePrincipled")
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    dom.data.materials.append(m)

    vals = {}
    for name in ("R", "A1", "A2", "dens", "heat", "w", "emis", "core_k"):
        v = node(nt, "ShaderNodeValue")
        v.label = name
        vals[name] = v

    tc = node(nt, "ShaderNodeTexCoord")
    pos = tc.outputs["Object"]
    vlen = node(nt, "ShaderNodeVectorMath", operation="LENGTH")
    nt.links.new(pos, vlen.inputs[0])
    r = vlen.outputs["Value"]

    def noise4(scale, wmul, detail, rough, dist=0.0):
        n = node(nt, "ShaderNodeTexNoise", noise_dimensions="4D")
        nt.links.new(pos, n.inputs["Vector"])
        nt.links.new(math_node(nt, "MULTIPLY", vals["w"].outputs[0], wmul), n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        return n.outputs["Fac"]

    n1 = noise4(1.5, 1.0, 3.0, 0.5, 0.2)    # large lobes
    n2 = noise4(4.2, 1.6, 5.0, 0.55, 0.0)   # billows
    n3 = noise4(9.0, 2.3, 4.0, 0.6, 0.0)    # wisps / hot pockets

    # displacement d = A1*(n1-0.5)*2 + A2*(n2-0.5)*2 ; shape = R*(1+d) - r
    d1 = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", n1, 0.5), 2.0)
    d1 = math_node(nt, "MULTIPLY", d1, vals["A1"].outputs[0])
    d2 = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", n2, 0.5), 2.0)
    d2 = math_node(nt, "MULTIPLY", d2, vals["A2"].outputs[0])
    d = math_node(nt, "ADD", math_node(nt, "ADD", d1, d2), 1.0)
    shape = math_node(nt, "SUBTRACT", math_node(nt, "MULTIPLY", d, vals["R"].outputs[0]), r)
    soft = math_node(nt, "MULTIPLY", shape, 13.0, clamp=True)
    wisp = math_node(nt, "ADD", math_node(nt, "MULTIPLY", n3, 1.4), 0.3)
    dens = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", soft, wisp), vals["dens"].outputs[0])
    nt.links.new(dens, vol.inputs["Density"])

    # core = clamp(1 - r / (R*core_k*(0.7+0.6*n2)))
    c1 = math_node(nt, "ADD", math_node(nt, "MULTIPLY", n2, 0.6), 0.7)
    c1 = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", c1, vals["R"].outputs[0]), vals["core_k"].outputs[0])
    core = math_node(nt, "SUBTRACT", 1.0, math_node(nt, "DIVIDE", r, c1), clamp=True)
    hp = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", n3, 0.33), 3.0, clamp=True)   # hot pockets 0..1
    # temperature = 800 + 6200 * heat * core^0.6 * (0.55 + 0.45*hp)
    tt = math_node(nt, "MULTIPLY", math_node(nt, "POWER", core, 0.6), vals["heat"].outputs[0])
    tt = math_node(nt, "MULTIPLY", tt, math_node(nt, "ADD", math_node(nt, "MULTIPLY", hp, 0.45), 0.55))
    temp = math_node(nt, "ADD", math_node(nt, "MULTIPLY", tt, 6200.0), 800.0)
    bb = node(nt, "ShaderNodeBlackbody")
    nt.links.new(temp, bb.inputs["Temperature"])
    nt.links.new(bb.outputs["Color"], vol.inputs["Emission Color"])
    # emission strength = emis * soft * core * (0.3 + 0.7*hp)
    es = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", core, soft),
                   math_node(nt, "ADD", math_node(nt, "MULTIPLY", hp, 0.7), 0.3))
    es = math_node(nt, "MULTIPLY", es, vals["emis"].outputs[0])
    nt.links.new(es, vol.inputs["Emission Strength"])
    vol.inputs["Color"].default_value = (0.13, 0.12, 0.11, 1.0)
    vol.inputs["Absorption Color"].default_value = (0.015, 0.015, 0.015, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.25

    # camera (orthographic, looking along +Y)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.05
    cam.location = (0, -6, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scn.camera = cam
    # soft key light for the smoke
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.5
    sun.rotation_euler = (math.radians(50), math.radians(-35), 0)
    scn.collection.objects.link(sun)
    return scn, vals


def params(t):
    """Animation curves for frame time t in [0,1]."""
    R = 0.16 + 0.62 * (1.0 - (1.0 - t) ** 2.8)
    A1 = 0.30 + 0.18 * t
    A2 = 0.16 + 0.06 * t
    dens = 34.0 * (1.0 - t) ** 1.5 + 0.8
    heat = max(0.0, 1.0 - t / 0.62) ** 1.2
    w = t * 1.6
    emis = 70.0 * heat ** 1.5
    core_k = 1.0 - 0.3 * t
    return dict(R=R, A1=A1, A2=A2, dens=dens, heat=heat, w=w, emis=emis, core_k=core_k)


def render(test=None):
    scn, vals = setup()
    os.makedirs(TMP, exist_ok=True)
    frames = range(FRAMES) if test is None else [test]
    for f in frames:
        t = f / (FRAMES - 1)
        p = params(t)
        for k, v in p.items():
            vals[k].outputs[0].default_value = v
        scn.render.filepath = os.path.join(TMP, "f%02d.png" % f)
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        print("frame", f, "%.1fs" % (time.time() - t0), flush=True)


def assemble():
    from PIL import Image
    atlas = Image.new("RGBA", (RES * 8, RES * 8), (0, 0, 0, 0))
    for f in range(FRAMES):
        im = Image.open(os.path.join(TMP, "f%02d.png" % f)).convert("RGBA")
        a = np.asarray(im).astype(np.float32) / 255.0
        # fade the very last frames out completely and soften the edge of the frame
        t = f / (FRAMES - 1)
        fade = 1.0 if t < 0.8 else max(0.0, 1.0 - (t - 0.8) / 0.2) ** 1.5
        yy, xx = np.mgrid[0:RES, 0:RES]
        rr = np.sqrt((xx - RES / 2 + 0.5) ** 2 + (yy - RES / 2 + 0.5) ** 2) / (RES / 2)
        edge = np.clip((1.0 - rr) / 0.08, 0, 1)
        a[..., 3] *= fade * edge
        im = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
        atlas.paste(im, ((f % 8) * RES, (f // 8) * RES))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT, optimize=True)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    if "--test" in sys.argv:
        render(int(sys.argv[sys.argv.index("--test") + 1]))
    elif "--assemble" in sys.argv:
        assemble()
    else:
        render()
        assemble()
