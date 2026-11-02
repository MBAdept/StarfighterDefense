"""
gen_sky_enemy.py - space panorama for the hostile ENEMY star system (4096x2048 equirectangular).
Run:  /opt/tools/venv/bin/python tools/textures/gen_sky_enemy.py [--preview]
Output: assets/textures/sky/space_panorama_enemy.png
Reuses the generator of gen_sky.py unchanged (3D direction vectors -> seamless left/right, no pole pinching;
stars splatted by exact angular distance) and only registers a new variant with a hostile crimson / violet /
magenta nebula palette and a warm reddish galactic band. Intensities stay in the same subtle range as the
existing panoramas so ships and glowing shots still stand out.
Previews: tools/textures/previews/sky_enemy_small.png (+ crop_center / crop_seam / crop_pole).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sky  # noqa: E402

gen_sky.VARIANTS["enemy"] = dict(
    seed=6613,
    out="space_panorama_enemy.png",
    # (centre lon deg, centre lat deg, radius deg, inner rgb, outer rgb, strength)
    nebulae=[
        (25, 14, 54, (0.86, 0.10, 0.12), (0.32, 0.02, 0.07), 1.00),     # crimson (large)
        (-115, -22, 50, (0.52, 0.13, 0.88), (0.17, 0.03, 0.38), 0.95),  # violet
        (140, 34, 36, (0.95, 0.18, 0.52), (0.30, 0.04, 0.20), 0.70),    # magenta
        (-35, -52, 30, (0.72, 0.20, 0.08), (0.26, 0.04, 0.03), 0.50),   # smouldering deep red
    ],
    band_tint=(1.0, 0.84, 0.82),
    bg_tint=(0.60, 0.22, 0.42),
)

if __name__ == "__main__":
    os.makedirs(gen_sky.OUT_DIR, exist_ok=True)
    print("variant enemy")
    gen_sky.build("enemy", "--preview" in sys.argv)
