"""
gen_icon.py - application icon for Starfighter Defense.
Run:  /opt/tools/venv/bin/python tools/blender/gen_icon.py
Output: assets/textures/ui/icon.png (256x256 RGBA) and assets/textures/ui/icon.ico (16..256)
A white/cyan player starfighter (rendered with Cycles, transparent film) climbs over a planet
horizon with a cyan atmosphere, sun flare top right, deep navy rounded-square background.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

from model_fighter import strip, diamond_secs  # noqa: E402

UI = os.path.join(B.ROOT, "assets", "textures", "ui")
TMP = os.path.join(B.ROOT, "tools", "blender", "previews", "icon_ship.png")


def player_ship():
    B.reset()
    white = B.mat("Hull", (0.86, 0.89, 0.93), 0.35, 0.3)
    dark = B.mat("HullDark", (0.10, 0.13, 0.18), 0.4, 0.4)
    cyan = B.mat("Accent", (0.2, 0.9, 1.0), 0.0, 0.3, emission=(0.25, 0.92, 1.0), strength=6.0)
    glass = B.mat("Glass", (0.02, 0.10, 0.16), 0.3, 0.05, emission=(0.1, 0.5, 0.8), strength=1.5)
    parts = []
    body = [(3.6, 0.04, 0.03, -0.03, 0), (2.4, 0.42, 0.30, -0.20, 0), (0.6, 0.70, 0.46, -0.30, 0.02),
            (-1.6, 0.80, 0.40, -0.32, 0.02), (-3.0, 0.62, 0.30, -0.26, 0)]
    secs = [B.sec_y(y, B.oct_pts(w, zt, zb, zm)) for (y, w, zt, zb, zm) in body]
    parts.append(B.part("body", B.bm_loft(secs), white, bevel_w=0.03, seg=1))
    can = [(2.0, 0.05, 0.32, 0.26), (1.3, 0.30, 0.62, 0.38), (0.2, 0.30, 0.58, 0.42), (-0.4, 0.12, 0.50, 0.42)]
    secs = [B.sec_y(y, [(-w, zb), (0, zt), (w, zb)]) for (y, w, zt, zb) in can]
    parts.append(B.part("canopy", B.bm_loft(secs), glass, wn=False))
    wst = [(0.5, 0.6, -2.6, 0.0, 0.14), (2.4, -1.0, -2.9, -0.05, 0.08), (3.6, -2.2, -3.1, -0.1, 0.04)]
    parts.append(B.part("wing", B.bm_loft(diamond_secs(wst)), white, bevel_w=0.02, seg=1, mirror=True))
    parts.append(B.part("wingstripe", strip((1.0, 0.25, 0.10), (3.3, -2.1, 0.0), 0.16, 0.05), cyan,
                        mirror=True, wn=False))
    for sx in (0.75,):
        parts.append(B.part("eng", B.bm_cyl((sx, -1.2, -0.05), (sx, -3.3, -0.05), 0.34, 0.30, sides=12), dark,
                            mirror=True, wn=False))
        parts.append(B.part("eglow", B.bm_cyl((sx, -3.31, -0.05), (sx, -3.36, -0.05), 0.24, 0.24, sides=12), cyan,
                            mirror=True, wn=False))
    parts.append(B.part("fin", B.bm_loft(diamond_secs([(0.0, -1.2, -3.0, 0.35, 0.05)], rear_bias=0.5) +
                                          diamond_secs([(0.0, -2.4, -3.2, 1.3, 0.02)], rear_bias=0.5)),
                        white, wn=False))
    return B.join(parts, "Player")


def render_ship():
    ship = player_ship()
    # orient: nose toward upper right in the final image
    ship.rotation_euler = (math.radians(18), math.radians(-12), math.radians(-38))
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 64
    scn.cycles.use_denoising = True
    scn.render.resolution_x = 768
    scn.render.resolution_y = 768
    scn.render.film_transparent = True
    try:
        scn.view_settings.view_transform = "AgX"
    except Exception:
        pass
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.08, 0.14, 1)
    scn.world = world
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 8.6
    cam.location = (0, 0, 20)
    scn.camera = cam
    for name, energy, rot, colr in (("Key", 4.0, (0.5, 0.3, 0.6), (1, 0.97, 0.92)),
                                    ("Rim", 3.0, (-0.9, -0.4, 0.2), (0.4, 0.8, 1.0))):
        l = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        l.data.energy = energy
        l.data.color = colr
        l.rotation_euler = rot
        scn.collection.objects.link(l)
    scn.render.filepath = TMP
    bpy.ops.render.render(write_still=True)


def compose():
    S = 1024  # work at 4x, downsample to 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    # background gradient
    bg = np.zeros((S, S, 3), np.float32)
    top = np.array([0.02, 0.04, 0.10])
    bot = np.array([0.05, 0.10, 0.22])
    bg[:] = top * (1 - yy[..., None]) + bot * yy[..., None]
    rng = np.random.default_rng(3)
    for _ in range(120):  # few stars
        x, y = rng.integers(0, S, 2)
        r = rng.uniform(1.0, 3.0)
        b = rng.uniform(0.3, 0.9)
        d2 = (xx * S - x) ** 2 + (yy * S - y) ** 2
        bg += (b * np.exp(-d2 / (2 * r * r)))[..., None] * np.array([0.9, 0.95, 1.0])
    # sun flare top right
    sx, sy = 0.80, 0.18
    d = np.sqrt((xx - sx) ** 2 + (yy - sy) ** 2)
    bg += (0.9 * np.exp(-(d / 0.03) ** 2) + 0.35 * np.exp(-(d / 0.12) ** 2))[..., None] * np.array([1.0, 0.92, 0.75])
    ray = np.exp(-np.abs(yy - sy) / 0.004) * np.exp(-np.abs(xx - sx) / 0.25) + \
        np.exp(-np.abs(xx - sx) / 0.004) * np.exp(-np.abs(yy - sy) / 0.25)
    bg += (0.5 * ray)[..., None] * np.array([1.0, 0.95, 0.85])
    # planet horizon (big circle below)
    pc = np.array([0.30, 1.55])
    pr = 0.95
    dp = np.sqrt((xx - pc[0]) ** 2 + (yy - pc[1]) ** 2)
    planet = dp < pr
    # orthographic sphere: sample the home-planet texture, lit from the sun (top right)
    tex = np.asarray(Image.open(os.path.join(B.ROOT, "assets", "textures", "planets", "terran.png"))
                     .convert("RGB").resize((1024, 512), Image.LANCZOS)).astype(np.float32) / 255.0
    nx = (xx - pc[0]) / pr
    ny = -(yy - pc[1]) / pr
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0, 1))
    tilt = np.radians(-25.0)  # tilt the globe so more interesting latitudes face the viewer
    ny2 = ny * np.cos(tilt) - nz * np.sin(tilt)
    nz2 = ny * np.sin(tilt) + nz * np.cos(tilt)
    lon = np.arctan2(nx, nz2) + 1.2
    lat = np.arcsin(np.clip(ny2, -1, 1))
    u = ((lon / (2 * np.pi) + 0.5) % 1.0) * 1023
    v = np.clip((0.5 - lat / np.pi) * 511, 0, 511)
    pcol = tex[v.astype(int), u.astype(int)]
    sun = np.array([0.55, 0.65, 0.52])
    lam = np.clip(nx * sun[0] + ny * sun[1] + nz * sun[2], 0, 1)
    pcol = pcol * (0.18 + 0.95 * lam[..., None])
    bg = np.where(planet[..., None], pcol, bg)
    atm = np.exp(-((dp - pr) / 0.018) ** 2) * 1.2 + np.exp(-np.maximum(dp - pr, 0) / 0.06) * 0.35 * (dp >= pr)
    bg += atm[..., None] * np.array([0.25, 0.85, 1.0])
    img = Image.fromarray((np.clip(bg, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8), "RGB").convert("RGBA")
    # ship with a cyan glow behind it
    ship = Image.open(TMP).convert("RGBA").resize((860, 860), Image.LANCZOS)
    glow = ship.split()[3].filter(ImageFilter.GaussianBlur(28))
    glow_img = Image.new("RGBA", ship.size, (60, 220, 255, 0))
    glow_img.putalpha(glow.point(lambda v: int(v * 0.55)))
    ox, oy = (S - 860) // 2 + 10, (S - 860) // 2 - 20
    img.alpha_composite(glow_img, (ox, oy))
    img.alpha_composite(ship, (ox, oy))
    # rounded-square mask
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((8, 8, S - 8, S - 8), radius=190, fill=255)
    img.putalpha(mask)
    # thin cyan border
    border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((10, 10, S - 10, S - 10), radius=188, outline=(80, 220, 255, 200), width=10)
    img.alpha_composite(border)
    final = img.resize((256, 256), Image.LANCZOS)
    os.makedirs(UI, exist_ok=True)
    final.save(os.path.join(UI, "icon.png"), optimize=True)
    final.save(os.path.join(UI, "icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # preview at several sizes
    pv = Image.new("RGBA", (256 + 128 + 48 + 32 + 16 + 50, 256), (40, 44, 56, 255))
    x = 0
    for s in (256, 128, 48, 32, 16):
        pv.alpha_composite(final.resize((s, s), Image.LANCZOS), (x, 0))
        x += s + 10
    pv.save(os.path.join(B.PREVIEW_DIR, "icon_sizes.png"))
    print("icon written")


if __name__ == "__main__":
    render_ship()
    compose()
