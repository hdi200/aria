#!/usr/bin/env python3
"""Find edits that change a score without redrawing it.

score_render_edit_sweep_tests writes, for every edit (and its undo), page 1 as the live
session draws it (`<case>-live.pdf`) and as a fresh session draws the saved copy
(`<case>-reopened.pdf`) when run with ARIA_STALE_RENDER_DIR set. A difference means the
live view is out of date: what the user sees is not what was saved.

    ARIA_STALE_RENDER_DIR=/tmp/aria-stale build-aria-475-host/score_render_edit_sweep_tests
    python3 sandbox/engraving/compat/compare_stale_renders.py /tmp/aria-stale

Needs pdftoppm (poppler) and Pillow. Exit code is non-zero if any page differs.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

DPI = 72
# Pixels whose grey level differs by more than this count as changed (ignores anti-aliasing).
LEVEL_THRESHOLD = 96
# A page differs if more changed pixels than this remain.
PIXEL_THRESHOLD = 12


def rasterize(pdf: Path, out_dir: Path) -> Image.Image:
    prefix = out_dir / pdf.stem
    subprocess.run(["pdftoppm", "-r", str(DPI), "-gray", "-singlefile", "-png", str(pdf), str(prefix)],
                   check=True, capture_output=True)
    return Image.open(f"{prefix}.png").convert("L")


def changed_pixels(a: Image.Image, b: Image.Image) -> int:
    if a.size != b.size:
        return a.size[0] * a.size[1]
    diff = ImageChops.difference(a, b).point(lambda v: 255 if v > LEVEL_THRESHOLD else 0)
    return sum(1 for v in diff.getdata() if v)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    folder = Path(sys.argv[1])
    stale = []
    pairs = sorted(folder.glob("*-live.pdf"))
    with tempfile.TemporaryDirectory() as tmp:
        for live in pairs:
            reopened = live.with_name(live.name.replace("-live.pdf", "-reopened.pdf"))
            if not reopened.exists() or live.stat().st_size == 0 or reopened.stat().st_size == 0:
                stale.append((live.name.replace("-live.pdf", ""), "missing render"))
                continue
            count = changed_pixels(rasterize(live, Path(tmp)), rasterize(reopened, Path(tmp)))
            if count > PIXEL_THRESHOLD:
                stale.append((live.name.replace("-live.pdf", ""), f"{count} pixels differ"))
    print(f"{len(pairs) - len(stale)}/{len(pairs)} edits draw the same live as after reopening")
    for name, reason in stale:
        print(f"  STALE {name}: {reason}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
