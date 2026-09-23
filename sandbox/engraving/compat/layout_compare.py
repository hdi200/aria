#!/usr/bin/env python3
"""Compare Aria's page rendering with desktop MuseScore Studio 4.7.5.

Desktop exports each score to PDF; Aria's render core (`score_render_probe`) renders
the same score. The check compares page counts and rasterizes page 1 of each at 40 dpi
(grayscale) to count differing pixels. Needs `pdfinfo`/`pdftoppm` (poppler), Pillow
and numpy.

    PAPERSIZE=letter python3 sandbox/engraving/compat/layout_compare.py --out /tmp/aria-layout

Run with the same region as the desktop (PAPERSIZE=letter on a US Mac); see README.md.
"""
import argparse
import concurrent.futures
import json
import re
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
DEFAULT_PROBE = REPO / "build-aria-475-host" / "score_render_probe"
DEFAULT_MSCORE = Path("/Applications/MuseScore 4.app/Contents/MacOS/mscore")


def key(score):
    return score.name.replace(".", "_")


def pdf_pages(pdf):
    try:
        info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return 0
    m = re.search(r"Pages:\s+(\d+)", info)
    return int(m.group(1)) if m else 0


def raster_page1(pdf, stem):
    subprocess.run(["pdftoppm", "-gray", "-r", "40", "-f", "1", "-l", "1", "-png", str(pdf), str(stem)],
                   capture_output=True, timeout=120)
    found = sorted(stem.parent.glob(stem.name + "-*.png"))
    try:
        return Image.open(found[0]).convert("L") if found else None
    except OSError:
        return None


def pixel_diff(a, b):
    if a is None or b is None:
        return None
    if abs(a.width - b.width) > 2 or abs(a.height - b.height) > 2:
        return 1.0
    w, h = min(a.width, b.width), min(a.height, b.height)
    x = np.asarray(a.crop((0, 0, w, h)), dtype=np.int16)
    y = np.asarray(b.crop((0, 0, w, h)), dtype=np.int16)
    return float((np.abs(x - y) > 64).mean())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", type=Path, help="score files (default: vtest/scores)")
    parser.add_argument("--out", type=Path, required=True, help="new output directory")
    parser.add_argument("--probe", type=Path, default=DEFAULT_PROBE)
    parser.add_argument("--mscore", type=Path, default=DEFAULT_MSCORE)
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()

    scores = args.paths or sorted(p for p in (REPO / "vtest/scores").iterdir() if p.suffix in (".mscz", ".mscx"))
    out = args.out
    (out / "ref").mkdir(parents=True, exist_ok=False)
    (out / "img").mkdir()

    jobs = [{"in": str(s), "out": str(out / "ref" / (key(s) + ".pdf"))} for s in scores]
    chunks = [jobs[i::args.jobs] for i in range(args.jobs) if jobs[i::args.jobs]]

    def export(index):
        job = out / f"job{index}.json"
        job.write_text(json.dumps(chunks[index]))
        subprocess.run([str(args.mscore), "-f", "-j", str(job)], capture_output=True, timeout=3600)
        job.unlink()

    print(f"MuseScore 4.7.5: export {len(scores)} PDFs ...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(len(chunks)) as pool:
        list(pool.map(export, range(len(chunks))))

    def compare(score):
        ref = out / "ref" / (key(score) + ".pdf")
        result = {"score": str(score), "ref_pages": pdf_pages(ref) if ref.exists() else 0}
        aria_dir = out / "aria" / key(score)
        subprocess.run([str(args.probe), str(score), "-o", str(aria_dir)], capture_output=True, timeout=300)
        pages = sorted(aria_dir.glob("page-*.pdf"))
        result["aria_pages"] = len(pages)
        ref_img = raster_page1(ref, out / "img" / (key(score) + "-ref")) if result["ref_pages"] else None
        aria_img = raster_page1(pages[0], out / "img" / (key(score) + "-aria")) if pages else None
        result["page1_diff"] = pixel_diff(ref_img, aria_img)
        return result

    print("Aria: render and compare ...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(compare, scores))
    (out / "results.json").write_text(json.dumps(results, indent=1))

    valid = [r for r in results if r["ref_pages"]]
    diffs = [r["page1_diff"] for r in valid if r["page1_diff"] is not None]
    same_pages = sum(r["aria_pages"] == r["ref_pages"] for r in valid)
    identical = sum(d < 0.001 for d in diffs)
    print(f"compared {len(valid)} scores (desktop could not export {len(results) - len(valid)})")
    print(f"same page count {same_pages}/{len(valid)}; page 1 pixel-identical {identical}/{len(diffs)}")
    for r in sorted(valid, key=lambda r: -(r["page1_diff"] or 0))[:10]:
        if r["aria_pages"] != r["ref_pages"] or (r["page1_diff"] or 0) >= 0.001:
            print(f"  {r['score']}: pages {r['ref_pages']} vs {r['aria_pages']}, page 1 differs {100 * (r['page1_diff'] or 0):.2f}%")
    return 0 if same_pages == len(valid) and identical == len(diffs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
