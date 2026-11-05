"""
gen_sky_enemy2.py - space panorama for the SECOND hostile star system "Ixmora" (4096x2048 equirectangular).
Run:  /opt/tools/venv/bin/python tools/textures/gen_sky_enemy2.py [--preview]
Output: assets/textures/sky/space_panorama_enemy2.png
Reuses the generator of gen_sky.py unchanged and only registers a variant with a cold blue / indigo / violet nebula
palette (blue giant star) and a pale bluish galactic band. Intensities stay in the same subtle range as the other
panoramas so ships and glowing shots still stand out.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sky  # noqa: E402

gen_sky.VARIANTS["enemy2"] = dict(
    seed=7729,
    out="space_panorama_enemy2.png",
    # (centre lon deg, centre lat deg, radius deg, inner rgb, outer rgb, strength)
    nebulae=[
        (-60, 18, 56, (0.16, 0.30, 0.95), (0.04, 0.07, 0.40), 1.00),    # deep blue (large)
        (95, -26, 48, (0.48, 0.20, 0.92), (0.14, 0.04, 0.40), 0.90),    # violet
        (165, 38, 34, (0.20, 0.70, 0.88), (0.04, 0.18, 0.34), 0.60),    # icy cyan
        (20, -55, 30, (0.30, 0.16, 0.62), (0.08, 0.03, 0.22), 0.50),    # dim indigo
    ],
    band_tint=(0.84, 0.90, 1.0),
    bg_tint=(0.30, 0.34, 0.80),
)

if __name__ == "__main__":
    os.makedirs(gen_sky.OUT_DIR, exist_ok=True)
    print("variant enemy2")
    gen_sky.build("enemy2", "--preview" in sys.argv)
