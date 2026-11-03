"""
concept_a.py - Steam library art, concept A "Verteidigung von Halcyon".

One 3D scene (Blender 5.2 / Cycles, no volumetrics):
  * Halcyon: terran texture + clouds, ocean gloss, procedural city lights on the night side (hierarchical
    city map generated from the land/coast mask, faded close below the camera), faint moonlight, analytic
    atmosphere shell (ray impact parameter -> thin cyan rim + haze, forward scattering toward the sun,
    thin warm sunset layer where the terminator crosses the limb). The sun sits just behind the right limb.
  * Enemy fighter "finger four" diving toward the cockpit (assets/models/fighter.glb, darker hull with a
    little grime), orange engine plumes + long ion trails, a distant second wave.
  * Two cyan cockpit lasers from the lower edge converge on the element lead, which explodes: a numpy
    ray-marched high-res fireball (cached) on a camera-facing card, white-hot flash, burning fragments,
    sparks, tumbling debris (loose parts of a fighter copy with charred material), orange point light.
  * A small ring station in the far distance (hero only, by placement).
Three cameras: hero (the cockpit), wide and portrait (aimed so the explosion lands at a chosen screen
point). The star/nebula background is a per-camera numpy plate at the output resolution (crisp stars,
nebula from the game's sky panorama with its baked stars removed), alpha-composited behind the film-
transparent render in the compositor, then Glare (Fog Glow + Bloom) and a vignette. View: AgX Punchy.

Run (from the project root):
  /opt/tools/venv/bin/python tools/steam/concept_a.py                  # previews -> tools/steam/previews/
  /opt/tools/venv/bin/python tools/steam/concept_a.py --final          # full size -> tools/steam/final/
Options:
  --only hero,wide,portrait   render a subset
  --samples N                 override samples (preview 64, final 192; OpenImageDenoise is always on)
  --threads N                 render threads (preview 2, final 4)
  --scale F                   resolution factor (quick tests, e.g. 0.5)
  --out DIR                   output directory
  --debug k=v,...             development overrides (e.g. fire=0.4, moon=0.45, neb=1.8, no_action, spin=150)

Output: concept_a_hero.png (1920x620 / final 3840x1240), concept_a_wide.png (920x430 / 1840x860),
concept_a_portrait.png (600x900 / 1200x1800). Clear zones for the title/logo: hero lower-left third,
wide left third, portrait upper quarter. No text is rendered.
Helper textures are generated once into tools/steam/cache/ (city lights, ocean mask, de-starred nebula,
fireball; ~3 min on first run, can be deleted at any time).
"""
import argparse
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))

import blib as B  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402
from PIL import Image  # noqa: E402

ASSETS = os.path.join(ROOT, "assets")
MODELS = os.path.join(ASSETS, "models")
PLANETS = os.path.join(ASSETS, "textures", "planets")
SKY = os.path.join(ASSETS, "textures", "sky")
CACHE = os.path.join(HERE, "cache")

# brand palette (linear Rec.709); CYAN is used for the lasers / atmosphere, the others are kept for reference
def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


CYAN = srgb2lin((0x52 / 255, 0xE6 / 255, 1.0))      # #52E6FF
AMBER = srgb2lin((1.0, 0xB8 / 255, 0x38 / 255))     # #FFB838
RED = srgb2lin((1.0, 0x47 / 255, 0x38 / 255))       # #FF4738
PINK = srgb2lin((1.0, 0x5C / 255, 0xD6 / 255))      # #FF5CD6

# ------------------------------------------------------------------------------------------------
# world layout (metres). Camera "cockpit" near the origin looking along +Y, Z up.
# ------------------------------------------------------------------------------------------------
PLANET_R = 20000.0
PLANET_ALPHA = math.radians(50.0)    # angular radius of the planet seen from the origin
PLANET_DEPRESS = math.radians(56.0)  # angle of the planet centre below the horizontal
_D = PLANET_R / math.sin(PLANET_ALPHA)
PLANET_C = Vector((0.0, _D * math.cos(PLANET_DEPRESS), -_D * math.sin(PLANET_DEPRESS)))
PLANET_SPIN = 150.0   # deg, rotation about the planet axis (choose the continents)
PLANET_TILT = 80.0    # deg, tilts the north pole toward the camera -> mid latitudes in view
PLANET_ROLL = 0.0

SUN_AZ = 62.0    # deg, from +Y toward +X (right): just behind the right limb -> rim light along the limb
SUN_EL = -4.0    # deg
SUN_DIR = Vector((0, 0, 1))
DEBUG = {}       # development overrides from --debug k=v,...


def update_sun():
    global SUN_DIR
    az = math.radians(DEBUG.get("sun_az", SUN_AZ))
    el = math.radians(DEBUG.get("sun_el", SUN_EL))
    SUN_DIR = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))


# Action layout: the formation leader is placed in the HERO camera's screen space (u, v, depth m); the
# wingmen follow as offsets in formation space, so all three cameras look at the same 3D scene.
FLIGHT = Vector((-0.30, -1.0, -0.34)).normalized()    # formation dives toward the cockpit, a bit left/down
LEADER = (0.50, 0.58, 34.0)
FORMATION = [  # lateral (pilot's right = screen left), back (along -flight), up, bank deg, plume scale
    (0.0, 0.0, 0.0, -16.0, 1.0),       # leader
    (6.0, 12.0, 1.5, -14.0, 1.0),      # wingman (screen left of the leader)
    (-8.0, 9.0, 0.0, -18.0, 1.0),      # element lead (screen right) -> hit by the lasers, explodes
    (-14.0, 17.0, -6.0, -20.0, 1.1),   # element wingman
]
EXPLODES = 2
DISTANT = [  # far second wave, placed in hero screen space: u, v, depth, bank
    (0.612, 0.085, 420.0, -15.0),
    (0.566, 0.145, 520.0, -12.0),
]
STATION = (0.10, 0.24, 2500.0)     # hero screen space, depth (m)
NEBULA_SHIFT = 0.0                 # rotate the sky panorama (fraction of 360 deg)
NEBULA_GAIN = 1.8
STREAKS = 0.0                      # anamorphic streak strength on the explosion core (0 = off)
VIGNETTE = 0.42
MOON = 0.45

FRAMINGS = {
    # res = preview, final = full size; hfov in degrees; cam = position; ypr = yaw/pitch/roll (deg)
    # beams = where the two cockpit lasers enter the frame (u, v) - they start 2.5 m in front of the lens
    "hero": dict(res=(1920, 620), final=(3840, 1240), hfov=62.0, cam=(0.0, 0.0, 0.0), ypr=(0.0, -3.0, 0.0),
                 beams=[(0.30, 1.12), (1.04, 1.10)]),
    # aim = put the explosion at screen (u, v) with a camera roll (deg); yaw/pitch are derived
    "wide": dict(res=(920, 430), final=(1840, 860), hfov=46.0, cam=(0.0, -6.0, 0.0), aim=(0.76, 0.45, 0.0),
                 beams=[(0.42, 1.10), (1.05, 1.06)]),
    "portrait": dict(res=(600, 900), final=(1200, 1800), hfov=33.0, cam=(0.0, 0.0, 0.0), aim=(0.62, 0.44, 0.0),
                     beams=[(-0.06, 1.04), (1.06, 1.04)]),
}


# ------------------------------------------------------------------------------------------------
# node helpers
# ------------------------------------------------------------------------------------------------
class Tree:
    """Tiny helper to write shader node trees compactly. Values may be sockets (linked) or constants."""

    def __init__(self, mat):
        try:
            mat.use_nodes = True
        except Exception:
            pass
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")

    def node(self, kind, inputs=None, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        for k, v in (inputs or {}).items():
            self.set(n.inputs[k], v)
        return n

    def set(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        elif v is not None:
            if hasattr(sock, "default_value"):
                dv = sock.default_value
                if hasattr(dv, "__len__") and not isinstance(v, (list, tuple)):
                    v = [v] * len(dv)
                if hasattr(dv, "__len__") and len(v) == 3 and len(dv) == 4:
                    v = (*v, 1.0)
                sock.default_value = v

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b, c)):
            if v is not None:
                self.set(n.inputs[i], v)
        return n.outputs[0]

    def vmath(self, op, a, b=None, scale=None):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        if a is not None:
            self.set(n.inputs[0], a)
        if b is not None:
            self.set(n.inputs[1], b)
        if scale is not None:
            self.set(n.inputs["Scale"], scale)
        if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE"):
            return n.outputs["Value"]
        return n.outputs["Vector"]

    def maprange(self, v, a, b, c=0.0, d=1.0, clamp=True, interp="LINEAR"):
        n = self.node("ShaderNodeMapRange", {"Value": v, "From Min": a, "From Max": b, "To Min": c, "To Max": d},
                      clamp=clamp, interpolation_type=interp)
        return n.outputs["Result"]

    def mix(self, fac, a, b):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = "MIX"
        self.set(n.inputs[0], fac)
        self.set(n.inputs[6], a)
        self.set(n.inputs[7], b)
        return n.outputs[2]

    def mixf(self, fac, a, b):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        self.set(n.inputs[0], fac)
        self.set(n.inputs[2], a)
        self.set(n.inputs[3], b)
        return n.outputs[0]

    def rgbmul(self, col, f):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = "MULTIPLY"
        self.set(n.inputs[0], 1.0)
        self.set(n.inputs[6], col)
        self.set(n.inputs[7], f)
        return n.outputs[2]

    def image(self, path, vector=None, colorspace="sRGB", interp="Cubic", ext="REPEAT"):
        img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = colorspace
        n = self.node("ShaderNodeTexImage", image=img, interpolation=interp, extension=ext)
        if vector is not None:
            self.set(n.inputs["Vector"], vector)
        return n

    def output(self, shader):
        self.nt.links.new(shader, self.out.inputs["Surface"])


def new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


def no_emission_sampling(m):
    try:
        m.cycles.emission_sampling = "NONE"
    except Exception:
        pass


def camera_only(ob, shadow=False):
    """Object only visible to camera rays (pure additive FX)."""
    ob.visible_diffuse = False
    ob.visible_glossy = False
    ob.visible_transmission = False
    ob.visible_volume_scatter = False
    ob.visible_shadow = shadow


# ------------------------------------------------------------------------------------------------
# cached helper textures (numpy)
# ------------------------------------------------------------------------------------------------
def _load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0


def planet_aux_maps():
    """ocean mask (4096x2048) + city light map (8192x4096) for the terran texture."""
    os.makedirs(CACHE, exist_ok=True)
    ocean_p = os.path.join(CACHE, "concept_a_ocean.png")
    city_p = os.path.join(CACHE, "concept_a_citylights.png")
    if os.path.exists(ocean_p) and os.path.exists(city_p):
        return ocean_p, city_p
    from scipy import ndimage
    t0 = time.time()
    tex = _load_rgb(os.path.join(PLANETS, "terran.png"))
    r, g, b = tex[..., 0], tex[..., 1], tex[..., 2]
    blue = b - np.maximum(r, g)
    bright = (r + g + b) / 3.0
    ocean = np.clip((blue + 0.02) / 0.06, 0, 1) * np.clip((0.62 - bright) / 0.1, 0, 1)
    ocean = ndimage.gaussian_filter(ocean, 0.8)
    Image.fromarray((ocean * 255).astype(np.uint8), "L").save(ocean_p)

    # --- city lights at 2x resolution ---
    W, H = 8192, 4096
    land = (blue < -0.04) & (bright < 0.72)
    land = np.asarray(Image.fromarray((land * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR),
                      np.float32) / 255.0
    oc = np.asarray(Image.fromarray((ocean * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR),
                    np.float32) / 255.0
    coast = land * np.clip(ndimage.gaussian_filter(oc, 10.0) * 3.0, 0, 1)
    lat = (0.5 - (np.arange(H) + 0.5) / H) * math.pi
    latw = np.clip((math.radians(62) - np.abs(lat)) / math.radians(20), 0, 1)[:, None]
    rng = np.random.default_rng(11)
    # population regions: smooth noise
    pop = np.zeros((H // 16, W // 16), np.float32)
    for s, a in ((24, 1.0), (8, 0.6), (3, 0.35)):
        pop += a * ndimage.gaussian_filter(rng.standard_normal(pop.shape).astype(np.float32), s, mode="wrap")
    pop = (pop - pop.mean()) / pop.std()
    pop = np.asarray(Image.fromarray(pop).resize((W, H), Image.BICUBIC), np.float32)
    pop = np.clip(0.55 + 0.45 * pop, 0, 1.6)
    dens = land * (0.12 + 1.6 * coast) * pop * latw
    flat = dens.ravel().astype(np.float64)
    flat /= flat.sum()
    landf = land > 0.5
    # hierarchical lights: city cores + suburbs, highways between neighbours, faint rural dust
    pts = {0.55: [], 0.9: [], 1.6: [], 2.8: [], 5.0: []}   # sigma(px) -> list of (x, y, brightness)

    def put(sig, x, y, b):
        x = np.mod(np.asarray(x, np.float64), W)
        y = np.clip(np.asarray(y, np.float64), 0, H - 1)
        ok = landf[y.astype(int), x.astype(int)]
        pts[sig].append(np.stack([x[ok], y[ok], np.broadcast_to(b, x.shape)[ok]], -1))

    n_city = 1100
    idx = rng.choice(flat.size, size=n_city, p=flat)
    cy, cx = np.divmod(idx, W)
    size = np.clip(rng.pareto(2.0, n_city) + 1.0, 1.0, 12.0)
    for x0, y0, sz in zip(cx, cy, size):
        stretch = 1.0 / max(math.cos((0.5 - (y0 + 0.5) / H) * math.pi), 0.3)
        r = 3.0 * sz
        core_sig = 0.9 if sz < 1.6 else (1.6 if sz < 3 else (2.8 if sz < 6 else 5.0))
        put(core_sig, [x0], [y0], 0.5 + 0.35 * sz)
        k = int(5 * r ** 1.3)
        off = rng.standard_t(3, (k, 2)) * r * 0.55
        dist = np.sqrt((off ** 2).sum(-1)) / r
        bri = rng.uniform(0.12, 0.6, k) * np.exp(-dist * 0.8)
        sig = np.where(rng.uniform(0, 1, k) < 0.75, 0.55, 0.9)
        for sg in (0.55, 0.9):
            m = sig == sg
            put(sg, x0 + off[m, 0] * stretch, y0 + off[m, 1], bri[m])
    # highways: chains of faint dots between nearby cities
    from scipy.spatial import cKDTree
    tree = cKDTree(np.stack([cx, cy], -1))
    for i in range(n_city):
        dd, jj = tree.query([cx[i], cy[i]], k=3)
        for d_, j in zip(dd[1:], jj[1:]):
            if d_ > 160 or j < i:
                continue
            n = int(d_ / 2.5)
            tt = rng.uniform(0, 1, n)
            xs = cx[i] + (cx[j] - cx[i]) * tt + rng.normal(0, 0.7, n)
            ys = cy[i] + (cy[j] - cy[i]) * tt + rng.normal(0, 0.7, n)
            put(0.55, xs, ys, rng.uniform(0.06, 0.22, n))
    # rural dust
    idx = rng.choice(flat.size, size=160000, p=flat)
    ys, xs = np.divmod(idx, W)
    put(0.55, xs + rng.uniform(-0.5, 0.5, xs.size), ys + rng.uniform(-0.5, 0.5, ys.size), rng.uniform(0.03, 0.12, xs.size))
    out = np.zeros((H, W), np.float32)
    for sig, lst in pts.items():
        if not lst:
            continue
        a_ = np.concatenate(lst, 0)
        acc = np.zeros((H, W), np.float32)
        np.add.at(acc, (a_[:, 1].astype(int), a_[:, 0].astype(int) % W), a_[:, 2].astype(np.float32))
        out += ndimage.gaussian_filter(acc, sig, mode="wrap") * (2 * math.pi * sig * sig) ** 0.6
    # faint suburban haze around populated areas
    out += 0.05 * ndimage.gaussian_filter(out, 5.0, mode="wrap") * 6.0
    out = np.clip(out / np.percentile(out[out > 1e-4], 99.8), 0, 1)
    # stored with sRGB-like encoding; loaded as sRGB -> linear in the shader
    enc = np.where(out <= 0.0031308, out * 12.92, 1.055 * np.power(out, 1 / 2.4) - 0.055)
    Image.fromarray((np.clip(enc, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(city_p, optimize=True)
    print("aux maps %.1fs" % (time.time() - t0))
    return ocean_p, city_p


def nebula_panorama():
    """Sky panorama (linear float) with the baked-in stars removed (they would upscale into blobs)."""
    p = os.path.join(CACHE, "concept_a_nebula.npy")
    if os.path.exists(p):
        arr = np.load(p)
        if arr.shape[1] == 2048:          # cached at half resolution (it is blurred anyway)
            return arr.astype(np.float32)
    from scipy import ndimage
    img = _load_rgb(os.path.join(SKY, "space_panorama.png"))
    lin = np.where(img <= 0.04045, img / 12.92, ((img + 0.055) / 1.055) ** 2.4).astype(np.float32)
    lum = lin.mean(-1)
    med = ndimage.median_filter(lum, size=7, mode="wrap")
    star = (lum - med) > 0.004
    star = ndimage.binary_dilation(star, iterations=2)
    out = lin.copy()
    for c in range(3):
        mc = ndimage.median_filter(lin[..., c], size=9, mode="wrap")
        out[..., c] = np.where(star, mc, lin[..., c])
    out = ndimage.gaussian_filter(out, (2.0, 2.0, 0), mode="wrap")
    out = out.reshape(out.shape[0] // 2, 2, out.shape[1] // 2, 2, 3).mean((1, 3))
    os.makedirs(CACHE, exist_ok=True)
    np.save(p, out.astype(np.float16))
    return out


FB_EXT = 1.7   # half extent of the fireball noise volumes
FB = dict(freq=1.5, a1=0.55, a2=0.34, a3=0.12, bump=2.4, edge=0.05, dens=40.0, heat=0.95, center=0.50,
          soot=1.0, gain=5.0, fall=1.45, crease=0.6)


def _fb_volumes():
    sys.path.insert(0, os.path.join(ROOT, "tools", "textures"))
    from noiselib import F32, Fractal3
    vols = {}
    for name, (g, freq, octv, seed) in {"n1": (72, 1.15, 4, 101), "n2": (128, 2.7, 4, 202),
                                        "n3": (192, 6.5, 3, 303)}.items():
        ax = np.linspace(-FB_EXT, FB_EXT, g, dtype=F32)
        p = np.stack(np.meshgrid(ax, ax, ax, indexing="ij"), -1)
        vols[name] = Fractal3(seed).fbm(p, freq, octv).astype(F32)
    return vols


def _fb_sample(vol, q):
    from scipy.ndimage import map_coordinates
    g = vol.shape[0]
    idx = (q + FB_EXT) / (2 * FB_EXT) * (g - 1)
    return map_coordinates(vol, [idx[..., 0], idx[..., 1], idx[..., 2]], order=1, mode="mirror")


def _fb_ramp(tmp):
    stops = np.array([0.0, 0.12, 0.28, 0.45, 0.62, 0.80, 1.0], np.float32)
    cols = np.array([[0.0, 0.0, 0.0], [0.32, 0.025, 0.008], [0.95, 0.15, 0.018], [1.7, 0.52, 0.07],
                     [2.6, 1.25, 0.28], [3.4, 2.6, 1.2], [4.2, 4.0, 3.4]], np.float32)
    return np.stack([np.interp(tmp, stops, cols[:, c]) for c in range(3)], -1).astype(np.float32)


def fireball_texture(res=1024, steps=170):
    """Single high-resolution fireball (numpy volume ray-march, emission + lit smoke), premultiplied linear
    RGBA float. Camera at -z. Billows/temperature from three noise volumes, irregular lobes, momentum
    stretch toward the lower left, smoke rim lit from the right (sun) and from the fire inside."""
    path = os.path.join(CACHE, "concept_a_fireball_%d.npy" % res)
    if os.path.exists(path) and not DEBUG.get("fb_regen"):
        return np.load(path).astype(np.float32)
    t0 = time.time()
    v = _fb_volumes()
    rng = np.random.default_rng(42)
    R = 0.56
    lobes = []
    for k in range(7):
        d = rng.normal(0, 1, 3)
        d /= np.linalg.norm(d)
        lobes.append((d * rng.uniform(0.32, 0.5), rng.uniform(0.22, 0.34), rng.uniform(0.18, 0.32)))
    m = np.array([-0.62, -0.48, -0.62], np.float32)       # momentum: lower left, toward the camera
    m /= np.linalg.norm(m)
    L = np.array([0.80, 0.25, 0.55], np.float32)          # light from the right, behind the fireball
    L /= np.linalg.norm(L)
    ax = (np.arange(res, dtype=np.float32) + 0.5) / res * 2.2 - 1.1
    X, Y = np.meshgrid(ax, -ax)
    inside = (X * X + Y * Y) < 1.08 ** 2
    xs, ys = X[inside], Y[inside]
    n = xs.size
    zs = np.linspace(-1.1, 1.1, steps, dtype=np.float32)
    dt = np.float32(zs[1] - zs[0])
    trans = np.ones(n, np.float32)
    col = np.zeros((n, 3), np.float32)
    smoke_base = np.array([0.075, 0.068, 0.064], np.float32)
    for z in zs:
        p = np.stack([xs, ys, np.full(n, z, np.float32)], -1)
        live = trans > 0.004
        if not live.any():
            break
        pl = p[live]
        # momentum stretch (shorten along m -> the cloud is elongated along m)
        along = pl @ m
        ps = pl - np.outer(along * (1 - 1 / 1.28), m)
        r = np.sqrt((ps * ps).sum(-1)) + 1e-6
        u = r / R
        q = ps * FB["freq"]
        n1 = _fb_sample(v["n1"], q * 0.7)
        n2 = _fb_sample(v["n2"], q)
        n3 = _fb_sample(v["n3"], q * 1.3)
        ns = _fb_sample(v["n2"], q * 0.55 + 0.7)
        bill = np.abs(n2)
        fine = np.abs(n3)
        bump = np.zeros_like(u)
        for c, rad, amp in lobes:
            dd = ((pl - c) ** 2).sum(-1)
            bump += amp * np.exp(-dd / (rad * rad))
        shape = 1.0 + FB["a1"] * n1 + FB["a2"] * (bill - 0.30) + FB["a3"] * (fine - 0.3) + bump * FB["bump"] - u
        dens = np.clip(shape / FB["edge"], 0, 1) ** 1.5 * (0.5 + 1.0 * np.clip(fine * 1.6, 0, 1)) * FB["dens"]
        rr2 = pl[:, 0] ** 2 + pl[:, 1] ** 2
        tmp = FB["heat"] * (1.5 - u * FB["fall"] + 0.55 * bill + 0.2 * n1 + FB["center"] * np.clip(1.0 - rr2 / (R * R * 1.6), 0, 1))
        soot = np.clip((ns - 0.05) / 0.35, 0, 1) * np.clip((u - 0.72) / 0.3, 0, 1)
        tmp = np.clip(tmp * (1.0 - FB["soot"] * soot), 0, 1)
        emit = _fb_ramp(tmp) * (FB["gain"] * tmp ** 1.5 * (1.0 - FB["crease"] + FB["crease"] * np.clip(bill * 1.8, 0, 1)))[..., None]
        nrm = ps / r[..., None]
        lam = np.clip((nrm @ L) * 0.5 + 0.5 + 0.25 * n2, 0, 1)
        glow = np.exp(-np.maximum(u - 0.25, 0) * 2.6) * 1.2
        smoke = (smoke_base[None] * (0.10 + 0.9 * lam ** 2.0)[..., None] +
                 np.array([1.0, 0.36, 0.09], np.float32)[None] * (glow * 0.25)[..., None])
        a = 1.0 - np.exp(-dens * dt)
        tl = trans[live]
        col[live] += (tl * a)[..., None] * (smoke + emit)
        trans[live] = tl * (1.0 - a)
    alpha = 1.0 - trans
    rr = np.sqrt(xs * xs + ys * ys)
    fade = np.clip((1.06 - rr) / 0.1, 0, 1)
    out = np.zeros((res, res, 4), np.float32)
    out[inside, :3] = col * fade[..., None]
    out[inside, 3] = alpha * fade
    np.save(path, out.astype(np.float16))
    print("fireball %dpx %.1fs" % (res, time.time() - t0))
    return out


# ------------------------------------------------------------------------------------------------
# scene parts
# ------------------------------------------------------------------------------------------------
def setup_render(samples, threads):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_adaptive_sampling = True
    scn.cycles.adaptive_threshold = 0.02
    scn.cycles.use_denoising = True
    scn.cycles.denoiser = "OPENIMAGEDENOISE"
    try:
        scn.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
        scn.cycles.denoising_prefilter = "ACCURATE"
    except Exception:
        pass
    scn.cycles.max_bounces = 6
    scn.cycles.diffuse_bounces = 2
    scn.cycles.glossy_bounces = 2
    scn.cycles.transmission_bounces = 2
    scn.cycles.transparent_max_bounces = 48
    scn.cycles.caustics_reflective = False
    scn.cycles.caustics_refractive = False
    scn.cycles.sample_clamp_indirect = 6.0
    scn.cycles.light_sampling_threshold = 0.01
    scn.render.threads_mode = "FIXED"
    scn.render.threads = threads
    scn.render.film_transparent = True
    scn.render.filter_size = 1.2
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Punchy"
    scn.view_settings.exposure = 0.0
    scn.view_settings.gamma = 1.0
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGB"
    scn.render.image_settings.color_depth = "8"
    scn.render.use_compositing = True


def build_world():
    w = bpy.data.worlds.new("Space")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    # used for reflections/ambient only (camera sees the composited plate): very dark blue-violet
    bg.inputs["Color"].default_value = (0.0035, 0.0045, 0.009, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    nt.links.new(bg.outputs[0], out.inputs["Surface"])


def build_sun():
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = DEBUG.get("sun", 3.5)
    ld.angle = math.radians(0.6)
    ld.color = (1.0, 0.95, 0.88)
    ob = bpy.data.objects.new("Sun", ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_euler = (-SUN_DIR).to_track_quat("-Z", "Y").to_euler()
    return ob


def build_moonlight():
    """faint cool light from behind the cockpit: reveals clouds/coasts on the night side, soft fill on the ships"""
    ld = bpy.data.lights.new("Moon", "SUN")
    ld.energy = DEBUG.get("moon", MOON)
    ld.angle = math.radians(1.0)
    ld.color = (0.62, 0.74, 1.0)
    ob = bpy.data.objects.new("Moon", ld)
    bpy.context.scene.collection.objects.link(ob)
    d = Vector((-0.45, -0.55, 0.70)).normalized()       # direction toward the light
    ob.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return ob


def build_planet():
    ocean_p, city_p = planet_aux_maps()
    bpy.ops.mesh.primitive_uv_sphere_add(segments=512, ring_count=256, radius=PLANET_R, location=PLANET_C)
    pl = bpy.context.active_object
    pl.name = "Halcyon"
    spin = DEBUG.get("spin", PLANET_SPIN)
    tilt = DEBUG.get("tilt", PLANET_TILT)
    pl.matrix_world = (Matrix.Translation(PLANET_C) @ Matrix.Rotation(math.radians(tilt), 4, "X") @
                       Matrix.Rotation(math.radians(PLANET_ROLL), 4, "Y") @ Matrix.Rotation(math.radians(spin), 4, "Z"))
    for p in pl.data.polygons:
        p.use_smooth = True
    m = new_mat("Halcyon")
    t = Tree(m)
    uv = t.node("ShaderNodeTexCoord").outputs["UV"]
    terr = t.image(os.path.join(PLANETS, "terran.png"), uv)
    clouds = t.image(os.path.join(PLANETS, "clouds.png"), uv)
    ocean = t.image(ocean_p, uv, colorspace="Non-Color")
    city = t.image(city_p, uv, colorspace="sRGB", interp="Linear")
    ca = t.math("MULTIPLY", clouds.outputs["Alpha"], 0.92)
    # slightly richer, darker surface colours
    surf = t.node("ShaderNodeHueSaturation", {"Color": terr.outputs["Color"], "Saturation": 1.15, "Value": 0.85})
    base = t.mix(ca, surf.outputs[0], (0.85, 0.88, 0.92))
    rough = t.mixf(ca, t.mixf(ocean.outputs["Color"], 0.85, 0.32), 0.95)
    geo = t.node("ShaderNodeNewGeometry")
    nrm = t.vmath("NORMALIZE", t.vmath("SUBTRACT", geo.outputs["Position"], tuple(PLANET_C)))
    nd = t.vmath("DOT_PRODUCT", nrm, tuple(SUN_DIR))
    night = t.maprange(nd, -0.02, -0.16, 0.0, 1.0, interp="SMOOTHSTEP")
    if DEBUG.get("allnight"):
        night = 1.0
    citylum = t.math("MULTIPLY", t.math("MULTIPLY", city.outputs["Color"], night),
                     t.math("SUBTRACT", 1.0, t.math("MULTIPLY", ca, 0.85)))
    vdist = t.node("ShaderNodeCameraData").outputs["View Distance"]
    near_fade = t.maprange(vdist, 7500.0, 14500.0, DEBUG.get("cityfade", 0.22), 1.0, interp="SMOOTHSTEP")
    citylum = t.math("MULTIPLY", citylum, near_fade)
    city_col = t.rgbmul((1.0, 0.52, 0.18), t.math("MULTIPLY", citylum, DEBUG.get("city", 9.0)))
    # warm twilight band just past the terminator
    tq = t.math("DIVIDE", t.math("ADD", nd, 0.04), 0.06)
    twi = t.math("EXPONENT", t.math("MULTIPLY", t.math("MULTIPLY", tq, tq), -1.0))
    twi_col = t.rgbmul((1.0, 0.35, 0.12), t.math("MULTIPLY", twi, 0.012))
    emis = t.node("ShaderNodeMix", data_type="RGBA", blend_type="ADD")
    t.set(emis.inputs[0], 1.0)
    t.set(emis.inputs[6], city_col)
    t.set(emis.inputs[7], twi_col)
    bsdf = t.node("ShaderNodeBsdfPrincipled", {"Base Color": base, "Roughness": rough, "Specular IOR Level": 0.6,
                                               "Emission Color": emis.outputs[2], "Emission Strength": 1.0})
    t.output(bsdf.outputs[0])
    if DEBUG.get("planet_flat"):
        dbg = t.mix(t.math("MULTIPLY", citylum, 4.0), terr.outputs["Color"], (1.0, 0.0, 0.0))
        e = t.node("ShaderNodeEmission", {"Color": dbg, "Strength": 1.0})
        t.output(e.outputs[0])
    no_emission_sampling(m)
    pl.data.materials.append(m)
    return pl


def build_atmosphere():
    shell_r = PLANET_R * 1.035
    bpy.ops.mesh.primitive_uv_sphere_add(segments=384, ring_count=192, radius=shell_r, location=PLANET_C)
    at = bpy.context.active_object
    at.name = "Atmosphere"
    for p in at.data.polygons:
        p.use_smooth = True
    m = new_mat("Atmosphere")
    t = Tree(m)
    geo = t.node("ShaderNodeNewGeometry")
    pc = t.vmath("SUBTRACT", geo.outputs["Position"], tuple(PLANET_C))
    inc = geo.outputs["Incoming"]
    b = t.vmath("LENGTH", t.vmath("CROSS_PRODUCT", pc, inc))
    h = t.math("DIVIDE", t.math("SUBTRACT", b, PLANET_R), PLANET_R)          # relative ray height
    hp = t.math("MAXIMUM", h, 0.0)
    hn = t.math("MINIMUM", h, 0.0)
    thin = t.math("EXPONENT", t.math("DIVIDE", hp, -0.0014))
    wide = t.math("EXPONENT", t.math("DIVIDE", hp, -0.0070))
    outer = t.math("ADD", thin, t.math("MULTIPLY", wide, 0.28))
    inner = t.math("ADD", t.math("MULTIPLY", t.math("EXPONENT", t.math("DIVIDE", hn, 0.0035)), 0.45),
                   t.math("MULTIPLY", t.math("EXPONENT", t.math("DIVIDE", hn, 0.05)), 0.03))
    above = t.math("GREATER_THAN", h, 0.0)
    glow = t.mixf(above, inner, outer)
    # sun factor at the closest-approach point of the ray
    along = t.vmath("DOT_PRODUCT", pc, inc)
    mpt = t.vmath("NORMALIZE", t.vmath("SUBTRACT", pc, t.vmath("SCALE", inc, scale=along)))
    sd = t.vmath("DOT_PRODUCT", mpt, tuple(SUN_DIR))
    lit = t.maprange(sd, -0.30, 0.40, 0.0, 1.0, interp="SMOOTHSTEP")
    # forward scattering when looking toward the sun
    vdots = t.math("MAXIMUM", t.vmath("DOT_PRODUCT", inc, tuple(-SUN_DIR)), 0.0)
    fwd = t.math("ADD", 1.0, t.math("MULTIPLY", t.math("POWER", vdots, 6.0), 2.0))
    light = t.math("ADD", t.math("MULTIPLY", lit, fwd), 0.10)
    inten = t.math("MULTIPLY", t.math("MULTIPLY", glow, light), DEBUG.get("atmo", 3.0))
    front = t.math("SUBTRACT", 1.0, geo.outputs["Backfacing"])
    inten = t.math("MULTIPLY", inten, front)
    col = t.mix(t.math("POWER", thin, 1.5), (0.03, 0.22, 1.0), CYAN)
    # warm sunset layer: low in the atmosphere (just above the limb) where the terminator crosses it
    sq = t.math("DIVIDE", t.math("SUBTRACT", sd, 0.03), 0.16)
    term = t.math("EXPONENT", t.math("MULTIPLY", t.math("MULTIPLY", sq, sq), -1.0))
    low = t.math("EXPONENT", t.math("DIVIDE", hp, -0.0013))
    warm = t.math("MULTIPLY", t.math("MULTIPLY", term, low), t.math("MULTIPLY", above, DEBUG.get("sunset", 1.0)))
    col = t.mix(warm, col, (1.0, 0.36, 0.08))
    em = t.node("ShaderNodeEmission", {"Color": col, "Strength": inten})
    tr = t.node("ShaderNodeBsdfTransparent")
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], tr.outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(m)
    at.data.materials.append(m)
    camera_only(at)
    return at


# ------------------------------------------------------------------------------------------------
# fighters, plumes, lasers, explosion
# ------------------------------------------------------------------------------------------------
def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    return [o for o in bpy.data.objects if o not in before]


def set_emission(m, strength=None, color=None):
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            if strength is not None:
                n.inputs["Emission Strength"].default_value = strength
            if color is not None:
                n.inputs["Emission Color"].default_value = (*color, 1.0)
            return n


def fighter_proto():
    new = import_glb("fighter")
    ob = next(o for o in new if o.type == "MESH")
    engines = [o.location.copy() for o in new if o.name.startswith("Engine")]
    for o in new:
        if o is not ob:
            bpy.data.objects.remove(o)
    for m in ob.data.materials:
        if m.name.startswith("Hull") and not m.name.startswith("HullDark"):
            bsdf = set_emission(m)
            nt = m.node_tree
            tc = nt.nodes.new("ShaderNodeTexCoord")
            nz = nt.nodes.new("ShaderNodeTexNoise")
            nz.inputs["Scale"].default_value = 3.5
            nz.inputs["Detail"].default_value = 8.0
            nz.inputs["Roughness"].default_value = 0.6
            nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
            mr = nt.nodes.new("ShaderNodeMapRange")
            mr.inputs["From Min"].default_value = 0.3
            mr.inputs["From Max"].default_value = 0.7
            nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
            cr = nt.nodes.new("ShaderNodeMix")
            cr.data_type = "RGBA"
            nt.links.new(mr.outputs["Result"], cr.inputs[0])
            cr.inputs[6].default_value = (0.12, 0.122, 0.135, 1.0)
            cr.inputs[7].default_value = (0.20, 0.205, 0.22, 1.0)
            nt.links.new(cr.outputs[2], bsdf.inputs["Base Color"])
            rr = nt.nodes.new("ShaderNodeMapRange")
            rr.inputs["To Min"].default_value = 0.52
            rr.inputs["To Max"].default_value = 0.34
            nt.links.new(mr.outputs["Result"], rr.inputs["Value"])
            nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
        if m.name.startswith("Accent"):
            set_emission(m, 9.0)
        elif m.name.startswith("Glow"):
            set_emission(m, 40.0, (1.0, 0.55, 0.16))
        elif m.name.startswith("Glass"):
            set_emission(m, 1.3, (1.0, 0.10, 0.025))
    me = ob.data
    bpy.data.objects.remove(ob)
    return me, engines


def heading_matrix(fwd, bank_deg):
    F = Vector(fwd).normalized()
    R = F.cross(Vector((0, 0, 1))).normalized()
    U = R.cross(F)
    rot = Matrix((R, F, U)).transposed()
    return Matrix.Rotation(math.radians(bank_deg), 3, F) @ rot


def plume_mesh(name, length, r0, r1, sides=20):
    bm = B.bm_cyl((0, 0, 0), (0, -length, 0), r0, r1, sides=sides, cap=False)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me


def plume_material(name, color_hot, color_cool, strength, along_pow, edge_pow):
    m = new_mat(name)
    t = Tree(m)
    gen = t.node("ShaderNodeTexCoord").outputs["Generated"]
    gy = t.node("ShaderNodeSeparateXYZ", {"Vector": gen}).outputs["Y"]      # 1 at the nozzle, 0 at the tail
    along = t.math("POWER", gy, along_pow)
    lw = t.node("ShaderNodeLayerWeight", {"Blend": 0.5})
    soft = t.math("POWER", t.math("SUBTRACT", 1.0, lw.outputs["Facing"]), edge_pow)
    col = t.mix(t.math("POWER", gy, 3.0), color_cool, color_hot)
    em = t.node("ShaderNodeEmission", {"Color": col, "Strength": t.math("MULTIPLY", t.math("MULTIPLY", along, soft), strength)})
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], t.node("ShaderNodeBsdfTransparent").outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(m)
    return m


def add_object(name, me, matrix, camera_fx=False):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = matrix
    if camera_fx:
        camera_only(ob)
    return ob


def build_fighters(layout):
    me, engines = fighter_proto()
    core = plume_mesh("PlumeCore", 2.6, 0.26, 0.06)
    core.materials.append(plume_material("PlumeCore", (1.0, 0.85, 0.55), (1.0, 0.42, 0.08), 45.0, 1.6, 1.5))
    halo = plume_mesh("PlumeHalo", 6.5, 0.5, 0.12)
    halo.materials.append(plume_material("PlumeHalo", (1.0, 0.55, 0.15), (1.0, 0.22, 0.03), 5.0, 2.2, 2.5))
    trail = plume_mesh("PlumeTrail", 24.0, 0.24, 0.02, sides=12)
    trail.materials.append(plume_material("PlumeTrail", (1.0, 0.45, 0.10), (0.9, 0.12, 0.02), 0.9, 1.8, 2.0))
    obs = []
    for i, f in enumerate(layout["fighters"]):
        if f["hit"]:
            continue
        pos, bank, ps = f["pos"], f["bank"], f["plume"]
        rot = heading_matrix(FLIGHT, bank).to_4x4()
        M = Matrix.Translation(pos) @ rot
        ob = add_object("Fighter_%d" % i, me, M)
        obs.append(ob)
        for e in engines:
            PM = M @ Matrix.Translation(e + Vector((0, -0.02, 0)))
            add_object("PlumeCore_%d" % i, core, PM @ Matrix.Scale(ps ** 0.5, 4), True)
            add_object("PlumeHalo_%d" % i, halo, PM @ Matrix.Scale(ps, 4), True)
            add_object("PlumeTrail_%d" % i, trail, PM @ Matrix.Diagonal((ps, ps * 1.2, ps, 1)), True)
    return obs


def beam_material(name, color, strength, edge_pow, ramp=None):
    """additive glowing tube; ramp=(d0, d1, f0): strength scaled from f0 at view distance d0 to 1 at d1"""
    m = new_mat(name)
    t = Tree(m)
    lw = t.node("ShaderNodeLayerWeight", {"Blend": 0.5})
    soft = t.math("POWER", t.math("SUBTRACT", 1.0, lw.outputs["Facing"]), edge_pow)
    if ramp is not None:
        vd = t.node("ShaderNodeCameraData").outputs["View Distance"]
        soft = t.math("MULTIPLY", soft, t.maprange(vd, ramp[0], ramp[1], ramp[2], 1.0, interp="SMOOTHSTEP"))
    em = t.node("ShaderNodeEmission", {"Color": color, "Strength": t.math("MULTIPLY", soft, strength)})
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], t.node("ShaderNodeBsdfTransparent").outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(m)
    return m


def build_lasers(starts, target):
    core_m = beam_material("LaserCore", (0.35, 0.92, 1.0), DEBUG.get("laser", 24.0), 1.2, ramp=(3.0, 30.0, 0.6))
    glow_m = beam_material("LaserGlow", CYAN, DEBUG.get("laserglow", 2.4), 2.5, ramp=(3.0, 30.0, 0.45))
    for i, a in enumerate(starts):
        a = Vector(a)
        d = (Vector(target) - a)
        b = a + d * 0.995
        for nm, m, r0, r1 in (("LaserCore", core_m, 0.010, 0.040), ("LaserGlow", glow_m, 0.035, 0.16)):
            me = bpy.data.meshes.new(nm)
            bm = B.bm_cyl(a, b, r0, r1, sides=24, cap=False)
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = True
            me.materials.append(m)
            add_object("%s_%d" % (nm, i), me, Matrix.Identity(4), True)
        # cyan light spill near the target end of each beam
        for k, f in enumerate((0.70, 0.85)):
            ld = bpy.data.lights.new("LaserLight", "POINT")
            ld.energy = 900.0
            ld.color = (0.35, 0.9, 1.0)
            ld.shadow_soft_size = 0.3
            lo = bpy.data.objects.new("LaserLight_%d_%d" % (i, k), ld)
            bpy.context.scene.collection.objects.link(lo)
            lo.location = a + d * f


def debris_material():
    m = new_mat("DebrisHull")
    t = Tree(m)
    obj = t.node("ShaderNodeTexCoord").outputs["Object"]
    n = t.node("ShaderNodeTexNoise", {"Vector": obj, "Scale": 2.2, "Detail": 6.0, "Roughness": 0.6}).outputs["Fac"]
    char = t.maprange(n, 0.42, 0.62, 0.0, 1.0)
    base = t.mix(char, (0.075, 0.075, 0.08), (0.012, 0.011, 0.011))
    ember = t.math("POWER", t.maprange(n, 0.60, 0.75, 0.0, 1.0), 2.0)
    bsdf = t.node("ShaderNodeBsdfPrincipled", {"Base Color": base, "Metallic": 0.5, "Roughness": 0.55,
                                               "Emission Color": (1.0, 0.32, 0.05),
                                               "Emission Strength": t.math("MULTIPLY", ember, 7.0)})
    t.output(bsdf.outputs[0])
    return m


def float_image(name, arr):
    """bpy float image from a top-down (H, W, 3|4) linear array; channels kept as they are."""
    H, W, C = arr.shape
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, W, H, alpha=True, float_buffer=True)
    if C == 3:
        arr = np.concatenate([arr, np.ones((H, W, 1), np.float32)], -1)
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1], dtype=np.float32).ravel())
    img.alpha_mode = "CHANNEL_PACKED"
    return img


def card_mesh(name):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    vs = [bm.verts.new(c) for c in ((-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0))]
    f = bm.faces.new(vs)
    for loop, c in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = c
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def card_material(name, img, gain, contrast=1.0, sat=1.0):
    """premultiplied RGBA card: background * (1 - alpha) + rgb * gain"""
    m = new_mat(name)
    t = Tree(m)
    tex = t.node("ShaderNodeTexImage", image=img, interpolation="Cubic", extension="CLIP")
    t.set(tex.inputs["Vector"], t.node("ShaderNodeTexCoord").outputs["UV"])
    inv = t.math("SUBTRACT", 1.0, tex.outputs["Alpha"])
    tr = t.node("ShaderNodeBsdfTransparent", {"Color": t.node("ShaderNodeCombineColor", {"Red": inv, "Green": inv, "Blue": inv}).outputs[0]})
    col = tex.outputs["Color"]
    if contrast != 1.0:     # expand the fire's dynamic range: hot parts hotter, embers/soot darker
        col = t.node("ShaderNodeGamma", {"Color": col, "Gamma": contrast}).outputs[0]
    if sat != 1.0:
        col = t.node("ShaderNodeHueSaturation", {"Color": col, "Saturation": sat}).outputs[0]
    em = t.node("ShaderNodeEmission", {"Color": col, "Strength": gain})
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], tr.outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(m)
    return m


def facing_matrix(pos, look_from, size, roll_deg=0.0):
    n = (Vector(look_from) - Vector(pos)).normalized()
    up = Vector((0, 0, 1))
    y = (up - n * up.dot(n)).normalized()
    x = y.cross(n)
    rot = Matrix((x, y, n)).transposed()
    rot = Matrix.Rotation(math.radians(roll_deg), 3, n) @ rot
    return Matrix.Translation(pos) @ rot.to_4x4() @ Matrix.Scale(size, 4)


def build_explosion(center, fwd, seed=3):
    rnd = np.random.default_rng(seed)
    C = Vector(center)
    F = Vector(fwd).normalized()
    eye = Vector((0, 0, 0))                 # all cockpit cameras sit near the origin
    fb = fireball_texture(1024, 160)
    img = float_image("Fireball", fb)
    me = card_mesh("FireCard")
    me.materials.append(card_material("FireCard", img, DEBUG.get("fire", 0.40), DEBUG.get("fcon", 1.5),
                                      DEBUG.get("fsat", 1.2)))
    # main fireball (texture spans 2.2 units, fireball radius ~0.6 units)
    add_object("Fireball", me, facing_matrix(C, eye, 6.2, 0.0), True)
    # burning fragments flung outward (smaller rotated copies)
    for k, (off, sz, roll) in enumerate((((-3.6, 2.2, -2.6), 1.15, 70.0), ((4.2, 0.5, 1.6), 0.95, 160.0),
                                          ((1.0, -1.5, 3.9), 0.8, 250.0))):
        p = C + Vector(off)
        add_object("Fragment_%d" % k, me, facing_matrix(p, eye, sz, roll), True)
    # white-hot flash at the heart: soft radial glow card (two gaussians) just in front of the fireball
    cm = new_mat("Flash")
    t = Tree(cm)
    uv = t.node("ShaderNodeTexCoord").outputs["UV"]
    sep = t.node("ShaderNodeSeparateXYZ", {"Vector": uv})
    dx = t.math("SUBTRACT", sep.outputs["X"], 0.5)
    dy = t.math("SUBTRACT", sep.outputs["Y"], 0.5)
    r2 = t.math("ADD", t.math("MULTIPLY", dx, dx), t.math("MULTIPLY", dy, dy))
    g1 = t.math("EXPONENT", t.math("MULTIPLY", r2, -260.0))
    g2 = t.math("EXPONENT", t.math("MULTIPLY", r2, -28.0))
    inten = t.math("ADD", t.math("MULTIPLY", g1, DEBUG.get("core", 40.0)), t.math("MULTIPLY", g2, 1.6))
    em = t.node("ShaderNodeEmission", {"Color": (1.0, 0.80, 0.55), "Strength": inten})
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], t.node("ShaderNodeBsdfTransparent").outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(cm)
    toward = (eye - C).normalized()
    fme = card_mesh("FlashCard")
    fme.materials.append(cm)
    add_object("Flash", fme, facing_matrix(C + toward * 3.6, eye, 3.2), True)
    # sparks: hot streaks, mostly carried along the flight direction
    sm = new_mat("Spark")
    t = Tree(sm)
    lw = t.node("ShaderNodeLayerWeight", {"Blend": 0.5})
    soft = t.math("POWER", t.math("SUBTRACT", 1.0, lw.outputs["Facing"]), 1.0)
    rnd_isl = t.node("ShaderNodeNewGeometry").outputs["Random Per Island"]
    strength = t.math("MULTIPLY", soft, t.math("ADD", 4.0, t.math("MULTIPLY", t.math("POWER", rnd_isl, 2.0), 36.0)))
    em = t.node("ShaderNodeEmission", {"Color": (1.0, 0.60, 0.20), "Strength": strength})
    add = t.node("ShaderNodeAddShader")
    t.set(add.inputs[0], t.node("ShaderNodeBsdfTransparent").outputs[0])
    t.set(add.inputs[1], em.outputs[0])
    t.output(add.outputs[0])
    no_emission_sampling(sm)
    bm = bmesh.new()
    for k in range(int(DEBUG.get("sparks", 28))):
        d = Vector(rnd.normal(0, 1, 3)).normalized()
        if k % 4 == 0:
            d = (d * 0.9 + F * 0.6).normalized()
        r0 = rnd.uniform(3.2, 7.5)
        ln = rnd.uniform(0.25, 0.9) * r0 * 0.16
        p0 = C + d * r0
        p1 = p0 + d * ln
        B.merge_bm(bm, B.bm_cyl(p1, p0, rnd.uniform(0.012, 0.026), 0.003, sides=6, cap=False))
    me = bpy.data.meshes.new("Sparks")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(sm)
    add_object("Sparks", me, Matrix.Identity(4), True)
    # light
    ld = bpy.data.lights.new("ExplosionLight", "POINT")
    ld.energy = DEBUG.get("xlight", 15000.0)
    ld.color = (1.0, 0.52, 0.18)
    ld.shadow_soft_size = 3.0
    lo = bpy.data.objects.new("ExplosionLight", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = C + toward * 1.5


def build_station(pos, look_from, roll=0.0, scale=1.0):
    new = import_glb("station")
    hub = next(o for o in new if o.name.startswith("Hub"))
    ring = next(o for o in new if o.name.startswith("Ring"))
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    for m in bpy.data.materials:
        if m.name.startswith("Windows"):
            set_emission(m, 6.0)
        elif m.name.startswith("Glow."):
            set_emission(m, 10.0)
    # front (dock port, +Y) turned partly toward the viewer, ring tilted for an elliptical read
    d = (Vector(look_from) - Vector(pos)).normalized()
    fwd = Matrix.Rotation(math.radians(58.0), 3, "Z") @ d
    fwd = (fwd + Vector((0, 0, 0.35))).normalized()
    rot = heading_matrix(fwd, roll).to_4x4()
    M = Matrix.Translation(pos) @ rot @ Matrix.Scale(scale, 4)
    for o in (hub, ring):
        o.matrix_world = M
    ring.matrix_world = M @ Matrix.Rotation(math.radians(20.0), 4, "Y")
    for o in (hub, ring):
        o.visible_shadow = False
    return hub, ring


def build_debris(center, fwd, seed=9):
    """The destroyed fighter: loose parts of a fighter copy flung outward and tumbling."""
    rnd = np.random.default_rng(seed)
    C = Vector(center)
    F = Vector(fwd).normalized()
    new = import_glb("fighter")
    ob = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not ob:
            bpy.data.objects.remove(o)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # loose parts
    bm.verts.ensure_lookup_table()
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.link_edges:
                o2 = e.other_vert(x)
                if o2.index not in seen:
                    seen.add(o2.index)
                    stack.append(o2)
        parts.append(comp)
    bm.free()
    parts.sort(key=len, reverse=True)
    rot0 = heading_matrix(F, -20.0)
    dm = debris_material()
    keep = []
    me = ob.data
    co = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    for k, comp in enumerate(parts[:40]):
        cen = Vector(co[comp].mean(0))
        size = float(np.ptp(co[comp], 0).max())
        if size < 0.5:
            continue
        keep.append((comp, cen, size))
    keep = [k for k in keep if k[2] < 3.4]
    for k, (comp, cen, size) in enumerate(keep[:10]):
        # duplicate the object and delete everything except this component
        nob = ob.copy()
        nob.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(nob)
        bm = bmesh.new()
        bm.from_mesh(nob.data)
        bm.verts.ensure_lookup_table()
        keepset = set(comp)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keepset], context="VERTS")
        bmesh.ops.translate(bm, vec=-cen, verts=bm.verts)
        bm.to_mesh(nob.data)
        bm.free()
        d = (rot0 @ cen)
        d = (d.normalized() if d.length > 1e-3 else Vector(rnd.normal(0, 1, 3)).normalized())
        dist = rnd.uniform(4.5, 9.0)
        pos = C + d * dist + F * rnd.uniform(1.0, 4.0) + Vector(rnd.normal(0, 0.8, 3))
        rot = (Euler(rnd.uniform(-1.4, 1.4, 3)).to_matrix() @ rot0).to_4x4()
        nob.matrix_world = Matrix.Translation(pos) @ rot
        mats = [nob.material_slots[p.material_index].material.name for p in nob.data.polygons]
        if sum(m.startswith("Glass") for m in mats) > 0.3 * len(mats):
            bpy.data.objects.remove(nob)      # the glowing canopy reads as a pink blob -> drop it
            continue
        for i, sl in enumerate(nob.material_slots):
            if sl.material and sl.material.name.startswith("Hull") and not sl.material.name.startswith("HullDark"):
                nob.material_slots[i].link = "OBJECT"
                nob.material_slots[i].material = dm
    bpy.data.objects.remove(ob)


# ------------------------------------------------------------------------------------------------
# cameras / screen space helpers
# ------------------------------------------------------------------------------------------------
def cam_rotation(yaw, pitch, roll):
    return (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(90 + pitch), 4, "X") @
            Matrix.Rotation(math.radians(roll), 4, "Z"))


def resolve_framing(fr):
    """Fill in yaw/pitch when a framing asks to put the explosion at screen (u, v) (with a roll)."""
    fr = dict(fr)
    if "aim" not in fr:
        return fr
    u, v, roll = fr["aim"]
    T = world_layout()["explosion"]
    d = T - Vector(fr["cam"])
    az = math.degrees(math.atan2(d.x, d.y))
    el = math.degrees(math.atan2(d.z, math.hypot(d.x, d.y)))
    W, H = fr["res"]
    th = math.tan(math.radians(fr["hfov"]) / 2)
    tv = th * H / W
    ax = math.degrees(math.atan((u - 0.5) * 2 * th))
    ay = math.degrees(math.atan((0.5 - v) * 2 * tv))
    r = math.radians(roll)
    ax, ay = ax * math.cos(r) - ay * math.sin(r), ax * math.sin(r) + ay * math.cos(r)
    fr["ypr"] = (-az + ax, el - ay, roll)
    return fr


def world_layout():
    hero = FRAMINGS["hero"]
    p0 = screen_point(hero, hero["res"], *LEADER)
    F = FLIGHT
    R = F.cross(Vector((0, 0, 1))).normalized()
    U = R.cross(F)
    fighters = []
    for i, (lat, back, up, bank, ps) in enumerate(FORMATION):
        pos = p0 + R * lat - F * back + U * up
        fighters.append(dict(pos=pos, bank=bank, plume=ps, hit=(i == EXPLODES)))
    for (u, v, d, bank) in DISTANT:
        fighters.append(dict(pos=screen_point(hero, hero["res"], u, v, d), bank=bank, plume=3.0, hit=False))
    return dict(explosion=fighters[EXPLODES]["pos"], fighters=fighters,
                station=screen_point(hero, hero["res"], *STATION))


def build_fill(fr):
    """soft cool fill from behind the cockpit so the fighters' fronts are not pitch black (falls off before the planet)"""
    ld = bpy.data.lights.new("Fill", "AREA")
    ld.shape = "DISK"
    ld.size = 30.0
    ld.energy = DEBUG.get("fill", 1500.0)
    ld.color = (0.55, 0.7, 1.0)
    lo = bpy.data.objects.new("Fill", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = Vector(fr["cam"]) + Vector((-6.0, -12.0, 8.0))
    tgt = world_layout()["explosion"]
    lo.rotation_euler = (tgt - lo.location).to_track_quat("-Z", "Y").to_euler()


def build_camera(name, fr):
    cd = bpy.data.cameras.new(name)
    cd.sensor_fit = "HORIZONTAL"
    cd.sensor_width = 36.0
    cd.lens = 18.0 / math.tan(math.radians(fr["hfov"]) / 2)
    cd.clip_start = 0.05
    cd.clip_end = 2.0e6
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = Matrix.Translation(Vector(fr["cam"])) @ cam_rotation(*fr["ypr"])
    return ob


def screen_point(cam, res, u, v, depth):
    """World position of normalized frame coords (u right, v down, 0..1) at a distance along the view axis."""
    W, H = res
    hw = depth * math.tan(math.radians(cam["hfov"]) / 2)
    hh = hw * H / W
    local = Vector(((u - 0.5) * 2 * hw, (0.5 - v) * 2 * hh, -depth))
    return Matrix.Translation(Vector(cam["cam"])) @ cam_rotation(*cam["ypr"]) @ local


# ------------------------------------------------------------------------------------------------
# background plate (numpy) + compositor
# ------------------------------------------------------------------------------------------------
def make_plate(fr, res, seed=5):
    W, H = res
    pano = nebula_panorama()
    PH, PW, _ = pano.shape
    # nebula at quarter resolution
    w4, h4 = max(W // 4, 8), max(H // 4, 8)
    uu = (np.arange(w4) + 0.5) / w4
    vv = (np.arange(h4) + 0.5) / h4
    U, V = np.meshgrid(uu, vv)
    t = math.tan(math.radians(fr["hfov"]) / 2)
    x = (U - 0.5) * 2 * t
    y = (0.5 - V) * 2 * t * H / W
    z = -np.ones_like(x)
    R = np.array(cam_rotation(*fr["ypr"]).to_3x3())
    d = np.stack([x, y, z], -1) @ R.T
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    # Blender equirect convention
    pu = (np.arctan2(d[..., 1], -d[..., 0]) / (2 * math.pi) + 0.5 + NEBULA_SHIFT) % 1.0
    pv = np.arctan2(d[..., 2], np.hypot(d[..., 0], d[..., 1])) / math.pi + 0.5
    from scipy import ndimage
    px = pu * PW - 0.5
    py = (1.0 - pv) * PH - 0.5
    neb = np.stack([ndimage.map_coordinates(pano[..., c], [py, px], order=1, mode="grid-wrap") for c in range(3)], -1)
    neb = np.stack([np.asarray(Image.fromarray(neb[..., c].astype(np.float32)).resize((W, H), Image.BICUBIC))
                    for c in range(3)], -1)
    neb = np.clip(neb, 0, None) * DEBUG.get("neb", NEBULA_GAIN)
    # crisp stars (normalized positions -> identical pattern at preview and final size)
    rng = np.random.default_rng(seed)
    area = (2 * t) * (2 * t * H / W)
    n = int(DEBUG.get("stars", 5200) * area)
    su = rng.uniform(0, 1, n)
    sv = rng.uniform(0, 1, n)
    mag = rng.pareto(1.6, n) + 1.0
    bri = np.clip(0.004 * mag ** 1.5, 0, 3.0)
    temp = rng.uniform(0, 1, n)
    cols = np.stack([0.8 + 0.25 * temp, 0.85 + 0.1 * temp, 1.05 - 0.25 * temp], -1)
    k = W / float(fr["res"][0])           # star size scales with the output resolution (1.0 at preview size)
    img = neb.copy()
    acc = np.zeros((H, W, 3), np.float32)
    fx = su * W - 0.5
    fy = sv * H - 0.5
    x0 = np.floor(fx).astype(int)
    y0 = np.floor(fy).astype(int)
    ax = fx - x0
    ay = fy - y0
    for dx, dy, wgt in ((0, 0, (1 - ax) * (1 - ay)), (1, 0, ax * (1 - ay)), (0, 1, (1 - ax) * ay), (1, 1, ax * ay)):
        xi = np.clip(x0 + dx, 0, W - 1)
        yi = np.clip(y0 + dy, 0, H - 1)
        for c in range(3):
            np.add.at(acc[..., c], (yi, xi), (bri * wgt * cols[:, c]).astype(np.float32))
    # point sources: at higher output resolution keep them crisp (sigma ~ sqrt(k)) and brighter (x k)
    sig = 0.55 * math.sqrt(k)
    stars = ndimage.gaussian_filter(acc, (sig, sig, 0)) * k
    halo = ndimage.gaussian_filter(acc, (2.5 * k, 2.5 * k, 0)) * 0.6
    img += stars + halo
    return img.astype(np.float32)


def plate_image(name, arr):
    H, W, _ = arr.shape
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, W, H, alpha=True, float_buffer=True)
    rgba = np.concatenate([arr, np.ones((H, W, 1), np.float32)], -1)[::-1]  # bottom-up
    img.pixels.foreach_set(rgba.ravel())
    return img


def make_vignette(res, strength=0.42, power=2.4):
    W, H = res
    x = (np.arange(W) + 0.5) / W - 0.5
    y = (np.arange(H) + 0.5) / H - 0.5
    X, Y = np.meshgrid(x, y)
    a = W / H
    r = np.sqrt((X * min(a, 1.6)) ** 2 + Y ** 2) / math.sqrt((0.5 * min(a, 1.6)) ** 2 + 0.25)
    v = 1.0 - strength * np.clip(r, 0, 1) ** power
    return np.repeat(v[..., None], 3, -1).astype(np.float32)


def build_compositor(plate, vignette=None):
    scn = bpy.context.scene
    ng = bpy.data.node_groups.new("Comp", "CompositorNodeTree")
    scn.compositing_node_group = ng
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    N = ng.nodes
    L = ng.links
    rl = N.new("CompositorNodeRLayers")
    im = N.new("CompositorNodeImage")
    im.image = plate
    ao = N.new("CompositorNodeAlphaOver")
    ao.inputs["Straight Alpha"].default_value = False
    L.new(im.outputs["Image"], ao.inputs["Background"])
    L.new(rl.outputs["Image"], ao.inputs["Foreground"])
    fog = N.new("CompositorNodeGlare")
    fog.inputs["Type"].default_value = "Fog Glow"
    fog.inputs["Quality"].default_value = "High"
    fog.inputs["Threshold"].default_value = 1.2
    fog.inputs["Strength"].default_value = DEBUG.get("fog", 0.3)
    fog.inputs["Size"].default_value = 0.75
    L.new(ao.outputs[0], fog.inputs["Image"])
    bloom = N.new("CompositorNodeGlare")
    bloom.inputs["Type"].default_value = "Bloom"
    bloom.inputs["Quality"].default_value = "High"
    bloom.inputs["Threshold"].default_value = 0.9
    bloom.inputs["Strength"].default_value = DEBUG.get("bloom", 0.2)
    bloom.inputs["Size"].default_value = 0.85
    L.new(fog.outputs["Image"], bloom.inputs["Image"])
    last = bloom.outputs["Image"]
    if DEBUG.get("streaks", STREAKS) > 0:
        st = N.new("CompositorNodeGlare")       # subtle anamorphic streak on the hottest cores only
        st.inputs["Type"].default_value = "Streaks"
        st.inputs["Quality"].default_value = "High"
        st.inputs["Threshold"].default_value = 6.0
        st.inputs["Strength"].default_value = DEBUG.get("streaks", STREAKS)
        st.inputs["Streaks"].default_value = 2
        st.inputs["Streaks Angle"].default_value = 0.0
        st.inputs["Fade"].default_value = 0.965
        st.inputs["Iterations"].default_value = 5
        st.inputs["Color Modulation"].default_value = 0.1
        st.inputs["Tint"].default_value = (0.55, 0.85, 1.0, 1.0)
        L.new(last, st.inputs["Image"])
        last = st.outputs["Image"]
    if vignette is not None:
        vi = N.new("CompositorNodeImage")
        vi.image = vignette
        mx = N.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs[0].default_value = 1.0
        L.new(last, mx.inputs[6])
        L.new(vi.outputs["Image"], mx.inputs[7])
        last = mx.outputs[2]
    out = N.new("NodeGroupOutput")
    L.new(last, out.inputs[0])
    return ng


# ------------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------------
def render_framing(key, args):
    fr = resolve_framing(FRAMINGS[key])
    res = fr["final"] if args.final else fr["res"]
    res = (int(res[0] * args.scale), int(res[1] * args.scale))
    B.reset()
    update_sun()
    samples = args.samples or (192 if args.final else 64)
    threads = args.threads or (4 if args.final else 2)
    setup_render(samples, threads)
    scn = bpy.context.scene
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.resolution_percentage = 100
    build_world()
    build_sun()
    build_moonlight()
    build_planet()
    if not args.no_atmo:
        build_atmosphere()
    cam = build_camera("Cam_" + key, fr)
    scn.camera = cam
    L = world_layout()
    if not DEBUG.get("no_action"):
        build_fighters(L)
        build_explosion(L["explosion"], FLIGHT)
        build_debris(L["explosion"], FLIGHT)
        starts = [screen_point(fr, fr["res"], u, v, 2.5) for (u, v) in fr["beams"]]
        build_lasers(starts, L["explosion"])
        build_fill(fr)
        if not DEBUG.get("no_station"):
            build_station(L["station"], Vector(fr["cam"]), roll=25.0)
    t0 = time.time()
    plate = plate_image("Plate_" + key, make_plate(fr, res))
    vig = plate_image("Vignette_" + key, make_vignette(res, DEBUG.get("vig", VIGNETTE)))
    build_compositor(plate, vig)
    print("plate %.1fs" % (time.time() - t0))
    out = os.path.join(args.out, "concept_a_%s.png" % key)
    scn.render.filepath = out
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    dt = time.time() - t0
    print("RENDERED %s %dx%d samples=%d threads=%d in %.1fs -> %s" % (key, res[0], res[1], samples, threads, dt, out))
    if args.final and args.scale == 1.0:
        # Steam also wants the 1x sizes (1920x620 hero, 920x430 header, 600x900 capsule): Lanczos downscale
        small = fr["res"]
        p1 = os.path.join(args.out, "concept_a_%s_%dx%d.png" % (key, small[0], small[1]))
        Image.open(out).convert("RGB").resize(small, Image.LANCZOS).save(p1, optimize=True)
        print("  1x ->", p1)
    return dt


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--final", action="store_true")
    ap.add_argument("--only", default="hero,wide,portrait")
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--threads", type=int, default=0)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--out", default="")
    ap.add_argument("--no-atmo", action="store_true")
    ap.add_argument("--debug", default="")
    args = ap.parse_args(argv)
    for kv in filter(None, args.debug.split(",")):
        k, _, v = kv.partition("=")
        DEBUG[k] = float(v) if v else True
    if not args.out:
        args.out = os.path.join(HERE, "final" if args.final else "previews")
    os.makedirs(args.out, exist_ok=True)
    times = {}
    for key in args.only.split(","):
        times[key] = render_framing(key.strip(), args)
    print("TIMES", {k: round(v, 1) for k, v in times.items()})


if __name__ == "__main__":
    main()
