#!/usr/bin/env python3
"""Compare Aria MusicXML export with MuseScore Studio 4.7.5 on the same score.

Each input is first normalized to an MSCZ with MuseScore 4.7.5. Both programs
export MusicXML from that exact file. MuseScore then imports each export and
exports MusicXML again. The comparison uses those two re-exports, so harmless
MusicXML spelling differences cancel out while lost musical content remains.

The comparison covers parts, notes/rests and their timing, voices/staves,
ties, lyrics, chord symbols, dynamics, and tempo. It deliberately does not
assert page layout, fonts, spanner geometry, or playback interpretation.

Example:
  python3 sandbox/engraving/compat/musicxml_export_sweep.py \
    vtest/scores/lyrics-6.mscx vtest/scores/harmony-22.mscz
"""

import argparse
import collections
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from fractions import Fraction
from pathlib import Path

from roundtrip_475 import DEFAULT_CORPUS, aria_resave_all, collect_inputs, mscore_convert_all


REPO = Path(__file__).resolve().parents[3]
DEFAULT_ARIA = REPO / "build-aria-475-host" / "score_render_musicxml_export"
DEFAULT_MSCORE = Path("/Applications/MuseScore 4.app/Contents/MacOS/mscore")
DEFAULT_OUT_PARENT = REPO / "build-aria-475-host" / "musicxml-export"


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def child(element, name):
    return next((item for item in element if local_name(item.tag) == name), None)


def children(element, name):
    return [item for item in element if local_name(item.tag) == name]


def text_of(element, name, default=""):
    item = child(element, name) if element is not None else None
    return "" if item is not None and item.text is None else (item.text if item is not None else default)


def number(value, default=0):
    try:
        return int(value)
    except (ValueError, TypeError):
        return default


def fraction_text(value):
    return str(value.numerator) if value.denominator == 1 else f"{value.numerator}/{value.denominator}"


def duration(element, divisions):
    return Fraction(number(text_of(element, "duration")), divisions)


def pitch_identity(note):
    pitch = child(note, "pitch")
    if pitch is not None:
        return ("pitch", text_of(pitch, "step"), text_of(pitch, "alter", "0"), text_of(pitch, "octave"))
    unpitched = child(note, "unpitched")
    if unpitched is not None:
        return ("unpitched", text_of(unpitched, "display-step"), text_of(unpitched, "display-octave"))
    return ("rest",)


def harmony_identity(harmony):
    root = child(harmony, "root")
    bass = child(harmony, "bass")
    kind = child(harmony, "kind")
    degrees = []
    for degree in children(harmony, "degree"):
        degrees.append((text_of(degree, "degree-value"), text_of(degree, "degree-alter"),
                        text_of(degree, "degree-type")))
    return (text_of(root, "root-step"), text_of(root, "root-alter", "0"),
            text_of(kind, "kind") if kind is not None else "", kind.get("text", "") if kind is not None else "",
            text_of(bass, "bass-step"), text_of(bass, "bass-alter", "0"), tuple(degrees),
            text_of(harmony, "staff", "1"))


def semantic_events(path):
    root = ET.parse(path).getroot()
    if local_name(root.tag) != "score-partwise":
        raise ValueError(f"expected score-partwise MusicXML, got {local_name(root.tag)}")

    part_list = child(root, "part-list")
    descriptors = {}
    if part_list is not None:
        for score_part in children(part_list, "score-part"):
            descriptors[score_part.get("id")] = (
                text_of(score_part, "part-name"), text_of(score_part, "part-abbreviation"))

    events = collections.defaultdict(collections.Counter)
    for part_index, part in enumerate(children(root, "part")):
        part_id = part.get("id")
        events["parts"][(part_index, *descriptors.get(part_id, ("", "")))] += 1
        divisions = 1
        staff_count = 1
        for measure_index, measure in enumerate(children(part, "measure")):
            cursor = Fraction(0)
            previous_note_onset = Fraction(0)
            for item in measure:
                tag = local_name(item.tag)
                if tag == "attributes":
                    divisions = max(1, number(text_of(item, "divisions"), divisions))
                    staff_count = max(staff_count, number(text_of(item, "staves"), staff_count))
                elif tag == "backup":
                    cursor -= duration(item, divisions)
                elif tag == "forward":
                    cursor += duration(item, divisions)
                elif tag == "note":
                    is_chord = child(item, "chord") is not None
                    onset = previous_note_onset if is_chord else cursor
                    length = duration(item, divisions)
                    if not is_chord:
                        previous_note_onset = onset
                        cursor += length
                    ties = tuple(sorted(t.get("type", "") for t in children(item, "tie")))
                    note_key = (part_index, measure_index, fraction_text(onset), fraction_text(length),
                                text_of(item, "voice", "1"), text_of(item, "staff", "1"),
                                pitch_identity(item), child(item, "grace") is not None, ties)
                    events["notes"][note_key] += 1
                    for lyric in children(item, "lyric"):
                        lyric_text = "".join((word.text or "") for word in children(lyric, "text"))
                        lyric_extend = child(lyric, "extend")
                        lyric_key = (part_index, measure_index, fraction_text(onset),
                                     text_of(item, "voice", "1"), lyric.get("number", ""),
                                     lyric_text, text_of(lyric, "syllabic"),
                                     lyric_extend.get("type", "") if lyric_extend is not None else "")
                        events["lyrics"][lyric_key] += 1
                elif tag == "harmony":
                    offset = Fraction(number(text_of(item, "offset")), divisions)
                    events["chords"][(part_index, measure_index, fraction_text(cursor + offset),
                                      harmony_identity(item))] += 1
                elif tag == "direction":
                    offset = Fraction(number(text_of(item, "offset")), divisions)
                    staff = text_of(item, "staff", "1")
                    for direction_type in children(item, "direction-type"):
                        dynamics = child(direction_type, "dynamics")
                        if dynamics is not None:
                            for dynamic in dynamics:
                                events["dynamics"][(part_index, measure_index,
                                                    fraction_text(cursor + offset), staff,
                                                    local_name(dynamic.tag), dynamic.text or "")] += 1
                    sound = child(item, "sound")
                    if sound is not None and "tempo" in sound.attrib:
                        events["tempo"][(part_index, measure_index, fraction_text(cursor + offset),
                                         sound.get("tempo"))] += 1
        events["staves"][(part_index, staff_count)] += 1
    return dict(events)


def compare_semantics(reference, candidate, limit=8):
    differences = {}
    for category in sorted(set(reference) | set(candidate)):
        missing = reference.get(category, collections.Counter()) - candidate.get(category, collections.Counter())
        extra = candidate.get(category, collections.Counter()) - reference.get(category, collections.Counter())
        if missing or extra:
            differences[category] = {
                "missing_count": sum(missing.values()),
                "extra_count": sum(extra.values()),
                "missing_examples": [repr(item) for item in list(missing.elements())[:limit]],
                "extra_examples": [repr(item) for item in list(extra.elements())[:limit]],
            }
    return differences


def job_name(path):
    safe_name = re.sub(r"[^A-Za-z0-9_-]+", "_", path.stem)[:60]
    return f"{safe_name}-{hashlib.sha1(str(path).encode()).hexdigest()[:8]}"


def valid_output(path):
    if not path.is_file() or path.stat().st_size == 0:
        return False
    if path.suffix == ".mscz":
        return zipfile.is_zipfile(path)
    try:
        ET.parse(path)
    except (ET.ParseError, OSError):
        return False
    return True


def make_records(scores, out):
    records = []
    for score in scores:
        work = out / job_name(score)
        work.mkdir()
        records.append({"score": str(score), "status": "pending", "work": str(work),
                        "source": score, "start": work / "start.mscz",
                        "desktop_xml": work / "desktop.musicxml", "aria_xml": work / "aria.musicxml",
                        "desktop_import": work / "desktop-import.mscz",
                        "aria_import": work / "aria-import.mscz",
                        "desktop_round": work / "desktop-round.musicxml",
                        "aria_round": work / "aria-round.musicxml"})
    return records


def active_records(records):
    return [record for record in records if record["status"] == "pending"]


def fail(record, stage, reason):
    reference_stages = {"normalize", "desktop-export", "desktop-import", "desktop-re-export"}
    origin = "reference" if stage in reference_stages else "candidate" if stage.startswith("aria-") else "comparison"
    record.update(status="failed", stage=stage, origin=origin, error=reason)


def mscore_stage(records, source_key, output_key, mscore, out, jobs, force, label):
    active = active_records(records)
    if not active:
        return
    print(f"{label}: converting {len(active)} scores", flush=True)
    pairs = [(record[source_key], record[output_key]) for record in active]
    batch_error = ""
    try:
        produced = mscore_convert_all(mscore, pairs, out, jobs, force, label)
    except (OSError, RuntimeError, ValueError) as error:
        batch_error = f"; batch error: {error}"
        produced = set()
    # A desktop process may crash on exit after writing a complete file. As in
    # roundtrip_475.py, the output itself decides whether the job succeeded.
    for record in active:
        output = record[output_key]
        if output not in produced and not valid_output(output):
            fail(record, label, f"MuseScore did not produce a valid {output.suffix} file{batch_error}")
        elif not valid_output(output):
            fail(record, label, f"MuseScore produced an invalid {output.suffix} file{batch_error}")


def aria_stage(records, aria, out, jobs):
    active = active_records(records)
    if not active:
        return
    print(f"aria-export: exporting {len(active)} scores", flush=True)
    pairs = [(record["start"], record["aria_xml"]) for record in active]
    batch_error = ""
    try:
        statuses = aria_resave_all(aria, pairs, out, jobs)
    except (OSError, RuntimeError, ValueError) as error:
        batch_error = f"; batch error: {error}"
        statuses = {}
    for record in active:
        status, message = statuses.get(str(record["start"]), ("FAIL", "no result"))
        # Like MuseScore, the host CLI can finish writing XML before its process
        # exits abnormally. A parsed, nonempty output is the success criterion.
        if not valid_output(record["aria_xml"]):
            reason = message if status != "OK" and message else "Aria did not produce valid MusicXML"
            fail(record, "aria-export", reason + batch_error)


def compare_record(record):
    if record["status"] != "pending":
        return record
    try:
        direct_diff = compare_semantics(semantic_events(record["desktop_xml"]), semantic_events(record["aria_xml"]))
        imported_diff = compare_semantics(semantic_events(record["desktop_round"]), semantic_events(record["aria_round"]))
        record.update(status="same" if not imported_diff else "changed", direct=direct_diff,
                      after_desktop_import=imported_diff)
    except (OSError, ValueError, ET.ParseError) as error:
        fail(record, "compare", str(error))
    return record


def run_sweep(scores, out, aria, mscore, jobs, force):
    records = make_records(scores, out)
    mscore_stage(records, "source", "start", mscore, out, jobs, force, "normalize")
    mscore_stage(records, "start", "desktop_xml", mscore, out, jobs, False, "desktop-export")
    aria_stage(records, aria, out, jobs)
    mscore_stage(records, "desktop_xml", "desktop_import", mscore, out, jobs, False, "desktop-import")
    mscore_stage(records, "aria_xml", "aria_import", mscore, out, jobs, False, "aria-import")
    mscore_stage(records, "desktop_import", "desktop_round", mscore, out, jobs, False, "desktop-re-export")
    mscore_stage(records, "aria_import", "aria_round", mscore, out, jobs, False, "aria-re-export")
    print(f"compare: checking {len(active_records(records))} scores", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        list(pool.map(compare_record, records))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path,
                        help="score files or directories; defaults to the 892-score compatibility corpus")
    parser.add_argument("--aria", type=Path, default=DEFAULT_ARIA)
    parser.add_argument("--mscore", type=Path, default=DEFAULT_MSCORE)
    parser.add_argument("--out", type=Path, help="new output directory; must not already exist")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--no-force", dest="force", action="store_false", default=True,
                        help="make MuseScore refuse future-version input during normalization")
    args = parser.parse_args()
    scores = collect_inputs(args.paths or DEFAULT_CORPUS, args.limit)
    if not scores:
        parser.error("no .mscz or .mscx scores found")
    for executable in (args.aria, args.mscore):
        if not executable.is_file():
            parser.error(f"executable not found: {executable}")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.out is None:
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        args.out = DEFAULT_OUT_PARENT / f"run-{timestamp}-{os.getpid()}"
    args.out = args.out.resolve()
    try:
        args.out.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.error(f"output directory already exists: {args.out}")
    except OSError as error:
        parser.error(f"cannot create output directory: {error}")
    # The desktop app only ships the Cocoa Qt platform plugin. The Aria helper
    # sets offscreen for its own subprocess independently.
    os.environ.pop("QT_QPA_PLATFORM", None)
    records = run_sweep(scores, args.out, args.aria, args.mscore, args.jobs, args.force)
    results = [{key: value for key, value in record.items()
                if key not in {"source", "start", "desktop_xml", "aria_xml", "desktop_import",
                               "aria_import", "desktop_round", "aria_round"}} for record in records]
    report = {"total": len(results), "same": sum(r["status"] == "same" for r in results),
              "changed": sum(r["status"] == "changed" for r in results),
              "failed": sum(r["status"] == "failed" for r in results),
              "reference_failed": sum(r.get("origin") == "reference" for r in results),
              "candidate_failed": sum(r.get("origin") == "candidate" for r in results),
              "direct_warnings": sum(bool(r.get("direct")) for r in results),
              "results": results}
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    for result in results:
        label = result["status"].upper()
        detail = f" at {result['stage']}: {result['error']}" if label == "FAILED" else ""
        categories = ", ".join(result.get("after_desktop_import", {}))
        if categories:
            detail = f" ({categories})"
        print(f"{label}\t{result['score']}{detail}")
        if result.get("direct"):
            print(f"DIRECT_WARNING\t{result['score']} ({', '.join(result['direct'])})")
    print(f"same {report['same']}/{report['total']}; changed {report['changed']}; "
          f"failed {report['failed']} (reference {report['reference_failed']}, "
          f"candidate {report['candidate_failed']}); direct warnings {report['direct_warnings']}; "
          f"report {args.out / 'report.json'}")
    return 0 if report["changed"] == report["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
