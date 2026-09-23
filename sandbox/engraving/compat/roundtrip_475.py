#!/usr/bin/env python3
"""Round-trip check: do scores saved by Aria come back intact in MuseScore 4.7.5?

The question is whether Aria can stand in for MuseScore 4.7.5 for one open-and-save
without changing the score. For every input score X, with S the starting file:

  ref  = 4.7.5 opens S and saves, then 4.7.5 opens that and saves again
  cand = Aria  opens S and saves (its real save path), then 4.7.5 opens that and saves

Both results pass through the same number of saves and end with a MuseScore 4.7.5
save, so MuseScore's own quirks cancel out. Any difference between ref and cand is
something the Aria step lost or changed.

S is, by default, X re-saved once by MuseScore 4.7.5, i.e. the kind of file a
4.7.5 user actually has. With --direct, S is X itself, which also tests how Aria
reads older formats (2.x, 3.x, early 4.x) compared with 4.7.5.

Also reported:
  refused  MuseScore 4.7.5 would not open Aria's file without --force
  dropped  XML tags in Aria's file that 4.7.5 silently discarded (beyond what it
           discards from its own files)

Usage:
  roundtrip_475.py [paths...]      default corpus: vtest/scores, Aria templates, compat fixtures
  roundtrip_475.py --direct vtest/scores
  roundtrip_475.py my-scores/ --jobs 8

Build the resave tool first (see compat/README.md). Standard library only.
"""

import argparse
import collections
import concurrent.futures
import difflib
import hashlib
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DEFAULT_RESAVE = REPO / "build-aria-475-host" / "score_render_resave"
DEFAULT_MSCORE = Path("/Applications/MuseScore 4.app/Contents/MacOS/mscore")
DEFAULT_OUT = REPO / "build-aria-475-host" / "roundtrip"
DEFAULT_CORPUS = [
    REPO / "vtest" / "scores",
    REPO / "MuseReaderiOS" / "MuseReaderiOS" / "Resources" / "ScoreTemplates.bundle",
    REPO / "sandbox" / "engraving" / "compat" / "fixtures",
]

# Files inside an .mscz that carry score content. Thumbnails, audio/view settings and
# META-INF are app state, not notation.
CONTENT_SUFFIXES = (".mscx", ".mss", ".xml")

RESAVE_IDLE_TIMEOUT = 180  # seconds without output before a resave worker is killed
MSCORE_JOB_TIMEOUT = 900


# --------------------------------------------------------------------------- corpus

def collect_inputs(paths, limit):
    inputs = []
    for root in paths:
        root = Path(root).resolve()
        if root.is_file():
            inputs.append(root)
            continue
        for path in sorted(root.rglob("*")):
            if any(part.startswith(".") for part in path.relative_to(root).parts):
                continue
            if path.suffix in (".mscz", ".mscx") and path.is_file():
                inputs.append(path)
    inputs = sorted(set(inputs))
    return inputs[:limit] if limit else inputs


def job_id(path):
    digest = hashlib.sha1(str(path).encode()).hexdigest()[:8]
    return f"{re.sub(r'[^A-Za-z0-9_-]+', '_', path.stem)[:60]}-{digest}"


def file_version(path):
    try:
        if path.suffix == ".mscz":
            with zipfile.ZipFile(path) as zf:
                name = next(n for n in zf.namelist() if n.endswith(".mscx") and "/" not in n)
                head = zf.read(name)[:400].decode("utf-8", "replace")
        else:
            head = path.read_bytes()[:400].decode("utf-8", "replace")
    except Exception:
        return "?"
    match = re.search(r'<museScore version="([0-9.]+)"', head)
    return match.group(1) if match else "?"


def display_path(path):
    return str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path)


# --------------------------------------------------------------------------- Aria resave

def run_resave_chunk(resave_bin, jobs, work):
    """Run one resave worker over jobs, restarting after crashes/hangs.
    Returns {input: (status, message)}."""
    results = {}
    pending = list(jobs)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    while pending:
        manifest = work / f"manifest-{job_id(pending[0][0])}.tsv"
        manifest.write_text("".join(f"{src}\t{dst}\n" for src, dst in pending))
        proc = subprocess.Popen([str(resave_bin), "--manifest", str(manifest)], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, errors="replace", env=env)
        lines = queue.Queue()
        reader = threading.Thread(target=lambda: [lines.put(l) for l in proc.stdout] + [lines.put(None)], daemon=True)
        reader.start()
        reported = set()
        while True:
            try:
                line = lines.get(timeout=RESAVE_IDLE_TIMEOUT)
            except queue.Empty:  # hung on one score
                proc.kill()
                break
            if line is None:
                break
            parts = line.rstrip("\n").split("\t")
            if parts[0] in ("OK", "FAIL") and len(parts) >= 2:
                results[parts[1]] = (parts[0], parts[2] if len(parts) > 2 else "")
                reported.add(parts[1])
        proc.wait()
        manifest.unlink(missing_ok=True)

        remaining = [job for job in pending if str(job[0]) not in reported]
        if remaining:
            # The first unreported job crashed or hung the worker; record it and move on.
            reason = "timeout" if proc.returncode in (-9, None) else f"crash (exit {proc.returncode})"
            results[str(remaining[0][0])] = ("FAIL", reason)
            remaining = remaining[1:]
        pending = remaining
    return results


def aria_resave_all(resave_bin, jobs, work, parallel):
    chunks = [jobs[i::parallel] for i in range(parallel) if jobs[i::parallel]]
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(chunks) or 1) as pool:
        for part in pool.map(lambda c: run_resave_chunk(resave_bin, c, work), chunks):
            results.update(part)
    return results


# --------------------------------------------------------------------------- MuseScore 4.7.5

def mscore_convert_all(mscore, pairs, work, parallel, force, label):
    """Convert (src, dst) pairs with MuseScore 4.7.5. Returns the set of dst that exist.

    Batches go through job files for speed. MuseScore can stop a job at a file it
    cannot open (or crash on exit), so anything still missing is retried one by one.
    """
    flags = ["-f"] if force else []

    def run(args, timeout):
        try:
            subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
        except subprocess.TimeoutExpired:
            pass

    def run_job(chunk, index):
        job = work / f"job-{label}-{index}.json"
        job.write_text(json.dumps([{"in": str(s), "out": str(d)} for s, d in chunk]))
        run([str(mscore)] + flags + ["-j", str(job)], MSCORE_JOB_TIMEOUT)
        job.unlink(missing_ok=True)

    chunks = [pairs[i::parallel] for i in range(parallel) if pairs[i::parallel]]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(chunks) or 1) as pool:
        list(pool.map(run_job, chunks, range(len(chunks))))

    missing = [(s, d) for s, d in pairs if not Path(d).exists()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=parallel) as pool:
        list(pool.map(lambda sd: run([str(mscore)] + flags + ["-o", str(sd[1]), str(sd[0])], 300), missing))

    return {d for _, d in pairs if Path(d).exists()}


# --------------------------------------------------------------------------- comparison

EID_RE = re.compile(r"<(eid|linkedMain|linked|linkedTo)>[^<]*</\1>")
TAG_RE = re.compile(r"<([A-Za-z_][\w.-]*)[\s/>]")


def read_members(mscz):
    members = {}
    with zipfile.ZipFile(mscz) as zf:
        for name in zf.namelist():
            if name.endswith(CONTENT_SUFFIXES) and not name.startswith("META-INF"):
                text = zf.read(name).decode("utf-8", "replace")
                # MuseScore names the main score after the container file.
                members["score.mscx" if "/" not in name and name.endswith(".mscx") else name] = text
    return members


def normalize(xml):
    xml = EID_RE.sub(lambda m: f"<{m.group(1)}/>", xml)
    return [line.strip() for line in xml.splitlines() if line.strip()]


def tags_in(xml):
    return set(TAG_RE.findall(xml))


def compare(ref_path, cand_path, start_path, mid_path, aria_path):
    ref, cand = read_members(ref_path), read_members(cand_path)
    changes = []
    changed_tags = collections.Counter()
    for name in sorted(set(ref) | set(cand)):
        if name not in cand:
            changes.append(f"missing after Aria round trip: {name}")
            continue
        if name not in ref:
            changes.append(f"extra after Aria round trip: {name}")
            continue
        a, b = normalize(ref[name]), normalize(cand[name])
        if a == b:
            continue
        diff = [l for l in difflib.unified_diff(a, b, lineterm="", n=0) if l[:1] in "+-" and l[:3] not in ("+++", "---")]
        for line in diff:
            m = TAG_RE.search(line)
            if m:
                changed_tags[m.group(1)] += 1
        changes.append(f"{name}: {len(diff)} changed lines")
        changes.extend("    " + l for l in diff[:40])
        if len(diff) > 40:
            changes.append(f"    ... {len(diff) - 40} more")

    # Tags Aria wrote that 4.7.5 discarded on reading, minus what 4.7.5 discards from
    # its own files anyway (start -> mid).
    dropped = {}
    aria, start, mid = read_members(aria_path), read_members(start_path), read_members(mid_path)
    if "score.mscx" in aria and "score.mscx" in cand:
        own_drops = tags_in(start.get("score.mscx", "")) - tags_in(mid.get("score.mscx", ""))
        for tag in tags_in(aria["score.mscx"]) - tags_in(cand["score.mscx"]) - own_drops:
            dropped[tag] = aria["score.mscx"].count(f"<{tag}")
    return changes, changed_tags, dropped


# --------------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", help="score files or folders (default: vtest + Aria templates + fixtures)")
    parser.add_argument("--direct", action="store_true", help="give Aria the original file instead of a 4.7.5 re-save")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="work/report folder (wiped each run)")
    parser.add_argument("--resave-bin", default=str(DEFAULT_RESAVE))
    parser.add_argument("--mscore", default=str(DEFAULT_MSCORE))
    parser.add_argument("--jobs", type=int, default=max(2, (os.cpu_count() or 4) // 2))
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    resave_bin, mscore = Path(args.resave_bin), Path(args.mscore)
    for tool in (resave_bin, mscore):
        if not tool.exists():
            sys.exit(f"missing tool: {tool}")

    inputs = collect_inputs(args.paths or [p for p in DEFAULT_CORPUS if p.exists()], args.limit)
    if not inputs:
        sys.exit("no scores found")

    out = Path(args.out)
    shutil.rmtree(out, ignore_errors=True)
    work = out / "work"
    for sub in ("seed", "mid", "ref", "aria", "cand"):
        (work / sub).mkdir(parents=True)

    ids = {p: job_id(p) for p in inputs}
    paths = {p: {stage: work / stage / f"{ids[p]}.mscz" for stage in ("seed", "mid", "ref", "aria", "cand")} for p in inputs}
    started = time.time()
    mode = "direct (original files)" if args.direct else "4.7.5-saved copies"
    print(f"{len(inputs)} scores, {args.jobs} workers, Aria starts from {mode}")

    def mscore_stage(label, pairs, force):
        print(f"  MuseScore 4.7.5: {label} ...", flush=True)
        return mscore_convert_all(mscore, pairs, work, args.jobs, force, label)

    seeded = mscore_stage("seed", [(p, paths[p]["seed"]) for p in inputs], force=True)
    start = {p: (p if args.direct else paths[p]["seed"]) for p in inputs}
    if args.direct:
        paths_mid = {p: paths[p]["seed"] for p in inputs}  # 4.7.5(X) is already the first pass
        mid_ok = seeded
    else:
        paths_mid = {p: paths[p]["mid"] for p in inputs}
        mid_ok = mscore_stage("mid", [(paths[p]["seed"], paths_mid[p]) for p in inputs if paths[p]["seed"] in seeded], force=False)
    ref_ok = mscore_stage("ref", [(paths_mid[p], paths[p]["ref"]) for p in inputs if paths_mid[p] in mid_ok], force=False)

    print("  Aria save ...", flush=True)
    aria_inputs = [p for p in inputs if args.direct or paths[p]["seed"] in seeded]
    aria_results = aria_resave_all(resave_bin, [(start[p], paths[p]["aria"]) for p in aria_inputs], work, args.jobs)

    cand_pairs = [(paths[p]["aria"], paths[p]["cand"]) for p in aria_inputs
                  if aria_results.get(str(start[p]), ("FAIL",))[0] == "OK"]
    cand_ok = mscore_stage("reopen Aria's files", cand_pairs, force=False)

    rows = []
    for p in inputs:
        row = {"input": display_path(p), "version": file_version(p), "status": "", "detail": [],
               "changed_tags": {}, "dropped": {}}
        if p not in aria_inputs:
            row["status"] = "4.7.5-cannot-open-input"
        elif aria_results.get(str(start[p]), ("FAIL",))[0] != "OK":
            row["status"], row["detail"] = "aria-save-failed", [aria_results.get(str(start[p]), ("FAIL", "not run"))[1]]
        elif paths[p]["cand"] not in cand_ok:
            row["status"] = "refused-by-4.7.5"
        elif paths[p]["ref"] not in ref_ok:
            row["status"] = "no-reference"
        else:
            try:
                changes, changed_tags, dropped = compare(paths[p]["ref"], paths[p]["cand"], start[p] if not args.direct else paths[p]["seed"],
                                                         paths_mid[p] if not args.direct else paths[p]["ref"], paths[p]["aria"])
            except Exception as error:  # corrupt zip etc.
                row["status"], row["detail"] = "compare-error", [repr(error)]
            else:
                row["changed_tags"], row["dropped"], row["detail"] = dict(changed_tags), dropped, changes
                row["status"] = "changed" if changes else ("dropped-tags" if dropped else "identical")
        rows.append(row)

    write_report(out, rows, mode, time.time() - started)
    summary = collections.Counter(r["status"] for r in rows)
    print()
    for status, count in summary.most_common():
        print(f"  {status:26s} {count}")
    print(f"\nreport: {out / 'report.md'}")
    bad = sum(count for status, count in summary.items() if status not in ("identical", "4.7.5-cannot-open-input"))
    return 1 if bad else 0


def write_report(out, rows, mode, elapsed):
    summary = collections.Counter(r["status"] for r in rows)
    statuses = sorted(summary)
    by_version = collections.defaultdict(collections.Counter)
    tag_totals, dropped_totals = collections.Counter(), collections.Counter()
    for r in rows:
        by_version[r["version"]][r["status"]] += 1
        tag_totals.update(r["changed_tags"].keys())
        dropped_totals.update(r["dropped"].keys())

    (out / "results.json").write_text(json.dumps(rows, indent=1))
    with open(out / "report.md", "w") as report:
        report.write(f"# MuseScore 4.7.5 round-trip report\n\n{len(rows)} scores, Aria started from {mode}, {elapsed:.0f}s\n\n")
        report.write("| status | count |\n|---|---|\n")
        for status, count in summary.most_common():
            report.write(f"| {status} | {count} |\n")
        report.write("\n## By source file version\n\n| version | " + " | ".join(statuses) + " |\n")
        report.write("|---|" + "---|" * len(statuses) + "\n")
        for version in sorted(by_version):
            report.write(f"| {version} | " + " | ".join(str(by_version[version][s]) for s in statuses) + " |\n")
        report.write("\n## Tags that differ after the round trip (number of scores)\n\n")
        for tag, count in tag_totals.most_common(60):
            report.write(f"- `{tag}`: {count}\n")
        report.write("\n## Tags in Aria's file that 4.7.5 silently dropped (number of scores)\n\n")
        for tag, count in dropped_totals.most_common(60):
            report.write(f"- `{tag}`: {count}\n")
        report.write("\n## Details\n")
        for r in rows:
            if r["status"] == "identical":
                continue
            report.write(f"\n### {r['input']} ({r['version']}): {r['status']}\n\n")
            if r["dropped"]:
                report.write("dropped by 4.7.5: " + ", ".join(f"{t}×{c}" for t, c in r["dropped"].items()) + "\n\n")
            if r["detail"]:
                report.write("```\n" + "\n".join(r["detail"][:120]) + "\n```\n")


if __name__ == "__main__":
    sys.exit(main())
