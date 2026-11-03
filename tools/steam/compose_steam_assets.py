"""
compose_steam_assets.py - builds the Steam library files for "Starfighter Defense" from the raw renders.

Inputs (tools/steam/renders/, made by final_a.py, final_c.py and make_icon.py):
  final_a_hero_16bit.tif      3840x1240  hero (concept A, cockpit view over Halcyon)
  final_a_portrait_16bit.tif  1200x1800  portrait capsule (concept A)
  final_c_wide_16bit.tif      1840x860   wide capsule (concept C, attack over Xhal)
  icon_ship_2048.png (+ icon_ship_meta.json)  the player's ship, RGBA, for the icon
Output (default /home/user/builds/steam_grid/, then zipped to /home/user/builds/StarfighterDefense_SteamGrid.zip):
  StarfighterDefense_hero_3840x1240.png, StarfighterDefense_hero_1920x620.png      (no text)
  StarfighterDefense_logo.png                       transparent logo, Orbitron 900, white -> cyan
  StarfighterDefense_grid_600x900.png / _1200x1800.png   portrait capsule with the title (top band)
  StarfighterDefense_grid_920x430.png / _1840x860.png    wide capsule with the title (top left)
  StarfighterDefense_icon_512.png, _icon_256.png, StarfighterDefense_icon.ico (16, 24, 32, 48, 64, 128, 256)
  preview_sheet.png                                 contact sheet (logo over the hero like Steam shows it)
  LIESMICH_Steam.txt                                German notes: which file is which, how to set them
All quantisation to 8 bit uses TPDF dither from the 16-bit / float data (no banding in the dark skies).
Run:  /opt/tools/venv/bin/python tools/steam/compose_steam_assets.py [--out DIR] [--zip PATH] [--no-zip]
Pure numpy + Pillow (no Blender needed).
"""
import argparse
import json
import os
import struct
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
RENDERS = os.path.join(HERE, "renders")
FONT_DIR = "/opt/tools/fonts/fontsource-orbitron-5.3.0/package/files"
FONT_900 = os.path.join(FONT_DIR, "orbitron-latin-900-normal.woff")
FONT_500 = os.path.join(FONT_DIR, "orbitron-latin-500-normal.woff")
PREFIX = "StarfighterDefense"


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


CYAN = hexrgb("#52E6FF")
AMBER = hexrgb("#FFB838")
NAVY = hexrgb("#0A1630")
STEAM_BG = hexrgb("#1B2838")
STEAM_BG2 = hexrgb("#23262E")


# ------------------------------------------------------------------------------------------------
# image I/O (display-referred float RGB 0..1)
# ------------------------------------------------------------------------------------------------
def read_tiff16(path):
    """Minimal reader for the uncompressed, chunky 16-bit RGB TIFFs written by Blender / final_a.py."""
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
    a = np.frombuffer(buf, dtype=bo + "u2").reshape(h, w, spp)[..., :3]
    return a.astype(np.float32) / 65535.0


def load_render(name):
    """16-bit TIFF if present (preferred), else the 8-bit PNG"""
    tif = os.path.join(RENDERS, name + "_16bit.tif")
    if os.path.exists(tif):
        return read_tiff16(tif)
    return np.asarray(Image.open(os.path.join(RENDERS, name + ".png")).convert("RGB")).astype(np.float32) / 255.0


def resize_f(x, size):
    """Lanczos resize of a float image (per channel, 32-bit float, no 8-bit round trip)"""
    # mode "F" is 32-bit float: a float64 array would be reinterpreted byte-wise (garbage), so cast first
    chans = [np.asarray(Image.fromarray(np.ascontiguousarray(x[..., c], dtype=np.float32), "F")
                        .resize(size, Image.LANCZOS)) for c in range(x.shape[2])]
    return np.dstack(chans).astype(np.float32)


def to8(x, seed=5, dither=True):
    v = x * 255.0
    if dither:
        rng = np.random.default_rng(seed)
        v = v + rng.random(v.shape, dtype=np.float32) - rng.random(v.shape, dtype=np.float32)
    return np.clip(np.rint(v), 0, 255).astype(np.uint8)


def save_rgb(x, path, seed=5):
    Image.fromarray(to8(x, seed), "RGB").save(path, optimize=True)
    return path


def save_rgba(rgb, a, path, seed=5):
    """straight-alpha RGBA PNG; the colour of fully transparent pixels is irrelevant"""
    out = np.dstack([to8(rgb, seed), to8(a[..., None], seed + 1, dither=False)])
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    return path


# ------------------------------------------------------------------------------------------------
# logo
# ------------------------------------------------------------------------------------------------
def text_mask(txt, font, track):
    """L mask of a word drawn letter by letter with extra tracking (px), cropped to the ink"""
    widths = [font.getlength(ch) for ch in txt]
    total = sum(widths) + track * (len(txt) - 1)
    asc, desc = font.getmetrics()
    m = Image.new("L", (int(total + 4 * track + 80), asc + desc + 80), 0)
    d = ImageDraw.Draw(m)
    x = 40.0
    for ch, w in zip(txt, widths):
        d.text((x, 40), ch, font=font, fill=255)
        x += w + track
    return m.crop(m.getbbox())


def logo_master(F=420):
    """Premultiplied float RGBA logo at a large working size + the ink box of the lettering.
    Two stacked lines: STARFIGHTER (slight tracking), DEFENSE flanked by thin bars to the same width.
    Fill: vertical white -> cyan gradient over the whole block; thin dark navy outline; soft drop
    shadow; soft cyan glow - readable on dark and light backgrounds."""
    font = ImageFont.truetype(FONT_900, F)
    l1 = text_mask("STARFIGHTER", font, F * 0.05)
    l2 = text_mask("DEFENSE", font, F * 0.11)
    W = l1.width
    gap = int(F * 0.17)
    H = l1.height + gap + l2.height
    ink = Image.new("L", (W, H), 0)
    ink.paste(l1, (0, 0))
    x2 = (W - l2.width) // 2
    ink.paste(l2, (x2, l1.height + gap))
    d = ImageDraw.Draw(ink)
    bh = max(2, int(round(F * 0.048)))
    yb = l1.height + gap + l2.height // 2 - bh // 2
    bgap = int(F * 0.13)
    d.rectangle((0, yb, x2 - bgap, yb + bh - 1), fill=255)
    d.rectangle((W - x2 + bgap, yb, W - 1, yb + bh - 1), fill=255)
    pad = int(F * 0.55)
    CW, CH = W + 2 * pad, H + 2 * pad
    M = Image.new("L", (CW, CH), 0)
    M.paste(ink, (pad, pad))
    a = np.asarray(M).astype(np.float32) / 255.0
    yy = (np.arange(CH, dtype=np.float32) - pad) / H
    t = np.clip((yy - 0.05) / 0.95, 0, 1) ** 1.15
    grad = (np.array([1.0, 1.0, 1.0], np.float32)[None] * (1 - t[:, None]) +
            (CYAN * 0.98 + 0.02)[None] * t[:, None])
    fill = np.broadcast_to(grad[:, None, :], (CH, CW, 3))
    ow = int(round(F * 0.032))
    outline_m = M.filter(ImageFilter.MaxFilter(2 * ow + 1)).filter(ImageFilter.GaussianBlur(F * 0.004))
    outline = np.asarray(outline_m).astype(np.float32) / 255.0
    sh = np.asarray(outline_m.filter(ImageFilter.GaussianBlur(F * 0.045))).astype(np.float32) / 255.0
    sh = np.roll(sh, (int(F * 0.045), int(F * 0.025)), (0, 1))
    glow = np.asarray(M.filter(ImageFilter.GaussianBlur(F * 0.17))).astype(np.float32) / 255.0
    glow2 = np.asarray(M.filter(ImageFilter.GaussianBlur(F * 0.05))).astype(np.float32) / 255.0
    rgb = np.zeros((CH, CW, 3), np.float32)
    al = np.zeros((CH, CW), np.float32)

    def over(col, aa):
        nonlocal rgb, al
        rgb = col * aa[..., None] + rgb * (1 - aa[..., None])
        al = aa + al * (1 - aa)

    over(np.broadcast_to(CYAN, (CH, CW, 3)), np.clip(glow * 1.15, 0, 1) * 0.50)
    over(np.broadcast_to(CYAN * 0.9 + 0.1, (CH, CW, 3)), np.clip(glow2 * 1.2, 0, 1) * 0.30)
    over(np.broadcast_to(np.array([0.0, 0.01, 0.03], np.float32), (CH, CW, 3)), sh * 0.70)
    over(np.broadcast_to(np.array([0.015, 0.035, 0.075], np.float32), (CH, CW, 3)), outline * 0.97)
    over(fill, a)
    return np.dstack([rgb, al]), (pad, pad, pad + W, pad + H)


def trim_logo(rgba, ink, thr=2.0 / 255.0, margin=0.03):
    ys, xs = np.where(rgba[..., 3] > thr)
    m = int(margin * (ink[2] - ink[0]))
    x0, x1 = max(xs.min() - m, 0), min(xs.max() + 1 + m, rgba.shape[1])
    y0, y1 = max(ys.min() - m, 0), min(ys.max() + 1 + m, rgba.shape[0])
    return rgba[y0:y1, x0:x1], (ink[0] - x0, ink[1] - y0, ink[2] - x0, ink[3] - y0)


def scaled_logo(rgba, ink, ink_width):
    """premultiplied logo resized so the lettering is ink_width px wide; returns (rgba, ink box)"""
    s = ink_width / float(ink[2] - ink[0])
    size = (max(1, int(round(rgba.shape[1] * s))), max(1, int(round(rgba.shape[0] * s))))
    out = np.clip(resize_f(rgba, size), 0, None)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])
    return out, tuple(v * s for v in ink)


def composite(base, logo, ink, ink_x, ink_y):
    """alpha-over a premultiplied logo onto base (float RGB) so its ink box starts at (ink_x, ink_y)"""
    out = base.copy()
    ox, oy = int(round(ink_x - ink[0])), int(round(ink_y - ink[1]))
    h, w = logo.shape[:2]
    x0, y0 = max(ox, 0), max(oy, 0)
    x1, y1 = min(ox + w, base.shape[1]), min(oy + h, base.shape[0])
    lg = logo[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    out[y0:y1, x0:x1] = lg[..., :3] + out[y0:y1, x0:x1] * (1 - lg[..., 3:4])
    return out


# ------------------------------------------------------------------------------------------------
# icon
# ------------------------------------------------------------------------------------------------
def gauss_blur(a, sigma):
    from scipy.ndimage import gaussian_filter      # Pillow cannot blur 32-bit float images
    return gaussian_filter(a.astype(np.float32), sigma, mode="constant").astype(np.float32)


def screen(base, col, amount):
    add = np.clip(amount, 0, 1)[..., None] * col
    return 1 - (1 - base) * (1 - add)


def icon_layers(S=2048):
    """ship (straight RGBA float) placed on an S x S canvas: ~85 % fill, nose to the upper right"""
    im = Image.open(os.path.join(RENDERS, "icon_ship_2048.png"))   # 16-bit PNG, Pillow reads it as 8 bit
    meta = json.load(open(os.path.join(RENDERS, "icon_ship_meta.json")))
    arr = np.asarray(im).astype(np.float32) / (65535.0 if im.mode.startswith("I") else 255.0)
    if arr.ndim == 2 or arr.shape[2] != 4:
        arr = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
    ys, xs = np.where(arr[..., 3] > 0.02)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    ext = max(x1 - x0, y1 - y0)
    s = 0.85 * S / ext
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    # premultiply, scale, place (bbox centre at 0.5 + small offset toward the upper right)
    pm = np.dstack([arr[..., :3] * arr[..., 3:4], arr[..., 3:4]])
    size = (int(round(arr.shape[1] * s)), int(round(arr.shape[0] * s)))
    pm = np.clip(resize_f(pm, size), 0, None)
    pm[..., 3] = np.clip(pm[..., 3], 0, 1)
    tx, ty = S * 0.505 - cx * s, S * 0.495 - cy * s
    canvas = np.zeros((S, S, 4), np.float32)
    ox, oy = int(round(tx)), int(round(ty))
    h, w = pm.shape[:2]
    X0, Y0, X1, Y1 = max(ox, 0), max(oy, 0), min(ox + w, S), min(oy + h, S)
    canvas[Y0:Y1, X0:X1] = pm[Y0 - oy:Y1 - oy, X0 - ox:X1 - ox]
    noz = [((u * s + tx), (v * s + ty)) for (u, v) in meta["nozzles"]]
    return canvas, noz


def icon_background(S, stars=True, flat=False, seed=7):
    yy, xx = (np.mgrid[0:S, 0:S].astype(np.float32) + 0.5) / S
    if flat:
        return np.broadcast_to(NAVY * 1.05, (S, S, 3)).copy()
    # dark navy (top left) -> violet (bottom right)
    t = np.clip(0.62 * yy + 0.38 * xx, 0, 1) ** 1.2
    top = np.array([0.030, 0.058, 0.150], np.float32)
    bot = np.array([0.120, 0.050, 0.210], np.float32)
    bg = top * (1 - t[..., None]) + bot * t[..., None]
    # dark night-side planet, only a thin cyan limb arc in the lower left (Halcyon, as in the hero)
    pc, pr = np.array([-0.55, 1.55], np.float32), 1.08
    d = np.sqrt((xx - pc[0]) ** 2 + (yy - pc[1]) ** 2)
    inside = np.clip((pr - d) * S / 1.5, 0, 1)
    planet = np.array([0.010, 0.016, 0.034], np.float32) + \
        (np.exp(-np.maximum(pr - d, 0) / 0.035) * 0.10)[..., None] * np.array([0.10, 0.45, 0.60], np.float32)
    bg = bg * (1 - inside[..., None]) + planet * inside[..., None]
    rim = np.exp(-((d - pr) / 0.0045) ** 2)
    halo = np.exp(-np.maximum(d - pr, 0) / 0.03) * (d >= pr) * 0.35
    bg = screen(bg, CYAN, rim * 1.0 + halo)
    # one small amber glint, top right
    gx, gy = 0.905, 0.285
    r2 = (xx - gx) ** 2 + (yy - gy) ** 2
    g = np.exp(-r2 / (2 * 0.0065 ** 2)) * 1.0 + np.exp(-r2 / (2 * 0.026 ** 2)) * 0.28
    g += np.exp(-((xx - gx) / 0.07) ** 2 - ((yy - gy) / 0.0022) ** 2) * 0.35
    bg = screen(bg, AMBER, g)
    if stars:
        rng = np.random.default_rng(seed)
        acc = np.zeros((S, S), np.float32)
        n = 70
        px = rng.uniform(0, 1, n)
        py = rng.uniform(0, 1, n)
        ok = np.sqrt((px - pc[0]) ** 2 + (py - pc[1]) ** 2) > pr + 0.02
        for x_, y_, b in zip(px[ok], py[ok], rng.uniform(0.25, 0.9, n)[ok]):
            acc[min(int(y_ * S), S - 1), min(int(x_ * S), S - 1)] += b
        st = gauss_blur(acc, S * 0.0011) * (2 * np.pi * (S * 0.0011) ** 2)
        bg = screen(bg, np.array([0.85, 0.92, 1.0], np.float32), np.clip(st, 0, 1))
    return bg


def shift(a, dx, dy):
    """a sampled at (x - dx, y - dy) (zero outside)"""
    out = np.zeros_like(a)
    H, W = a.shape
    xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
    ys, yd = (slice(0, H - dy), slice(dy, H)) if dy >= 0 else (slice(-dy, H), slice(0, H + dy))
    out[yd, xd] = a[ys, xs]
    return out


def compose_icon(S=2048, stars=True, flat=False, glow_scale=1.0):
    ship, noz = icon_layers(S)
    bg = icon_background(S, stars=stars, flat=flat)
    a = ship[..., 3]
    # 2D cyan rim light on the silhouette edges that face the lower left (light from below / behind):
    # the 3D rim light only catches the thin bevels of the flat ship in this top-down view
    k = max(2, int(S * 0.0075))
    rim = np.clip(a - shift(a, k, -k), 0, 1)
    rim = np.clip(gauss_blur(rim, S * 0.0022) * 1.6, 0, 1) * a
    ship = ship.copy()
    ship[..., :3] = screen(ship[..., :3], CYAN, rim * (1.0 if flat else 0.85))
    # cyan glow behind the ship (silhouette halo), stronger on the flat small-size master
    g1 = gauss_blur(a, S * 0.022 * glow_scale)
    g2 = gauss_blur(a, S * 0.060 * glow_scale)
    bg = screen(bg, CYAN, g1 * (0.62 if flat else 0.48) + g2 * (0.30 if flat else 0.22))
    out = ship[..., :3] + bg * (1 - a[..., None])
    # engine glows (cyan) at the nozzles, on top
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    for (u, v) in noz:
        r2 = (xx - u) ** 2 + (yy - v) ** 2
        e = np.exp(-r2 / (2 * (S * 0.012) ** 2)) * 0.75 + np.exp(-r2 / (2 * (S * 0.035) ** 2)) * 0.25
        out = screen(out, CYAN * 0.8 + 0.2, e)
    return np.clip(out, 0, 1).astype(np.float32)


def small_icon(master, size, contrast=1.15, sharpen=True):
    im = resize_f(master, (size, size))
    m = im.mean(axis=(0, 1), keepdims=True)
    im = np.clip((im - m) * contrast + m, 0, 1)
    p = Image.fromarray(to8(im, dither=False), "RGB")
    if sharpen:
        p = p.filter(ImageFilter.UnsharpMask(radius=0.7, percent=70, threshold=1))
    return p


# ------------------------------------------------------------------------------------------------
# preview sheet
# ------------------------------------------------------------------------------------------------
def label(d, xy, txt, size=22, fill=(200, 214, 230)):
    d.text(xy, txt, font=ImageFont.truetype(FONT_500, size), fill=fill)


def checker(w, h, n=24):
    yy, xx = np.mgrid[0:h, 0:w]
    c = ((xx // n + yy // n) % 2).astype(np.float32)
    v = 0.55 + 0.15 * c
    return np.dstack([v, v, v])


def preview_sheet(path, hero1x, logo, ink, wide1x, port1x, icons, logo_box_frac):
    W, H = 2000, 2140
    sheet = np.broadcast_to(STEAM_BG, (H, W, 3)).copy()
    d_items = []
    # 1) hero 1920x620 with the logo lower left, roughly like the Steam client places it
    hx, hy = 40, 110
    lw = int(1920 * logo_box_frac)
    lg, lk = scaled_logo(logo, ink, lw)
    hero_l = composite(hero1x, lg, lk, int(1920 * 0.035), int(620 * 0.93 - (lk[3] - lk[1])))
    sheet[hy:hy + 620, hx:hx + 1920] = hero_l
    d_items.append(((hx, hy - 34), "Hero 1920x620 (3840x1240) + Logo, wie Steam es unten links zeigt"))
    # 2) portrait 600x900 and wide 920x430 at 1x, Steam-size thumbnails
    py = hy + 620 + 80
    sheet[py:py + 900, 40:640] = port1x
    d_items.append(((40, py - 34), "Hochformat 600x900"))
    sheet[py:py + 430, 680:1600] = wide1x
    d_items.append(((680, py - 34), "Breitformat 920x430"))
    tp = resize_f(port1x, (200, 300))
    tw = resize_f(wide1x, (230, 108))
    sheet[py + 470:py + 770, 680:880] = tp
    sheet[py + 470:py + 578, 920:1150] = tw
    th = resize_f(hero1x, (960, 310))
    d_items.append(((680, py + 436), "Miniaturen 200x300 / 230x108"))
    # logo on checkerboard and on a light background
    lg2, lk2 = scaled_logo(logo, ink, 560)
    bx, by = 1190, py + 470
    hh, ww = lg2.shape[:2]
    ww, hh = min(ww, 760), min(hh, 300)
    sheet[by:by + hh, bx:bx + ww] = checker(ww, hh)
    sheet[by:by + hh, bx:bx + ww] = lg2[:hh, :ww, :3] + sheet[by:by + hh, bx:bx + ww] * (1 - lg2[:hh, :ww, 3:4])
    d_items.append(((bx, by - 34), "Logo (transparent)"))
    # 3) hero thumbnail with logo
    ty = py + 900 + 70
    lg3, lk3 = scaled_logo(logo, ink, int(960 * logo_box_frac))
    th_l = composite(th, lg3, lk3, int(960 * 0.035), int(310 * 0.93 - (lk3[3] - lk3[1])))
    sheet[ty:ty + 310, 40:1000] = th_l
    d_items.append(((40, ty - 34), "Hero 960x310 mit Logo"))
    # 4) icons: 256 px, and 64 / 48 / 32 / 24 / 16 px on both Steam greys (#1b2838 top, #23262e below)
    ix, iy = 1040, ty
    sheet[iy:iy + 256, ix:ix + 256] = icons[256]
    x0 = ix + 256 + 30
    sheet[iy + 160:iy + 310, x0 - 10:W - 40] = STEAM_BG2
    x = x0
    for s in (64, 48, 32, 24, 16):
        sheet[iy + 64 - s + 10:iy + 74, x:x + s] = icons[s]
        sheet[iy + 64 - s + 170:iy + 234, x:x + s] = icons[s]
        x += s + 26
    d_items.append(((ix, iy - 34), "Icon 256 / 64 / 48 / 32 / 24 / 16 px"))
    img = Image.fromarray(to8(sheet), "RGB")
    d = ImageDraw.Draw(img)
    label(d, (40, 22), "STARFIGHTER DEFENSE - Steam-Grid-Artwork (Vorschau)", 30, (255, 255, 255))
    for xy, t in d_items:
        label(d, xy, t)
    img.save(path, optimize=True)
    return path


# ------------------------------------------------------------------------------------------------
# README (German)
# ------------------------------------------------------------------------------------------------
LIESMICH = r"""STARFIGHTER DEFENSE – Steam-Grid-Artwork
========================================

Bilder für die Steam-Bibliothek, wenn „Starfighter Defense“ als Nicht-Steam-Spiel in Steam
eingetragen ist. Alle Motive sind mit Blender/Cycles aus den 3D-Modellen und Texturen des Spiels
gerendert, der Titel ist in Orbitron gesetzt.


Welche Datei ist was?
---------------------
StarfighterDefense_grid_600x900.png     Hochformat-Kachel („Capsule“) mit Titel – das Bild in der
                                        Kachelansicht der Bibliothek
StarfighterDefense_grid_1200x1800.png   dasselbe in doppelter Auflösung (schärfer auf großen bzw.
                                        hochauflösenden Bildschirmen)
StarfighterDefense_grid_920x430.png     Breitformat-Kachel mit Titel
StarfighterDefense_grid_1840x860.png    dasselbe in doppelter Auflösung
StarfighterDefense_hero_3840x1240.png   „Hero“: breites Hintergrundbild oben auf der Spielseite,
                                        ohne Text (Steam blendet das Logo darüber ein)
StarfighterDefense_hero_1920x620.png    dasselbe in Standardgröße
StarfighterDefense_logo.png             Logo mit transparentem Hintergrund (liegt über dem Hero)
StarfighterDefense_icon_256.png         Symbol 256 × 256 (PNG)
StarfighterDefense_icon_512.png         Symbol 512 × 512 (PNG)
StarfighterDefense_icon.ico             Symbol für Windows mit 16, 24, 32, 48, 64, 128 und 256 px
preview_sheet.png                       Übersicht aller Bilder – nur zum Ansehen, nicht für Steam

Von den Paaren (Standardgröße / doppelte Größe) braucht man jeweils nur eine Datei; beide zeigen
dasselbe Motiv. Das Hero-Bild hat unten links eine ruhige, dunkle Fläche für das Logo.


Im Steam-Client festlegen
-------------------------
Voraussetzung: Das Spiel steht als Nicht-Steam-Spiel in der Bibliothek (in der Bibliothek unten
links „Spiel hinzufügen“ > „Ein Nicht-Steam-Spiel hinzufügen …“).
Die Menüpunkte können je nach Client-Version und Sprache etwas anders heißen; in Klammern steht
jeweils die englische Bezeichnung.

1. Hochformat-Kachel
   In der Bibliothek Rechtsklick auf das Spiel > Verwalten > Benutzerdefiniertes Artwork festlegen
   (Manage > Set custom artwork) und StarfighterDefense_grid_600x900.png
   (oder StarfighterDefense_grid_1200x1800.png) auswählen.

2. Hero (Hintergrundbild der Spielseite)
   Die Spielseite öffnen, mit der rechten Maustaste auf das große Bild oben klicken >
   Benutzerdefinierten Hintergrund festlegen (Set Custom Background) und
   StarfighterDefense_hero_3840x1240.png (oder StarfighterDefense_hero_1920x620.png) auswählen.

3. Logo
   Ebenfalls auf der Spielseite: Rechtsklick auf das Hintergrundbild > Benutzerdefiniertes Logo
   festlegen (Set Custom Logo) und StarfighterDefense_logo.png auswählen. Mit Rechtsklick >
   Logo-Position anpassen (Adjust Logo Position) lassen sich Position und Größe ändern – das
   Hero-Bild ist für ein Logo unten links angelegt.

4. Symbol (Icon)
   Rechtsklick auf das Spiel > Eigenschaften … (Properties). Im Fenster auf das Symbolfeld neben
   dem Namen der Verknüpfung klicken und StarfighterDefense_icon.ico (Windows) oder
   StarfighterDefense_icon_256.png auswählen.

Die Breitformat-Kachel (920 × 430) setzt man am einfachsten über den grid-Ordner (siehe unten).


Alternative: Dateien direkt in den grid-Ordner kopieren
--------------------------------------------------------
Steam speichert benutzerdefinierte Bilder im Ordner
   Windows:  C:\Program Files (x86)\Steam\userdata\<ID>\config\grid\
   Linux:    ~/.steam/steam/userdata/<ID>/config/grid/
             (je nach Installation auch ~/.local/share/Steam/userdata/<ID>/config/grid/)
<ID> ist die Nummer des eigenen Steam-Kontos (der Unterordner von userdata). Fehlt der Ordner
„grid“, kann man ihn anlegen.

Die Dateien werden nach der App-ID der Verknüpfung benannt (<appid> steht für eine Zahl):
   <appid>p.png       Hochformat-Kachel    <- StarfighterDefense_grid_600x900.png (oder 1200x1800)
   <appid>.png        Breitformat-Kachel   <- StarfighterDefense_grid_920x430.png (oder 1840x860)
   <appid>_hero.png   Hero                 <- StarfighterDefense_hero_3840x1240.png (oder 1920x620)
   <appid>_logo.png   Logo                 <- StarfighterDefense_logo.png
   <appid>_icon.png   Symbol               <- StarfighterDefense_icon_256.png

So findet man die <appid> am einfachsten: zuerst ein Bild über den Client festlegen (Schritt 1
oben). Steam legt dann im grid-Ordner eine Datei <Zahl>p.png an – diese Zahl ist die <appid>.
Die übrigen Dateien mit derselben Zahl benennen. Steam vor dem Kopieren beenden und danach wieder
starten, damit die Bilder neu geladen werden.

Hinweis zum Symbol: Bei Nicht-Steam-Spielen gilt das Symbol, das in den Eigenschaften der
Verknüpfung eingetragen ist. Eine Datei <appid>_icon.png im grid-Ordner wählt man deshalb wie in
Schritt 4 in den Eigenschaften aus.
"""


# ------------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/home/user/builds/steam_grid")
    ap.add_argument("--zip", default="/home/user/builds/StarfighterDefense_SteamGrid.zip")
    ap.add_argument("--no-zip", action="store_true")
    ap.add_argument("--renders", default="", help="input folder (default tools/steam/renders)")
    args = ap.parse_args()
    global RENDERS
    if args.renders:
        RENDERS = args.renders
    os.makedirs(args.out, exist_ok=True)
    out = lambda name: os.path.join(args.out, "%s_%s" % (PREFIX, name))  # noqa: E731
    files = []

    # --- logo ---------------------------------------------------------------------------------
    logo, ink = logo_master()
    logo, ink = trim_logo(logo, ink)
    # the logo file: at most 1280 x 720, lettering as wide as fits
    lw = 1280.0 / logo.shape[1] * (ink[2] - ink[0])
    if logo.shape[0] * 1280.0 / logo.shape[1] > 720:
        lw = 720.0 / logo.shape[0] * (ink[2] - ink[0])
    lf, lk = scaled_logo(logo, ink, int(lw))
    a = lf[..., 3]
    rgb = np.where(a[..., None] > 1e-4, lf[..., :3] / np.maximum(a[..., None], 1e-4), 0)
    files.append(save_rgba(np.clip(rgb, 0, 1), a, out("logo.png")))
    print("logo", lf.shape[1], "x", lf.shape[0])

    # --- hero -------------------------------------------------------------------------------------
    hero = load_render("final_a_hero")
    assert hero.shape[:2] == (1240, 3840), hero.shape
    files.append(save_rgb(hero, out("hero_3840x1240.png"), 11))
    hero1 = np.clip(resize_f(hero, (1920, 620)), 0, 1)
    files.append(save_rgb(hero1, out("hero_1920x620.png"), 12))

    # --- wide capsule: title in the free top-left quadrant ---------------------------------------
    wide = load_render("final_c_wide")
    assert wide.shape[:2] == (860, 1840), wide.shape
    Wd, Hd = 1840, 860
    lg, lk = scaled_logo(logo, ink, int(0.455 * Wd))
    wide_t = np.clip(composite(wide, lg, lk, 0.040 * Wd, 0.075 * Hd), 0, 1)
    files.append(save_rgb(wide_t, out("grid_1840x860.png"), 13))
    wide1 = np.clip(resize_f(wide_t, (920, 430)), 0, 1)
    files.append(save_rgb(wide1, out("grid_920x430.png"), 14))

    # --- portrait capsule: title centred in the calm top band ------------------------------------
    port = load_render("final_a_portrait")
    assert port.shape[:2] == (1800, 1200), port.shape
    Wp, Hp = 1200, 1800
    tw = int(0.84 * Wp)
    lg, lk = scaled_logo(logo, ink, tw)
    port_t = np.clip(composite(port, lg, lk, (Wp - tw) / 2.0, 0.065 * Hp), 0, 1)
    files.append(save_rgb(port_t, out("grid_1200x1800.png"), 15))
    port1 = np.clip(resize_f(port_t, (600, 900)), 0, 1)
    files.append(save_rgb(port1, out("grid_600x900.png"), 16))

    # --- icon -----------------------------------------------------------------------------------
    S = 2048
    master = compose_icon(S, stars=True)
    master_ns = compose_icon(S, stars=False)
    master_flat = compose_icon(S, stars=False, flat=True, glow_scale=1.6)
    Image.fromarray(to8(master), "RGB").save(os.path.join(RENDERS, "icon_master_2048.png"), optimize=True)
    icons = {}
    for s in (512, 256, 128):
        icons[s] = np.clip(resize_f(master, (s, s)), 0, 1)
    for s in (64, 48):
        icons[s] = np.clip(resize_f(master_ns, (s, s)), 0, 1)
    small = {s: small_icon(master_flat, s) for s in (32, 24, 16)}
    for s, p in small.items():
        icons[s] = np.asarray(p).astype(np.float32) / 255.0
    files.append(save_rgb(icons[512], out("icon_512.png"), 17))
    files.append(save_rgb(icons[256], out("icon_256.png"), 18))
    ico_imgs = {s: Image.fromarray(to8(icons[s], dither=False), "RGB").convert("RGBA")
                for s in (16, 24, 32, 48, 64, 128, 256)}
    base = ico_imgs[256]
    ico_path = out("icon.ico")
    base.save(ico_path, format="ICO", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
              append_images=[ico_imgs[s] for s in (16, 24, 32, 48, 64, 128)])
    files.append(ico_path)

    # --- preview sheet + README --------------------------------------------------------------------
    files.append(preview_sheet(os.path.join(args.out, "preview_sheet.png"), hero1, logo, ink, wide1, port1,
                               icons, logo_box_frac=0.30))
    p = os.path.join(args.out, "LIESMICH_Steam.txt")
    with open(p, "w", encoding="utf-8-sig", newline="\r\n") as f:     # BOM + CRLF: opens cleanly in Notepad
        f.write(LIESMICH)
    files.append(p)

    # --- zip ------------------------------------------------------------------------------------
    keep = set(os.path.basename(f) for f in files)
    for fn in os.listdir(args.out):       # stale files from earlier runs are not part of the set
        if fn not in keep:
            print("note: not in this build, left out of the zip:", fn)
    if not args.no_zip:
        if os.path.exists(args.zip):
            os.remove(args.zip)
        with zipfile.ZipFile(args.zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in sorted(files):
                z.write(f, "steam_grid/" + os.path.basename(f))
        print("zip ->", args.zip, os.path.getsize(args.zip) // 1024, "KB")
    for f in sorted(files):
        if f.endswith(".png"):
            im = Image.open(f)
            print("  %-45s %dx%d %s" % (os.path.basename(f), im.width, im.height, im.mode))
        else:
            print("  %-45s %d bytes" % (os.path.basename(f), os.path.getsize(f)))


if __name__ == "__main__":
    main()
