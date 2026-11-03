"""
make_icon.py - renders the PLAYER's starfighter for the Steam icon at high resolution (2048x2048, RGBA).

The ship is gen_icon.player_ship() from tools/blender/gen_icon.py (imported, nothing under assets/ is
touched), in the same pose as the game icon (rotation 18 / -12 / -38 deg, orthographic camera, nose to the
upper right), so the taskbar / library icons keep the game's silhouette. Changes for an icon that has to
read at 16-32 px:
  * the camera is fitted to the ship: it fills ~94 % of the render (the composer scales it to ~85 %)
  * a strong cyan (#52E6FF) rim light from below / behind, warm key light from the upper right
  * brighter cyan wing stripes / engine glows, subtle plate tone variation on the hull (concept C's
    panel lines are available via PANEL_LINES but off: at icon sizes they read as cracks)
  * transparent film; the background (navy -> violet, dark night-side planet with a thin cyan limb arc,
    one small amber glint) and all icon sizes are made by compose_steam_assets.py
Run:  /opt/tools/venv/bin/python tools/steam/make_icon.py [--samples 128] [--res 2048] [--threads 4]
Output: tools/steam/renders/icon_ship_2048.png (+ icon_ship_meta.json: engine nozzle positions in pixels)
"""
import argparse
import json
import math
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import blib as B  # noqa: E402,F401  (imports bpy first)
import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402
from gen_icon import player_ship  # noqa: E402

RENDERS = os.path.join(HERE, "renders")


def srgb2lin(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


CYAN = tuple(srgb2lin(v / 255.0) for v in (0x52, 0xE6, 0xFF))
POSE = (18.0, -12.0, -38.0)                       # same as gen_icon.render_ship()
PANEL_LINES = 0.0      # strength of concept C's Voronoi panel lines; 0: they read as cracks at icon sizes


def bsdf_of(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def upgrade_materials():
    """panel lines + plate tone on the hull (as concept C), brighter cyan accents and canopy"""
    hull = bpy.data.materials["Hull"]
    nt = hull.node_tree
    b = bsdf_of(hull)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.distance = "CHEBYCHEV"
    vor.inputs["Scale"].default_value = 1.7
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    line = nt.nodes.new("ShaderNodeMapRange")
    line.inputs["From Min"].default_value = 0.0
    line.inputs["From Max"].default_value = 0.014
    line.inputs["To Min"].default_value = 1.0
    line.inputs["To Max"].default_value = 0.0
    nt.links.new(vor.outputs["Distance"], line.inputs["Value"])
    vc = nt.nodes.new("ShaderNodeTexVoronoi")
    vc.distance = "CHEBYCHEV"
    vc.inputs["Scale"].default_value = 1.7
    nt.links.new(tc.outputs["Object"], vc.inputs["Vector"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vc.outputs["Color"], sep.inputs[0])
    tone = nt.nodes.new("ShaderNodeMapRange")
    tone.inputs["To Min"].default_value = 0.88
    tone.inputs["To Max"].default_value = 1.0
    nt.links.new(sep.outputs[0], tone.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    mul.inputs[6].default_value = (0.84, 0.88, 0.93, 1.0)
    nt.links.new(tone.outputs["Result"], mul.inputs[7])
    fac = nt.nodes.new("ShaderNodeMath")
    fac.operation = "MULTIPLY"
    fac.inputs[1].default_value = PANEL_LINES
    nt.links.new(line.outputs["Result"], fac.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(fac.outputs[0], mix.inputs[0])
    nt.links.new(mul.outputs[2], mix.inputs[6])
    mix.inputs[7].default_value = (0.16, 0.18, 0.22, 1.0)
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.08
    b.inputs["Roughness"].default_value = 0.32
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = 0.3
    acc = bsdf_of(bpy.data.materials["Accent"])
    acc.inputs["Base Color"].default_value = (*CYAN, 1.0)
    acc.inputs["Emission Color"].default_value = (*CYAN, 1.0)
    acc.inputs["Emission Strength"].default_value = 11.0
    gl = bsdf_of(bpy.data.materials["Glass"])
    gl.inputs["Emission Color"].default_value = (0.06, 0.45, 0.85, 1.0)
    gl.inputs["Emission Strength"].default_value = 2.2


def sun(name, toward_light, energy, color, angle=3.0):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.color = color
    ld.angle = math.radians(angle)
    lo = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.rotation_euler = (-Vector(toward_light).normalized()).to_track_quat("-Z", "Y").to_euler()
    return lo


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--res", type=int, default=2048)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--out", default=RENDERS)
    args = ap.parse_args()
    ship = player_ship()                       # resets the file
    upgrade_materials()
    ship.rotation_euler = Euler(tuple(math.radians(a) for a in POSE))
    bpy.context.view_layer.update()
    # fit the orthographic camera (looking down -Z, image up = +Y) to the ship's projected extent
    M = ship.matrix_world
    pts = [M @ v.co for v in ship.data.vertices]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    ext = max(x1 - x0, y1 - y0)
    scn = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ext / 0.94
    cam.data.clip_end = 100.0
    cam.location = ((x0 + x1) / 2, (y0 + y1) / 2, 20.0)
    scn.camera = cam
    # lights: warm key from the upper right / above, strong cyan rim from below-behind (lower left),
    # faint cool fill so the hull's shadow side is not dead grey
    sun("Key", (0.55, 0.45, 0.70), 4.2, (1.0, 0.95, 0.88))
    sun("RimCyan", (-0.62, -0.55, -0.56), 14.0, CYAN, angle=6.0)
    sun("RimCyan2", (-0.85, 0.05, -0.52), 6.0, CYAN, angle=6.0)
    sun("Fill", (-0.3, -0.2, 0.93), 0.6, (0.55, 0.7, 1.0), angle=20.0)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.018, 0.03, 0.07, 1)
    scn.world = world
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = args.samples
    scn.cycles.use_adaptive_sampling = True
    scn.cycles.adaptive_threshold = 0.01
    scn.cycles.use_denoising = True
    scn.cycles.denoiser = "OPENIMAGEDENOISE"
    try:
        scn.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
        scn.cycles.denoising_quality = "HIGH"
    except Exception:  # noqa: BLE001
        pass
    scn.render.threads_mode = "FIXED"
    scn.render.threads = args.threads
    scn.render.resolution_x = scn.render.resolution_y = args.res
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = True
    scn.render.filter_size = 1.2
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Punchy"
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.render.image_settings.color_depth = "16"
    scn.render.dither_intensity = 0.0
    os.makedirs(args.out, exist_ok=True)
    out = os.path.join(args.out, "icon_ship_%d.png" % args.res)
    scn.render.filepath = out
    bpy.ops.render.render(write_still=True)
    # engine nozzle centres (gen_icon: engines at x = +-0.75, nozzle glow at y = -3.36, z = -0.05) in pixels
    half = cam.data.ortho_scale / 2
    nozzles = []
    for sx in (-0.75, 0.75):
        p = M @ Vector((sx, -3.36, -0.05))
        u = (p.x - cam.location.x + half) / (2 * half)
        v = 1.0 - (p.y - cam.location.y + half) / (2 * half)
        nozzles.append((u * args.res, v * args.res))
    meta = dict(res=args.res, nozzles=nozzles, pose=POSE, ortho_scale=cam.data.ortho_scale)
    with open(os.path.join(args.out, "icon_ship_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("icon ship ->", out, meta)


if __name__ == "__main__":
    main()
