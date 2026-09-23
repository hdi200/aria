# MusicXML export comparison (prototype)

This check compares the XML produced by Aria's `ScoreRenderSession::musicXMLData`
with MuseScore Studio 4.7.5's XML export from the same 4.7.5-normalized score.
It then imports both exports into 4.7.5 and compares the MusicXML exported from
those imported scores. The second comparison answers whether desktop MuseScore
receives the same music from the two exports.

Build the host CLI with `cmake --build build-aria-475-host --target
score_render_musicxml_export`, then run a focused set:

```bash
python3 sandbox/engraving/compat/musicxml_export_sweep.py \
  vtest/scores/lyrics-6.mscx \
  vtest/scores/harmony-22.mscz \
  vtest/scores/dynamics-11.mscz \
  vtest/scores/tuplets-9.mscz
```

Omit paths to use the same 892-score corpus as `roundtrip_475.py`. Use
`--out PATH` to choose a new report directory, `--jobs N` for parallel conversion,
and `--limit N` for a short run. The default output goes into a fresh timestamped
directory under `build-aria-475-host/musicxml-export`. An explicit `--out`
directory must not already exist, so previous reports are never overwritten.
Normalization uses MuseScore's force-open mode by default because the corpus
contains 5.00 development files; use `--no-force` to test strict opening. The
report is `report.json` in the output directory, with per-score
exports retained for inspection. A changed or failed score makes the command
exit nonzero.

The comparison checks parts and staff counts, note pitches and rests, measure
positions and durations, voices, ties, lyrics, chord symbols, dynamics, and
sound tempo. It compares the musical meaning of those fields, not raw XML text;
for example, different `<divisions>` values that describe the same rhythm
compare equal.

MusicXML is not a lossless interchange format for MuseScore layout and styling.
This check does not assert line/page breaks, fonts, text geometry, playback
soundfonts, instrument channels, slurs or other spanners, figured bass, or
notation-specific properties not listed above. Some properties may be lost by
both exporters or by MuseScore's MusicXML import; this check detects differences
between Aria and the desktop exporter, not completeness against the original
MSCZ at every property. The direct comparison in `report.json` helps locate
differences that the desktop import normalizes away.

The driver batches each desktop conversion stage with MuseScore's `-j` job files
and Aria export with the CLI's `--manifest` mode. It checks each result even if
a desktop process crashes after writing its output, and records failures per
score and stage.

## September 2026 full-corpus result (4.7.5 engine)

Of 892 scores, 891 could be compared after both exports were imported into
MuseScore 4.7.5, and all 891 matched on the musical fields above. The remaining
`timesig-3.mscz` fails on the *reference* path: MuseScore 4.7.5 crashes while
exporting its own MusicXML after reimport, so it gives no Aria-versus-desktop
comparison.

There are no direct-export warnings. The earlier 5.0 development engine exported
a different chord `kind/@text` than desktop for nine chord-symbol scores (for
example `text="sus2"` where desktop writes `text="2"`); that went away with the
move to the 4.7.5 engine.
