# MuseScore 4.7.5 round-trip check

Aria users move scores between the iPad and desktop MuseScore Studio. The current
stable desktop release is 4.7.5, which uses file format 4.70. Aria's engine is
MuseScore 4.7.5 plus a few Aria patches (see ENGINE.md), and every save has to come
back to 4.7.5 intact. This check proves that on a corpus of scores. Run it after any
engine change or upstream merge.

## What it does

For each score it compares two paths that both end with a MuseScore 4.7.5 save:

- **ref**: 4.7.5 opens and saves the score, then does it again.
- **cand**: Aria opens and saves the score (its real `ScoreRenderSession` save
  path), then 4.7.5 opens and saves it.

MuseScore's own quirks cancel out, because 4.7.5 is not perfectly stable when it
re-saves its own files. Any remaining difference is something Aria lost or
changed. It also flags files that 4.7.5 refuses to open, and tags 4.7.5 silently
drops from Aria's file.

By default Aria starts from a copy that 4.7.5 has already saved, which is what a
4.7.5 user actually has. `--direct` hands Aria the original file instead, which
also tests how Aria reads older formats.

## Run it

```bash
# one-time configure (Mac host build, separate from the iOS render-core outputs)
cmake -S sandbox/engraving -B build-aria-475-host -G Ninja -DCMAKE_BUILD_TYPE=Release -DSCORE_RENDER_BUILD_TESTS=ON \
  -DQt6_DIR=$HOME/Qt/6.11.0/macos/lib/cmake/Qt6 -DSCORE_RENDER_QT_HOST_ROOT=$HOME/Qt/6.11.0/macos

cmake --build build-aria-475-host --target score_render_resave
python3 sandbox/engraving/compat/roundtrip_475.py            # vtest + Aria templates + fixtures
python3 sandbox/engraving/compat/roundtrip_475.py ~/some-scores --direct
```

It needs MuseScore Studio 4.7.5 at `/Applications/MuseScore 4.app`; use `--mscore`
to point elsewhere. The report goes to `build-aria-475-host/roundtrip/report.md`,
and the exit code is non-zero if any score changed.

`fixtures/` holds scores that each exercise a known 4.7-only feature, such as the
"pitch names, no accidentals" notehead schemes added in MuseScore 4.7.

## Known differences (baseline, September 2026, 4.7.5 engine)

Default run: 890 of 892 identical. The remaining two are `lyrics-15` and `lyrics-16`,
and Aria's file is the correct one. Their 4-bar Piano part carries a stale 32-bar
multimeasure rest from the original test file. Desktop writes it back untouched
because it never lays out a part it has not displayed. Aria lays out every part
before saving, so the impossible rest is dropped, as desktop also does once the part
is opened.

`--direct` run: 890 of 892 identical (the 5.0 development engine managed 604); only
the same two lyrics files differ. Run it with `PAPERSIZE=letter` on a US Mac: files
that store no page size start from the default style, whose page size follows the
region (Letter in the US, A4 elsewhere) in both Aria and desktop, and the command-line
tool has no region of its own.

MuseScore 5 files (5.00) open with "open anyway", as desktop 4.7.5 does, and come
back identical to what 4.7.5 itself writes after forcing them open.

## Page layout

`layout_compare.py` checks that Aria draws the same pages as desktop: it compares page
counts and page 1 pixel by pixel against 4.7.5's PDF export (build `score_render_probe`;
needs poppler, Pillow and numpy).

```bash
PAPERSIZE=letter python3 sandbox/engraving/compat/layout_compare.py --out /tmp/aria-layout
```

September 2026 baseline: all 842 vtest scores have the same page count and a
pixel-identical page 1 (the 5.0 development engine: 533). Getting there needed the
desktop-equivalent master score setup after loading (see ENGINE.md).

Native tests in `tests/score_render_accidental_tests.cpp` cover the edit side, which
this check does not (build with `-DSCORE_RENDER_BUILD_TESTS=ON`):
`part names survive save and follow instrument replacement`,
`new dynamics and text reach linked parts`,
`blank part dynamics require approval`, and
`jumps and markers reach linked parts`.
