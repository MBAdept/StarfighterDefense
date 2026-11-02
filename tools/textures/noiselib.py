"""
noiselib.py - vectorised procedural noise for texture generation (numpy only).

Contents
  Perlin3      : improved 3D gradient noise (Ken Perlin 2002), evaluated on arbitrary point arrays.
  fbm3 / ridged3 / warp3 : fractal helpers built on Perlin3 (random rotation per octave
                 to hide lattice alignment).
  TilePerlin2  : 2D gradient noise that tiles with an integer period (for seamless textures).
  sphere_dirs  : direction vectors for an equirectangular image (no seam, no pole pinch when
                 noise is evaluated on these 3D points).
  helpers      : smoothstep, lerp, gradient maps, downsample, save helpers.

All functions work in float32 to keep memory reasonable for multi-megapixel images.
"""
import numpy as np
from PIL import Image

F32 = np.float32


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def random_rotation(rng):
    """Uniform random 3x3 rotation matrix (QR of a gaussian matrix)."""
    q, r = np.linalg.qr(rng.normal(size=(3, 3)))
    q = q * np.sign(np.diag(r))
    if np.linalg.det(q) < 0:
        q[:, 0] = -q[:, 0]
    return q.astype(F32)


class Perlin3:
    """Improved Perlin noise in 3D. noise(x, y, z) -> roughly [-1, 1]."""

    _GRAD = np.array([
        [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
        [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
        [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
        [1, 1, 0], [0, -1, 1], [-1, 1, 0], [0, -1, -1]], dtype=F32)

    def __init__(self, seed=0):
        rng = np.random.default_rng(seed)
        p = rng.permutation(256).astype(np.int32)
        self.perm = np.concatenate([p, p, p[:2]])  # 514 entries -> safe for +1 lookups
        self.gx = self._GRAD[:, 0].copy()
        self.gy = self._GRAD[:, 1].copy()
        self.gz = self._GRAD[:, 2].copy()

    def _g(self, h, x, y, z):
        h = h & 15
        return self.gx[h] * x + self.gy[h] * y + self.gz[h] * z

    def noise(self, x, y, z):
        x = np.asarray(x, dtype=F32)
        y = np.asarray(y, dtype=F32)
        z = np.asarray(z, dtype=F32)
        xf0 = np.floor(x)
        yf0 = np.floor(y)
        zf0 = np.floor(z)
        xi = xf0.astype(np.int64) & 255
        yi = yf0.astype(np.int64) & 255
        zi = zf0.astype(np.int64) & 255
        xf = x - xf0
        yf = y - yf0
        zf = z - zf0
        u = _fade(xf)
        v = _fade(yf)
        w = _fade(zf)
        p = self.perm
        A = p[xi] + yi
        AA = p[A] + zi
        AB = p[A + 1] + zi
        B = p[xi + 1] + yi
        BA = p[B] + zi
        BB = p[B + 1] + zi
        x1 = xf - 1.0
        y1 = yf - 1.0
        z1 = zf - 1.0
        n000 = self._g(p[AA], xf, yf, zf)
        n100 = self._g(p[BA], x1, yf, zf)
        n010 = self._g(p[AB], xf, y1, zf)
        n110 = self._g(p[BB], x1, y1, zf)
        n001 = self._g(p[AA + 1], xf, yf, z1)
        n101 = self._g(p[BA + 1], x1, yf, z1)
        n011 = self._g(p[AB + 1], xf, y1, z1)
        n111 = self._g(p[BB + 1], x1, y1, z1)
        x00 = n000 + u * (n100 - n000)
        x10 = n010 + u * (n110 - n010)
        x01 = n001 + u * (n101 - n001)
        x11 = n011 + u * (n111 - n011)
        y0 = x00 + v * (x10 - x00)
        y1_ = x01 + v * (x11 - x01)
        return (y0 + w * (y1_ - y0)).astype(F32)


class Fractal3:
    """Fractal sums of Perlin3 with a fixed random rotation + offset per octave."""

    def __init__(self, seed=0, max_oct=12):
        rng = np.random.default_rng(seed + 9173)
        self.base = Perlin3(seed)
        self.rots = [random_rotation(rng) for _ in range(max_oct)]
        self.offs = [rng.uniform(-100, 100, 3).astype(F32) for _ in range(max_oct)]

    def _oct(self, i, p, f):
        r = self.rots[i]
        o = self.offs[i]
        x = (p[..., 0] * r[0, 0] + p[..., 1] * r[0, 1] + p[..., 2] * r[0, 2]) * f + o[0]
        y = (p[..., 0] * r[1, 0] + p[..., 1] * r[1, 1] + p[..., 2] * r[1, 2]) * f + o[1]
        z = (p[..., 0] * r[2, 0] + p[..., 1] * r[2, 1] + p[..., 2] * r[2, 2]) * f + o[2]
        return self.base.noise(x, y, z)

    def fbm(self, p, freq=1.0, octaves=6, lac=2.0, gain=0.5):
        """p: (..., 3) float32 array. Returns ~[-1,1] (normalised by amplitude sum)."""
        total = np.zeros(p.shape[:-1], dtype=F32)
        amp = 1.0
        norm = 0.0
        f = freq
        for i in range(octaves):
            total += amp * self._oct(i, p, f)
            norm += amp
            amp *= gain
            f *= lac
        return total / F32(norm * 0.7)  # 0.7: typical std -> spread to ~[-1,1]

    def ridged(self, p, freq=1.0, octaves=6, lac=2.0, gain=0.5, sharp=2.0):
        """Ridged multifractal-ish noise in [0,1] (1 = ridge)."""
        total = np.zeros(p.shape[:-1], dtype=F32)
        amp = 1.0
        norm = 0.0
        f = freq
        prev = np.ones(p.shape[:-1], dtype=F32)
        for i in range(octaves):
            n = np.clip(1.0 - np.abs(self._oct(i, p, f)), 0.0, 1.0)
            n = n ** sharp
            total += amp * n * prev
            prev = np.clip(n * 1.2, 0, 1)
            norm += amp
            amp *= gain
            f *= lac
        return total / F32(norm)

    def turbulence(self, p, freq=1.0, octaves=6, lac=2.0, gain=0.5):
        total = np.zeros(p.shape[:-1], dtype=F32)
        amp = 1.0
        norm = 0.0
        f = freq
        for i in range(octaves):
            total += amp * np.abs(self._oct(i, p, f))
            norm += amp
            amp *= gain
            f *= lac
        return total / F32(norm * 0.55)


def warp3(fr_list, p, freq, strength, octaves=4):
    """Domain warp: returns p + strength * (fbm_x, fbm_y, fbm_z) using three Fractal3 objects."""
    q = np.empty_like(p)
    for k in range(3):
        q[..., k] = p[..., k] + strength * fr_list[k].fbm(p, freq, octaves)
    return q


def sphere_dirs(w, h, dtype=F32):
    """Equirectangular direction field. Returns (h, w, 3), lon in [-pi,pi) along x,
    lat from +pi/2 (top row) to -pi/2 (bottom). Convention: y = up."""
    lon = (np.arange(w, dtype=np.float64) + 0.5) / w * 2.0 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(h, dtype=np.float64) + 0.5) / h * np.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    d = np.stack([cl * np.sin(lon), np.sin(lat), -cl * np.cos(lon)], axis=-1)
    return d.astype(dtype)


def dir_to_lonlat(d):
    lon = np.arctan2(d[..., 0], -d[..., 2])
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    return lon, lat


class TilePerlin2:
    """2D gradient noise tiling with integer period `period` (in lattice cells)."""

    def __init__(self, seed=0):
        rng = np.random.default_rng(seed)
        ang = rng.uniform(0, 2 * np.pi, 4096)
        self.gx = np.cos(ang).astype(F32)
        self.gy = np.sin(ang).astype(F32)
        self.seed = seed

    def _hash(self, xi, yi, period):
        xi = np.mod(xi, period)
        yi = np.mod(yi, period)
        h = (xi * 374761393 + yi * 668265263 + self.seed * 1442695041) & 0xFFFFFFFF
        h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
        return (h ^ (h >> 16)) & 4095

    def noise(self, x, y, period):
        x0 = np.floor(x)
        y0 = np.floor(y)
        xi = x0.astype(np.int64)
        yi = y0.astype(np.int64)
        xf = (x - x0).astype(F32)
        yf = (y - y0).astype(F32)
        u = _fade(xf)
        v = _fade(yf)

        def g(ix, iy, dx, dy):
            h = self._hash(ix, iy, period)
            return self.gx[h] * dx + self.gy[h] * dy

        n00 = g(xi, yi, xf, yf)
        n10 = g(xi + 1, yi, xf - 1, yf)
        n01 = g(xi, yi + 1, xf, yf - 1)
        n11 = g(xi + 1, yi + 1, xf - 1, yf - 1)
        a = n00 + u * (n10 - n00)
        b = n01 + u * (n11 - n01)
        return (a + v * (b - a)) * F32(1.414)

    def fbm(self, w, h, base_period=4, octaves=6, gain=0.5):
        """Tileable fbm image of size (h, w); base_period lattice cells across the image."""
        ys, xs = np.mgrid[0:h, 0:w].astype(F32)
        total = np.zeros((h, w), F32)
        amp = 1.0
        norm = 0.0
        period = base_period
        for _ in range(octaves):
            total += amp * self.noise(xs / w * period, ys / h * period, period)
            norm += amp
            amp *= gain
            period *= 2
        return total / F32(norm * 0.6)


def gradient_map(t, stops):
    """t: array in [0,1]; stops: list of (pos, (r,g,b)). Returns (..., 3)."""
    t = np.clip(t, 0.0, 1.0)
    pos = np.array([s[0] for s in stops], dtype=F32)
    cols = np.array([s[1] for s in stops], dtype=F32)
    out = np.empty(t.shape + (3,), dtype=F32)
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def srgb_from_linear(x):
    x = np.clip(x, 0.0, None)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def linear_from_srgb(x):
    x = np.asarray(x, dtype=F32)
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def box_down(img, f):
    """Downsample by integer factor f with a box filter (works for (h,w) or (h,w,c))."""
    h, w = img.shape[:2]
    h2, w2 = h // f, w // f
    img = img[:h2 * f, :w2 * f]
    if img.ndim == 2:
        return img.reshape(h2, f, w2, f).mean(axis=(1, 3))
    return img.reshape(h2, f, w2, f, img.shape[2]).mean(axis=(1, 3))


def blur_wrap_x(img, sigma):
    """Separable gaussian blur, wrapping horizontally (equirect), clamping vertically."""
    if sigma <= 0:
        return img
    r = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(F32)
    k /= k.sum()
    out = np.zeros_like(img)
    for i, kv in enumerate(k):
        out += kv * np.roll(img, i - r, axis=1)
    tmp = out
    out = np.zeros_like(img)
    pad = np.concatenate([np.repeat(tmp[:1], r, axis=0), tmp, np.repeat(tmp[-1:], r, axis=0)], axis=0)
    h = img.shape[0]
    for i, kv in enumerate(k):
        out += kv * pad[i:i + h]
    return out


def blur2d(img, sigma, wrap=False):
    if sigma <= 0:
        return img
    r = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(F32)
    k /= k.sum()
    out = np.zeros_like(img)
    if wrap:
        for i, kv in enumerate(k):
            out += kv * np.roll(img, i - r, axis=1)
        tmp = out
        out = np.zeros_like(img)
        for i, kv in enumerate(k):
            out += kv * np.roll(tmp, i - r, axis=0)
        return out
    h, w = img.shape[:2]
    padx = np.concatenate([np.repeat(img[:, :1], r, axis=1), img, np.repeat(img[:, -1:], r, axis=1)], axis=1)
    for i, kv in enumerate(k):
        out += kv * padx[:, i:i + w]
    tmp = out
    out = np.zeros_like(img)
    pady = np.concatenate([np.repeat(tmp[:1], r, axis=0), tmp, np.repeat(tmp[-1:], r, axis=0)], axis=0)
    for i, kv in enumerate(k):
        out += kv * pady[i:i + h]
    return out


def save_rgb(path, rgb01, optimize=True):
    a = (np.clip(rgb01, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(a, "RGB").save(path, optimize=optimize)


def save_rgba(path, rgba01, optimize=True):
    a = (np.clip(rgba01, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(a, "RGBA").save(path, optimize=optimize)


def save_gray(path, g01, optimize=True):
    a = (np.clip(g01, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(a, "L").save(path, optimize=optimize)


def dither(rgb01, rng, amount=1.0 / 255.0):
    """Add triangular dither noise to avoid banding in dark gradients."""
    n = (rng.random(rgb01.shape, dtype=F32) - rng.random(rgb01.shape, dtype=F32)) * amount
    return rgb01 + n
