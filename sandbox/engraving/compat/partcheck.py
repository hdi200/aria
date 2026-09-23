"""Check that linked parts match the full score in an .mscz.

Pairs every part element (<linkedTo>EID</linkedTo>) with the full-score element that has
that <eid>, and reports:
  missing  - a full-score item (of a type that belongs in parts) with no copy in a part
             that contains its staff (system items: in every part)
  differ   - a part copy whose simple properties differ from the full-score original
"""
import collections
import sys
import zipfile
import xml.etree.ElementTree as ET

IGNORE = {"eid", "linkedTo", "offset", "placement", "autoplace", "minDistance", "visible", "track",
          "color", "posAbove", "posBelow", "userOff", "size"}
STAFF_TYPES = {"Chord", "Rest", "Note", "Dynamic", "StaffText", "Harmony", "Articulation", "Lyrics",
               "InstrumentChange", "KeySig", "TimeSig", "Fermata", "Expression", "Tie", "Slur", "HairPin",
               "Accidental", "Spanner"}
SYSTEM_TYPES = {"Jump", "Marker", "Tempo", "RehearsalMark", "SystemText"}


def members(path):
    z = zipfile.ZipFile(path)
    main = next(n for n in z.namelist() if n.endswith(".mscx") and "/" not in n)
    parts = [n for n in z.namelist() if n.startswith("Excerpts/") and n.endswith(".mscx")]
    return ET.fromstring(z.read(main)), {n.split("/")[1]: ET.fromstring(z.read(n)) for n in parts}


def staff_blocks(root):
    score = root.find("Score")
    return [(s.get("id"), s) for s in score.findall("Staff") if s.find("Measure") is not None or s.find("VBox") is not None]


def scalars(el):
    return {c.tag: (c.text or "").strip() for c in el if len(c) == 0 and c.tag not in IGNORE}


def check(path):
    master, parts = members(path)
    by_eid = {}
    for staff_id, block in staff_blocks(master):
        for el in block.iter():
            eid = el.find("eid")
            if eid is not None and eid.text:
                by_eid[eid.text] = (el, staff_id)

    copies = collections.defaultdict(dict)       # part -> master eid -> element
    part_staves = collections.defaultdict(set)   # part -> master staff ids it contains
    issues = collections.Counter()
    examples = {}

    def note(key, text):
        issues[key] += 1
        examples.setdefault(key, text)

    for name, root in parts.items():
        for _, block in staff_blocks(root):
            for el in block.iter():
                link = el.find("linkedTo")
                if link is None or not link.text:
                    continue
                original = by_eid.get(link.text)
                if original is None:
                    note(("dangling link", el.tag), f"{name}: {el.tag} links to missing full-score item")
                    continue
                m_el, m_staff = original
                copies[name][link.text] = el
                if m_el.tag in STAFF_TYPES and m_el.tag not in ("Tie", "Spanner"):
                    part_staves[name].add(m_staff)
                a, b = scalars(m_el), scalars(el)
                for tag in sorted(set(a) | set(b)):
                    if a.get(tag) != b.get(tag):
                        note(("differ", m_el.tag, tag), f"{name}: {m_el.tag} <{tag}> score={a.get(tag)!r} part={b.get(tag)!r}")

    for eid, (m_el, m_staff) in by_eid.items():
        for name in parts:
            system = m_el.tag in SYSTEM_TYPES
            if not system and (m_el.tag not in STAFF_TYPES or m_staff not in part_staves[name]):
                continue
            if eid not in copies[name]:
                label = m_el.find("text")
                desc = (label.text if label is not None else "") or ""
                note(("missing", m_el.tag), f"{name}: no copy of {m_el.tag} {desc!r} (full-score staff {m_staff})")
    return issues, examples


if __name__ == "__main__":
    results = {path: check(path) for path in sys.argv[1:]}
    baseline_keys = set()
    for path in sys.argv[1:-1]:
        baseline_keys |= set(results[path][0])
    for path, (issues, examples) in results.items():
        print(f"== {path.split('/')[-1]}: {sum(issues.values())} issues")
        for key, count in sorted(issues.items(), key=lambda kv: -kv[1]):
            new = "" if key in baseline_keys or path != sys.argv[-1] else "   <-- NEW"
            print(f"   {count:4d}  {' / '.join(key)}{new}    e.g. {examples[key]}")
