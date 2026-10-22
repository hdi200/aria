#!/usr/bin/env python3
"""Builds the Android launcher icons from the iOS 1024 px app icon (light art on #0077FF).

Usage, from this repository:
  python3 scripts/make-launcher-icon.py ../MuseReaderiOS/MuseReaderiOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png Aria/Android/app/src/main/res
"""
import sys
import numpy as np
from PIL import Image, ImageDraw

src, res = sys.argv[1], sys.argv[2]
BLUE = np.array([0, 119, 255], float)
icon = np.asarray(Image.open(src).convert('RGB').resize((2048, 2048), Image.LANCZOS), float)
# Coverage of the light art over the blue: the red channel is 0 on blue, ~255 on the art.
a = np.clip(icon[..., 0] / 255.0, 0, 1)
safe = np.maximum(a, 1e-6)[..., None]
color = np.clip((icon - (1 - a[..., None]) * BLUE) / safe, 0, 255)

L = 4320                      # 108 dp layer at 40 px/dp, downsampled later
S = int(L * 60 / 108)         # icon art fills 60 dp, keeping the A and note inside a round mask
off = (L - S) // 2
art_a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((S, S), Image.LANCZOS), float) / 255
art_c = np.stack([np.asarray(Image.fromarray(color[..., i].astype(np.uint8)).resize((S, S), Image.LANCZOS), float) for i in range(3)], -1)
fa = np.zeros((L, L)); fc = np.full((L, L, 3), 255.0)
fa[off:off+S, off:off+S] = art_a; fc[off:off+S, off:off+S] = art_c
# The staff lines run to the icon's edges; carry them on to the layer's edges.
edge = S // 60
for x0, x1, col in [(0, off + edge, off + edge), (off + S - 1 - edge, L, off + S - 1 - edge)]:
    fa[off:off+S, x0:x1] = fa[off:off+S, col][:, None]
    fc[off:off+S, x0:x1] = fc[off:off+S, col][:, None, :]
fg = np.dstack([fc, fa * 255]).astype(np.uint8)
fg_img = Image.fromarray(fg)
mono = np.dstack([np.full((L, L, 3), 255), fa * 255]).astype(np.uint8)
mono_img = Image.fromarray(mono)
bg_img = Image.new('RGBA', (L, L), (0, 119, 255, 255))
legacy = Image.open(src).convert('RGBA')
for d, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    layer = px * 108 // 48
    out = f'{res}/mipmap-{d}'
    fg_img.resize((layer, layer), Image.LANCZOS).save(f'{out}/ic_launcher_foreground.png')
    mono_img.resize((layer, layer), Image.LANCZOS).save(f'{out}/ic_launcher_monochrome.png')
    bg_img.resize((layer, layer)).save(f'{out}/ic_launcher_background.png')
    big = legacy.resize((px * 8, px * 8), Image.LANCZOS)
    m = Image.new('L', big.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius=big.width * 0.18, fill=255)
    big.putalpha(m)
    big.resize((px, px), Image.LANCZOS).save(f'{out}/ic_launcher.png')
print('ok')
