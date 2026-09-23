"""Parse and compare the musical content of two Standard MIDI Files.

Only MIDI export is under test here. Instrument audio, soundfonts, and rendering
are outside a MIDI file. Byte-level comparisons are misleading because PPQ,
track order, names, and event packing may differ while playback is equivalent.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path


class MidiError(ValueError):
    pass


@dataclass(frozen=True)
class Event:
    tick: int
    track: int
    order: int
    kind: str
    channel: int = -1
    a: int = 0
    b: int = 0


@dataclass(frozen=True)
class Note:
    track: int
    channel: int
    pitch: int
    start_us: int
    duration_us: int
    start_beat: Fraction
    duration_beat: Fraction
    velocity: int


def _u16(data: bytes, pos: int) -> int:
    return int.from_bytes(data[pos:pos + 2], "big")


def _u32(data: bytes, pos: int) -> int:
    return int.from_bytes(data[pos:pos + 4], "big")


def _vlq(data: bytes, pos: int) -> tuple[int, int]:
    value = 0
    # Standard MIDI uses at most four bytes. MuseScore itself emits five-byte
    # values for negative pre-roll ticks in two guitar bend regression scores.
    # Parse those too, then flag them separately in the comparison report.
    for _ in range(5):
        if pos >= len(data):
            raise MidiError("truncated variable length quantity")
        byte = data[pos]
        pos += 1
        value = (value << 7) | (byte & 0x7f)
        if not byte & 0x80:
            return value, pos
    raise MidiError("variable length quantity exceeds five bytes")


def read_midi(path: Path) -> tuple[int, list[Event], int, int]:
    data = path.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd" or _u32(data, 4) < 6:
        raise MidiError("missing MIDI header")
    fmt, count, division = _u16(data, 8), _u16(data, 10), _u16(data, 12)
    if fmt not in (0, 1):
        raise MidiError(f"unsupported MIDI format {fmt}")
    if division & 0x8000 or division == 0:
        raise MidiError("SMPTE time division is not supported")
    pos = 8 + _u32(data, 4)
    events: list[Event] = []
    long_vlq_count = 0
    for track in range(count):
        if data[pos:pos + 4] != b"MTrk" or pos + 8 > len(data):
            raise MidiError(f"missing track {track}")
        end = pos + 8 + _u32(data, pos + 4)
        if end > len(data):
            raise MidiError(f"truncated track {track}")
        pos += 8
        tick = 0
        running = None
        order = 0
        while pos < end:
            start = pos
            delta, pos = _vlq(data, pos)
            long_vlq_count += pos - start > 4
            tick += delta
            if pos >= end:
                raise MidiError(f"truncated event in track {track}")
            first = data[pos]
            if first & 0x80:
                pos += 1
                status = first
                if status < 0xf0:
                    running = status
                else:
                    running = None
            else:
                if running is None:
                    raise MidiError(f"missing running status in track {track}")
                status = running
            if status == 0xff:
                if pos >= end:
                    raise MidiError("truncated meta event")
                meta = data[pos]
                start = pos + 1
                size, pos = _vlq(data, pos + 1)
                long_vlq_count += pos - start > 4
                payload = data[pos:pos + size]
                if len(payload) != size or pos + size > end:
                    raise MidiError("truncated meta payload")
                pos += size
                if meta == 0x51 and size == 3:
                    events.append(Event(tick, track, order, "tempo", a=int.from_bytes(payload, "big")))
            elif status in (0xf0, 0xf7):
                start = pos
                size, pos = _vlq(data, pos)
                long_vlq_count += pos - start > 4
                pos += size
                if pos > end:
                    raise MidiError("truncated SysEx payload")
            elif status < 0xf0:
                kind = status >> 4
                channel = status & 0x0f
                size = 1 if kind in (0xc, 0xd) else 2
                payload = data[pos:pos + size]
                if len(payload) != size or pos + size > end:
                    raise MidiError("truncated channel event")
                pos += size
                a, b = payload[0], payload[1] if size == 2 else 0
                if kind == 0x9 and b > 0:
                    label = "on"
                elif kind == 0x8 or (kind == 0x9 and b == 0):
                    label = "off"
                elif kind == 0xb:
                    label = "control"
                elif kind == 0xc:
                    label = "program"
                elif kind == 0xe:
                    label = "bend"
                else:
                    label = "other"
                events.append(Event(tick, track, order, label, channel, a, b))
            else:
                raise MidiError(f"unsupported MIDI status 0x{status:02x}")
            order += 1
        pos = end
    return division, events, count, long_vlq_count


def _microseconds_at_ticks(ppq: int, events: list[Event]) -> dict[int, int]:
    """Map every event tick to actual time using the file's global tempo map."""
    by_tick = defaultdict(list)
    for event in events:
        by_tick[event.tick].append(event)
    previous = 0
    elapsed = Fraction(0)
    tempo = 500_000
    times = {}
    for tick in sorted(by_tick):
        elapsed += Fraction((tick - previous) * tempo, ppq)
        times[tick] = round(elapsed)
        for event in sorted(by_tick[tick], key=lambda e: (e.track, e.order)):
            if event.kind == "tempo":
                tempo = event.a
        previous = tick
    return times


def summarize(path: Path) -> dict:
    ppq, events, track_count, long_vlq_count = read_midi(path)
    times = _microseconds_at_ticks(ppq, events)
    pending: dict[tuple[int, int, int], deque[Event]] = defaultdict(deque)
    notes: list[Note] = []
    programs = []
    controls = []
    bends = []
    orphan_off = []
    for event in events:
        if event.kind == "on":
            pending[event.track, event.channel, event.a].append(event)
        elif event.kind == "off":
            queue = pending[event.track, event.channel, event.a]
            if not queue:
                orphan_off.append((Fraction(event.tick, ppq), event.a))
                continue
            on = queue.popleft()
            notes.append(Note(event.track, event.channel, event.a,
                              times[on.tick], times[event.tick] - times[on.tick],
                              Fraction(on.tick, ppq), Fraction(event.tick - on.tick, ppq), on.b))
        elif event.kind == "program":
            programs.append((Fraction(event.tick, ppq), event.track, event.channel, event.a))
        elif event.kind == "control":
            controls.append((Fraction(event.tick, ppq), event.track, event.channel, event.a, event.b))
        elif event.kind == "bend":
            bends.append((Fraction(event.tick, ppq), event.track, event.channel, event.a + 128 * event.b))
    unterminated_on = [(Fraction(event.tick, ppq), event.a, event.b)
                       for queue in pending.values() for event in queue]

    # Last tempo at a beat wins; redundant repeated values do not change playback.
    tempo_at = {}
    for event in sorted((e for e in events if e.kind == "tempo"), key=lambda e: (e.tick, e.track, e.order)):
        tempo_at[Fraction(event.tick, ppq)] = event.a
    effective_tempo = []
    current = 500_000
    for beat, value in sorted(tempo_at.items()):
        if value != current:
            effective_tempo.append((beat, value))
            current = value
    return {"ppq": ppq, "track_count": track_count, "long_vlq_count": long_vlq_count, "notes": notes,
            "tempo": effective_tempo, "programs": programs,
            "controls": controls, "bends": bends,
            "orphan_off": orphan_off, "unterminated_on": unterminated_on}


def _beat(beat: Fraction) -> str:
    return str(beat.numerator) if beat.denominator == 1 else f"{beat.numerator}/{beat.denominator}"


def _strip_pitch_bend_range_setup(controls: list[tuple]) -> tuple[list[tuple], int]:
    """Remove only the standard five-message RPN-0/0 setup sequence.

    Aria passes exportRPNs=false to ExportMidi; the desktop CLI's current
    setting passes true. Other CC6 or RPN messages remain in the comparison.
    """
    clean = []
    count = 0
    index = 0
    expected = ((100, 0), (101, 0), (6, 12), (100, 127), (101, 127))
    while index < len(controls):
        window = controls[index:index + 5]
        if (len(window) == 5
                and all(event[:3] == window[0][:3] for event in window)
                and tuple(event[3:] for event in window) == expected):
            count += 1
            index += 5
        else:
            clean.append(controls[index])
            index += 1
    return clean, count


def compare(reference: dict, candidate: dict, tolerance_us: int = 2000) -> dict:
    """Classify differences independently so velocity cannot hide a pitch error."""
    issues = []
    warnings = []
    if reference["long_vlq_count"] or candidate["long_vlq_count"]:
        diagnostic = {"kind": "nonstandard-vlq", "reference_count": reference["long_vlq_count"],
                      "candidate_count": candidate["long_vlq_count"]}
        (warnings if reference["long_vlq_count"] == candidate["long_vlq_count"] else issues).append(diagnostic)
    ref_notes: list[Note] = reference["notes"]
    cand_notes: list[Note] = candidate["notes"]
    tempo_issue = None
    if reference["tempo"] != candidate["tempo"]:
        tempo_issue = {"kind": "tempo", "reference": [(_beat(b), t) for b, t in reference["tempo"][:12]],
                       "candidate": [(_beat(b), t) for b, t in candidate["tempo"][:12]]}
        issues.append(tempo_issue)
    for label in ("orphan_off", "unterminated_on"):
        if Counter(reference[label]) != Counter(candidate[label]):
            issues.append({"kind": label, "reference_count": len(reference[label]),
                           "candidate_count": len(candidate[label]),
                           "reference_examples": [str(item) for item in reference[label][:8]],
                           "candidate_examples": [str(item) for item in candidate[label][:8]]})
    ref_counts = Counter(n.pitch for n in ref_notes)
    cand_counts = Counter(n.pitch for n in cand_notes)
    if ref_counts != cand_counts:
        issues.append({"kind": "pitch-count", "reference_notes": len(ref_notes),
                       "candidate_notes": len(cand_notes),
                       "missing": dict((ref_counts - cand_counts).most_common(12)),
                       "extra": dict((cand_counts - ref_counts).most_common(12))})
    timing = []
    velocity = []
    beat_timing = []
    max_start_delta_us = 0
    max_duration_delta_us = 0
    for pitch in sorted(ref_counts.keys() & cand_counts.keys()):
        ref = sorted((n for n in ref_notes if n.pitch == pitch), key=lambda n: (n.start_us, n.duration_us, n.velocity))
        cand = sorted((n for n in cand_notes if n.pitch == pitch), key=lambda n: (n.start_us, n.duration_us, n.velocity))
        for r, c in zip(ref, cand):
            start_delta = c.start_us - r.start_us
            duration_delta = c.duration_us - r.duration_us
            max_start_delta_us = max(max_start_delta_us, abs(start_delta))
            max_duration_delta_us = max(max_duration_delta_us, abs(duration_delta))
            if abs(start_delta) > tolerance_us or abs(duration_delta) > tolerance_us:
                timing.append({"pitch": pitch, "reference_start_us": r.start_us,
                               "candidate_start_us": c.start_us, "start_delta_us": start_delta,
                               "reference_duration_us": r.duration_us,
                               "candidate_duration_us": c.duration_us, "duration_delta_us": duration_delta})
            if r.start_beat != c.start_beat or r.duration_beat != c.duration_beat:
                beat_timing.append({"pitch": pitch, "reference_beat": _beat(r.start_beat),
                                    "candidate_beat": _beat(c.start_beat),
                                    "reference_duration": _beat(r.duration_beat),
                                    "candidate_duration": _beat(c.duration_beat)})
            if r.velocity != c.velocity:
                velocity.append({"pitch": pitch, "start_us": r.start_us,
                                 "reference": r.velocity, "candidate": c.velocity})
    if timing:
        issues.append({"kind": "note-time", "count": len(timing), "examples": timing[:8]})
    if tempo_issue is not None:
        tempo_issue["max_note_start_delta_us"] = max_start_delta_us
        tempo_issue["max_note_duration_delta_us"] = max_duration_delta_us
    if beat_timing:
        issues.append({"kind": "note-beat", "count": len(beat_timing), "examples": beat_timing[:8]})
    if velocity:
        issues.append({"kind": "velocity", "count": len(velocity), "examples": velocity[:8]})

    # Track grouping catches a part sent to the wrong track. Track numbers and
    # channel allocations are irrelevant, so compare groups by note content.
    def groups(notes):
        by_track = defaultdict(list)
        for n in notes:
            by_track[n.track].append((n.pitch, n.start_beat, n.duration_beat))
        return Counter(tuple(sorted(group)) for group in by_track.values() if group)
    if groups(ref_notes) != groups(cand_notes):
        issues.append({"kind": "track-grouping", "reference_groups": sum(groups(ref_notes).values()),
                       "candidate_groups": sum(groups(cand_notes).values())})

    # Program numbers and expressive controls are reported separately. Files can
    # choose different channels/tracks, but events at the same beat still matter.
    def semantic_events(items, index):
        return Counter((_beat(item[0]), *item[index:]) for item in items)
    ref_controls, ref_rpn_count = _strip_pitch_bend_range_setup(reference["controls"])
    cand_controls, cand_rpn_count = _strip_pitch_bend_range_setup(candidate["controls"])
    if ref_rpn_count != cand_rpn_count:
        diagnostic = {"kind": "rpn-bend-risk" if reference["bends"] or candidate["bends"] else "export-rpn-option",
                      "reference_setup_sequences": ref_rpn_count,
                      "candidate_setup_sequences": cand_rpn_count}
        if reference["bends"] or candidate["bends"]:
            issues.append(diagnostic)
        else:
            warnings.append(diagnostic)
    for label, index, ref_items, cand_items in (
            ("programs", 3, reference["programs"], candidate["programs"]),
            ("controls", 3, ref_controls, cand_controls),
            ("bends", 3, reference["bends"], candidate["bends"])):
        ref = semantic_events(ref_items, index)
        cand = semantic_events(cand_items, index)
        if ref != cand:
            issues.append({"kind": label, "missing": list((ref - cand).elements())[:8],
                           "extra": list((cand - ref).elements())[:8],
                           "reference_count": sum(ref.values()), "candidate_count": sum(cand.values())})
    return {"status": "match" if not issues else "different", "issues": issues,
            "warnings": warnings,
            "reference_notes": len(ref_notes), "candidate_notes": len(cand_notes)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--tolerance-us", type=int, default=2000)
    args = parser.parse_args()
    print(json.dumps(compare(summarize(args.reference), summarize(args.candidate), args.tolerance_us), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
