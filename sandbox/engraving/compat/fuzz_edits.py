#!/usr/bin/env python3
"""Random-edit stress test over many scores.

Runs build-aria-475-host/score_render_fuzz (tests/score_render_fuzz.cpp) on each score in its
own process, so a crash or hang is reported instead of stopping the run, then checks every
final score in desktop MuseScore 4.7.5 (roundtrip_475.py --direct). See the harness for what
each failure kind means.

    cmake --build build-aria-475-host --target score_render_fuzz score_render_resave
    python3 sandbox/engraving/compat/fuzz_edits.py                       # default corpus sample
    python3 sandbox/engraving/compat/fuzz_edits.py ~/scores --steps 400 --seed 7

Same seed, same scores, same edits: every failure lists a REPRO command. The report goes to
<out>/report.md and the exit code is non-zero if anything failed.
"""

import argparse
import concurrent.futures
import os
import random
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
HARNESS = REPO / "build-aria-475-host" / "score_render_fuzz"
ROUNDTRIP = REPO / "sandbox" / "engraving" / "compat" / "roundtrip_475.py"
DEFAULT_CORPUS = [
    REPO / "MuseReaderiOS" / "MuseReaderiOS" / "Resources" / "ScoreTemplates.bundle",
    REPO / "vtest" / "scores",
    REPO / "demos",
]


def collect(paths):
    scores = []
    for root in paths:
        root = Path(root)
        if root.is_file():
            scores.append(root)
            continue
        scores.extend(p for p in sorted(root.rglob("*")) if p.suffix in (".mscz", ".mscx") and "-ref" not in p.stem)
    return scores


def run_one(score, seed, args, out):
    command = [str(HARNESS), "--score", str(score), "--seed", str(seed), "--steps", str(args.steps),
               "--check-every", str(args.check_every), "--out", str(out)]
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    started = time.time()
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout, env=env)
        output, code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as expired:
        output = expired.stdout.decode() if isinstance(expired.stdout, bytes) else (expired.stdout or "")
        code = "timeout"
    lines = [line for line in output.splitlines() if re.match(r"(STEP|PROBE|FAIL|REPRO|DONE|SKIP|NOTE)\b", line)]
    failures = []
    for index, line in enumerate(lines):
        if line.startswith("FAIL"):
            repro = lines[index + 1] if index + 1 < len(lines) and lines[index + 1].startswith("REPRO") else ""
            kind = line.split()[3].rstrip(":") if len(line.split()) > 3 else "?"
            failures.append((kind, line, repro))
    if code == "timeout" or (isinstance(code, int) and code < 0):
        last_step = next((line for line in reversed(lines) if line.startswith(("STEP", "PROBE"))), "before the first step")
        kind = "hang" if code == "timeout" else "crash"
        repro = (f"REPRO score_render_fuzz --score '{score}' --seed {seed} --steps {args.steps} "
                 f"--check-every {args.check_every} --out <dir>")
        failures.append((kind, f"{kind.upper()} ({code}) last: {last_step}", repro))
    steps = sum(1 for line in lines if line.startswith("STEP"))
    refused = sum(1 for line in lines if line.startswith("STEP") and " refused" in line)
    return score, seed, steps, refused, failures, time.time() - started, any(l.startswith("SKIP") for l in lines)


def desktop_check(out):
    final = out / "final"
    if not final.exists() or not any(final.rglob("*.mscx")):
        return None, []
    report_dir = out / "desktop-roundtrip"
    subprocess.run([sys.executable, str(ROUNDTRIP), str(final), "--direct", "--out", str(report_dir)],
                   capture_output=True, text=True)
    report = (report_dir / "report.md").read_text() if (report_dir / "report.md").exists() else ""
    counts = dict(re.findall(r"^\| (\S[^|]*?) \| (\d+) \|$", report, re.M))
    problems = [line for line in report.splitlines() if re.search(r"cannot-open|changed", line) and "|" in line]
    return counts, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", help="score files or folders (default: templates, vtest, demos)")
    parser.add_argument("--scores", type=int, default=40, help="random sample size (0 = all)")
    parser.add_argument("--steps", type=int, default=150)
    parser.add_argument("--check-every", type=int, default=10)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument("--timeout", type=int, default=600, help="seconds per score before it counts as a hang")
    parser.add_argument("--out", default=str(REPO / "build-aria-475-host" / "fuzz"))
    parser.add_argument("--no-desktop", action="store_true", help="skip the desktop 4.7.5 check of final files")
    args = parser.parse_args()

    if not HARNESS.exists():
        sys.exit(f"Build the harness first: cmake --build build-aria-475-host --target score_render_fuzz ({HARNESS})")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    scores = collect(args.paths or DEFAULT_CORPUS)
    random.Random(args.seed).shuffle(scores)
    if args.scores:
        scores = scores[: args.scores]

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_one, score, args.seed * 1000 + index, args, out) for index, score in enumerate(scores)]
        for future in concurrent.futures.as_completed(futures):
            score, seed, steps, refused, failures, elapsed, skipped = future.result()
            results.append(future.result())
            status = "skip" if skipped else (f"{len(failures)} failure(s)" if failures else "ok")
            print(f"{status:>14}  {elapsed:6.1f}s  {steps:4d} steps  {score}", flush=True)

    counts, desktop_problems = (None, []) if args.no_desktop else desktop_check(out)

    by_kind = Counter()
    grouped = defaultdict(list)
    for score, seed, steps, refused, failures, elapsed, skipped in results:
        for kind, line, repro in failures:
            by_kind[kind] += 1
            grouped[kind].append((score, line, repro))
    total_steps = sum(r[2] for r in results)
    total_refused = sum(r[3] for r in results)

    report = [f"# Random-edit stress test", "",
              f"{len(results)} scores, {total_steps} edits ({total_refused} refused by the command, which is normal), seed {args.seed}", ""]
    report.append("| failure | count |\n|---|---|")
    for kind in ("crash", "hang", "state", "corruption", "save", "reopen", "stale", "roundtrip", "undo"):
        report.append(f"| {kind} | {by_kind.get(kind, 0)} |")
    if counts is not None:
        report += ["", "Desktop 4.7.5 on the final scores: " + ", ".join(f"{k} {v}" for k, v in counts.items())]
        report += [f"- {line}" for line in desktop_problems[:20]]
    for kind, entries in grouped.items():
        report += ["", f"## {kind} ({len(entries)})", ""]
        for score, line, repro in entries[:25]:
            report += [f"- `{score.relative_to(REPO) if score.is_relative_to(REPO) else score}`", f"  - {line[:400]}",
                       f"  - `{repro}`"]
    (out / "report.md").write_text("\n".join(report) + "\n")
    print("\n".join(report[:16]))
    print(f"\nFull report: {out / 'report.md'}")
    failed = sum(by_kind.values()) + (len(desktop_problems) if desktop_problems else 0)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
