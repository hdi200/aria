# MuseScore 4.7.5 round-trip check

Aria users move scores between the iPad and desktop MuseScore Studio. The current
stable desktop release is 4.7.5, which uses file format 4.70. Aria's engine is a
MuseScore 5.0 development snapshot, so every save has to come back to 4.7.5 intact.
This check proves that on a corpus of scores. Run it after any engine change or
upstream merge.

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
cmake -S sandbox/engraving -B build-aria-compat-host -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DQt6_DIR=$HOME/Qt/6.11.0/macos/lib/cmake/Qt6 -DSCORE_RENDER_QT_HOST_ROOT=$HOME/Qt/6.11.0/macos

cmake --build build-aria-compat-host --target score_render_resave
python3 sandbox/engraving/compat/roundtrip_475.py            # vtest + Aria templates + fixtures
python3 sandbox/engraving/compat/roundtrip_475.py ~/some-scores --direct
```

It needs MuseScore Studio 4.7.5 at `/Applications/MuseScore 4.app`; use `--mscore`
to point elsewhere. The report goes to `build-aria-compat-host/roundtrip/report.md`,
and the exit code is non-zero if any score changed.

`fixtures/` holds scores that each exercise a known 4.7-only feature, such as the
"pitch names, no accidentals" notehead schemes added in MuseScore 4.7.

## Known differences (baseline, September 2026)

Default run: 890 of 892 identical. The remaining two are `lyrics-15` and `lyrics-16`:
a linked part loses a measure-long multimeasure-rest measure that 4.7.5 keeps.

`--direct` run: 604 of 892 identical. Almost all of the rest are files opened in
Aria straight from older formats without passing through 4.7.5 first:

- 2.x/3.x files: instrument-name vertical alignment defaults differ (`longInstrumentAlign`).
- Some 3.x–4.4 files: `paddingToNotationAbove/Below` compatibility values differ.
- `.mscx` files with no style file: Aria defaults to A4 where 4.7.5 uses Letter.
- `text-offset-scale` (4.60): text offsets on scaled staves are converted differently.
- 5.00 files: Aria keeps instrument names that 4.7.5 itself drops when forced open.

These all come from the 5.0-dev engine's reading differing from 4.7.5's. They go
away if the engine is moved to the 4.7.5 release.

Native tests in `tests/score_render_accidental_tests.cpp` cover the edit side, which
this check does not (build with `-DSCORE_RENDER_BUILD_TESTS=ON`):
`part names survive save and follow instrument replacement`,
`new dynamics and text reach linked parts`,
`blank part dynamics are repaired on open`, and
`jumps and markers reach linked parts`.
