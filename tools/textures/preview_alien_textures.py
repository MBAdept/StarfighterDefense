"""
preview_alien_textures.py - QA previews for the alien-system textures.
Run:  /opt/tools/venv/bin/python tools/textures/preview_alien_textures.py
Writes to tools/textures/previews/:
  alien_planets_sheet.png   flat equirect maps (albedo + emission maps)
  alien_planets_spheres.png planets rendered as spheres like shaders/planet.gdshader does (sun-lit day side,
                            emission on the night side), tilted 35 deg so a pole is visible (pinch check),
                            and rotated so the u=0/1 seam faces the camera (seam check)
  alien_textures_sheet.png  overview: spheres + enemy sky panorama + enemy map background
Also prints a numeric seam check (left/right edge difference vs. typical neighbouring-column difference).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noiselib import linear_from_srgb, srgb_from_linear, smoothstep  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PL = os.path.join(ROOT, "assets", "textures", "planets")
PREV = os.path.join(ROOT, "tools", "textures", "previews")
PLANETS = ["alien_crimson", "alien_spore", "alien_ash", "alien_crystal", "alien_home"]
EMIS = {"alien_ash": "alien_ash_emission", "alien_home": "alien_home_emission"}


def load_lin(name):
    a = np.asarray(Image.open(os.path.join(PL, name + ".png")).convert("RGB"), np.float32) / 255.0
    return linear_from_srgb(a).astype(np.float32)


def sample(tex, lon, lat):
    h, w = tex.shape[:2]
    u = (lon + np.pi) / (2 * np.pi) * w - 0.5
    v = (np.pi / 2 - lat) / np.pi * h - 0.5
    u0 = np.floor(u).astype(int)
    v0 = np.clip(np.floor(v).astype(int), 0, h - 1)
    v1 = np.clip(v0 + 1, 0, h - 1)
    fu = (u - u0)[..., None]
    fv = np.clip(v - np.floor(v), 0, 1)[..., None]
    u0w, u1w = u0 % w, (u0 + 1) % w
    a = tex[v0, u0w] * (1 - fu) + tex[v0, u1w] * fu
    b = tex[v1, u0w] * (1 - fu) + tex[v1, u1w] * fu
    return a * (1 - fv) + b * fv


def sphere(alb, emis, size=300, tilt=35.0, spin=180.0, sun=(-0.55, 0.35, 0.76)):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    x = (xs + 0.5) / size * 2 - 1
    y = 1 - (ys + 0.5) / size * 2
    r2 = x * x + y * y
    inside = r2 <= 1.0
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    n = np.stack([x, y, z], -1)                         # view space, +z toward the camera
    t = np.radians(tilt)
    rx = np.array([[1, 0, 0], [0, np.cos(t), -np.sin(t)], [0, np.sin(t), np.cos(t)]], np.float32)
    s = np.radians(spin)
    ry = np.array([[np.cos(s), 0, np.sin(s)], [0, 1, 0], [-np.sin(s), 0, np.cos(s)]], np.float32)
    d = n @ rx @ ry                                     # planet space, +y = north
    lon = np.arctan2(d[..., 0], -d[..., 2])
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    base = sample(alb, lon, lat)
    L = np.array(sun, np.float32)
    L /= np.linalg.norm(L)
    ndl = n @ L
    day = smoothstep(-0.12, 0.25, ndl)
    col = base * (0.03 + 0.95 * np.maximum(ndl, 0) * day + 0.04 * day)[..., None]
    if emis is not None:
        col = col + sample(emis, lon, lat) * ((1 - day * 0.6) * 1.8)[..., None]
    fres = (1 - np.clip(z, 0, 1)) ** 3
    col = col + np.array([0.5, 0.25, 0.55], np.float32) * (fres * 0.25)[..., None]
    col = col / (1 + 0.15 * col)
    out = srgb_from_linear(col) * inside[..., None]
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def seam_check(name):
    a = np.asarray(Image.open(os.path.join(PL, name + ".png")).convert("RGB"), np.float32)
    edge = np.abs(a[:, 0] - a[:, -1]).mean()
    inner = np.abs(a[:, 1:] - a[:, :-1]).mean()
    print("seam %-22s edge diff %.2f  vs neighbour-column diff %.2f  -> %s" % (
        name, edge, inner, "OK" if edge < inner * 1.5 + 0.5 else "CHECK"))


def main():
    os.makedirs(PREV, exist_ok=True)
    names = PLANETS + list(EMIS.values())
    for nm in names:
        seam_check(nm)
    for nm in ("../sky/space_panorama_enemy",):
        p = os.path.join(PL, nm + ".png")
        if os.path.exists(p):
            seam_check(nm)
    # flat sheet: 2 columns
    tw, th = 512, 256
    rows = (len(names) + 1) // 2
    sheet = Image.new("RGB", (2 * tw + 12, rows * (th + 26) + 4), (10, 10, 14))
    dr = ImageDraw.Draw(sheet)
    for i, nm in enumerate(names):
        im = Image.open(os.path.join(PL, nm + ".png")).convert("RGB").resize((tw, th), Image.LANCZOS)
        x = (i % 2) * (tw + 12)
        y = (i // 2) * (th + 26) + 22
        sheet.paste(im, (x, y))
        dr.text((x + 4, y - 18), nm + ".png", fill=(220, 220, 230))
    sheet.save(os.path.join(PREV, "alien_planets_sheet.png"))
    # spheres: row 1 = day side + pole, row 2 = seam facing the camera
    S = 300
    sph = Image.new("RGB", (len(PLANETS) * (S + 10) + 10, 2 * (S + 30) + 10), (0, 0, 0))
    dr = ImageDraw.Draw(sph)
    for i, nm in enumerate(PLANETS):
        alb = load_lin(nm)
        em = load_lin(EMIS[nm]) if nm in EMIS else None
        a = sphere(alb, em, S, tilt=35, spin=40.0 * i + 20)
        b = sphere(alb, em, S, tilt=-20, spin=180.0, sun=(0.75, 0.25, 0.6))
        x = 10 + i * (S + 10)
        sph.paste(Image.fromarray(a), (x, 26))
        sph.paste(Image.fromarray(b), (x, S + 56))
        dr.text((x + 4, 6), nm, fill=(220, 220, 230))
    dr.text((14, S + 36), "row 2: u=0/1 seam facing the camera, south pole tilted in", fill=(160, 160, 170))
    sph.save(os.path.join(PREV, "alien_planets_spheres.png"))
    # overview: sphere strip on top, enemy sky panorama + enemy map background below
    bottom = []
    sky = os.path.join(ROOT, "assets", "textures", "sky", "space_panorama_enemy.png")
    mp = os.path.join(ROOT, "assets", "textures", "map", "map_background_enemy.png")
    if os.path.exists(sky):
        bottom.append(Image.open(sky).convert("RGB").resize((1024, 512), Image.LANCZOS))
    if os.path.exists(mp):
        bottom.append(Image.open(mp).convert("RGB").resize((910, 512), Image.LANCZOS))
    wb = sum(p_.width for p_ in bottom) + 10 * max(0, len(bottom) - 1)
    wtot = max(wb, 1024)
    top = sph.resize((wtot, int(sph.height * wtot / sph.width)), Image.LANCZOS)
    ov = Image.new("RGB", (wtot, top.height + (522 if bottom else 0)), (0, 0, 0))
    ov.paste(top, (0, 0))
    x = 0
    for p_ in bottom:
        ov.paste(p_, (x, top.height + 10))
        x += p_.width + 10
    ov.save(os.path.join(PREV, "alien_textures_sheet.png"))
    wmax = wtot
    print("previews written to", PREV, "(max part width %d)" % wmax)


if __name__ == "__main__":
    main()
