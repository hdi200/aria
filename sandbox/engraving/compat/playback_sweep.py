#!/usr/bin/env python3
"""Compare Aria's playback MIDI export with MuseScore Studio 4.7.5.

The default starts both exporters from a 4.7.5-saved copy. Use --direct to
export the supplied files themselves, including old or development formats.
The MIDI comparator reports pitch/count, musical beats, actual time, tempo,
velocity, instrument programs, controllers, bends, and track grouping.
"""

import argparse
import collections
import json
import sys
import time
from pathlib import Path

from playback_midi import MidiError, compare, summarize
from roundtrip_475 import (DEFAULT_CORPUS, DEFAULT_MSCORE, REPO,
                           aria_resave_all, collect_inputs, display_path,
                           job_id, mscore_convert_all)

DEFAULT_ARIA = REPO / "build-aria-compat-host" / "score_render_playback_export"


def write_report(out: Path, rows: list[dict], elapsed: float, direct: bool) -> None:
    counts = collections.Counter(row["status"] for row in rows)
    kinds = collections.Counter(issue["kind"] for row in rows for issue in row["issues"])
    warnings = collections.Counter(item["kind"] for row in rows for item in row.get("warnings", []))
    (out / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    with (out / "report.md").open("w") as report:
        report.write("# Aria versus MuseScore 4.7.5 playback MIDI\n\n")
        report.write(f"{len(rows)} scores; input mode: {'direct' if direct else '4.7.5-saved'}; {elapsed:.1f}s.\n\n")
        report.write("This compares MIDI export events, not synthesized audio.\n\n")
        report.write("| Status | Count |\n|---|---:|\n")
        for status, count in counts.most_common():
            report.write(f"| {status} | {count} |\n")
        report.write("\n| Difference | Scores |\n|---|---:|\n")
        for kind, count in kinds.most_common():
            report.write(f"| {kind} | {count} |\n")
        report.write("\n| Expected export-option difference | Scores |\n|---|---:|\n")
        for kind, count in warnings.most_common():
            report.write(f"| {kind} | {count} |\n")
        report.write("\n## Differences and failures\n")
        for row in rows:
            if row["status"] == "match":
                continue
            report.write(f"\n### {row['input']} — {row['status']}\n\n")
            if row.get("error"):
                report.write(f"{row['error']}\n\n")
            if row["issues"]:
                report.write("```json\n" + json.dumps(row["issues"], indent=2) + "\n```\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="score files/folders; defaults to round-trip corpus")
    parser.add_argument("--direct", action="store_true", help="export original files instead of 4.7.5-saved copies")
    parser.add_argument("--out", type=Path, required=True, help="new report/output directory")
    parser.add_argument("--aria-bin", type=Path, default=DEFAULT_ARIA)
    parser.add_argument("--mscore", type=Path, default=DEFAULT_MSCORE)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--tolerance-us", type=int, default=2000)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.tolerance_us < 0:
        parser.error("--tolerance-us must be nonnegative")
    for executable in (args.aria_bin, args.mscore):
        if not executable.is_file():
            parser.error(f"missing executable: {executable}")

    inputs = collect_inputs(args.paths or [p for p in DEFAULT_CORPUS if p.exists()], args.limit)
    if not inputs:
        parser.error("no scores found")
    out = args.out.resolve()
    if out.exists():
        parser.error(f"output directory already exists: {out}")
    out.mkdir(parents=True)
    work = out / "work"
    for stage in ("seed", "reference", "aria"):
        (work / stage).mkdir(parents=True)
    ids = {p: job_id(p) for p in inputs}
    seed = {p: work / "seed" / f"{ids[p]}.mscz" for p in inputs}
    reference = {p: work / "reference" / f"{ids[p]}.mid" for p in inputs}
    aria = {p: work / "aria" / f"{ids[p]}.mid" for p in inputs}
    started = time.monotonic()
    print(f"{len(inputs)} scores; {args.jobs} workers; {'direct' if args.direct else '4.7.5-saved'} input", flush=True)

    if args.direct:
        export_inputs = inputs
        seeded = set(inputs)
    else:
        print("MuseScore 4.7.5: normalize source scores ...", flush=True)
        seeded = mscore_convert_all(args.mscore, [(p, seed[p]) for p in inputs], work,
                                    args.jobs, True, "seed")
        export_inputs = [seed[p] for p in inputs if seed[p] in seeded]
    origin = {p: p if args.direct else seed[p] for p in inputs}
    eligible = [p for p in inputs if origin[p] in export_inputs]

    print("MuseScore 4.7.5: export reference MIDI ...", flush=True)
    reference_ok = mscore_convert_all(args.mscore, [(origin[p], reference[p]) for p in eligible],
                                      work, args.jobs, False, "reference-midi")
    print("Aria: export playback MIDI ...", flush=True)
    aria_results = aria_resave_all(args.aria_bin, [(origin[p], aria[p]) for p in eligible],
                                   work, args.jobs)

    rows = []
    for path in inputs:
        row = {"input": display_path(path), "status": "", "issues": [], "warnings": [], "error": "",
               "reference_midi": str(reference[path]), "aria_midi": str(aria[path])}
        if path not in eligible:
            row["status"] = "reference-cannot-open-input"
        elif reference[path] not in reference_ok:
            row["status"] = "reference-export-failed"
        elif aria_results.get(str(origin[path]), ("FAIL",))[0] != "OK" or not aria[path].exists():
            row["status"] = "aria-export-failed"
            row["error"] = aria_results.get(str(origin[path]), ("FAIL", "no output"))[1]
        else:
            try:
                result = compare(summarize(reference[path]), summarize(aria[path]), args.tolerance_us)
                row.update(result)
            except (OSError, MidiError, ValueError) as exc:
                row["status"] = "compare-error"
                row["error"] = str(exc)
        rows.append(row)
    elapsed = time.monotonic() - started
    write_report(out, rows, elapsed, args.direct)
    counts = collections.Counter(row["status"] for row in rows)
    print(" ".join(f"{status}={count}" for status, count in counts.most_common()))
    print(f"report: {out / 'report.md'}")
    return 0 if counts == {"match": len(rows)} else 1


if __name__ == "__main__":
    sys.exit(main())
