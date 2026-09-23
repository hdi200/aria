# MusicXML export comparison (prototype)

This check compares the XML produced by Aria's `ScoreRenderSession::musicXMLData`
with MuseScore Studio 4.7.5's XML export from the same 4.7.5-normalized score.
It then imports both exports into 4.7.5 and compares the MusicXML exported from
those imported scores. The second comparison answers whether desktop MuseScore
receives the same music from the two exports.

Build the host CLI with `cmake --build build-aria-compat-host --target
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
directory under `build-aria-compat-host/musicxml-export`. An explicit `--out`
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

## September 2026 full-corpus result

The first batched run is in
`build-aria-compat-host/musicxml-export-full/report.json`. Of 892 scores,
891 could be compared after both exports were imported into MuseScore 4.7.5;
all 891 then matched on the musical fields above. The remaining `timesig-3.mscz`
failed on the *reference* path: MuseScore 4.7.5 crashes while exporting its own
MusicXML after reimport, including when retried alone. It therefore provides
no Aria-versus-desktop comparison.

The direct exports differ in the chord `kind` element's `text` attribute for
nine scores: `fret-box.mscz`, `harmony-13.mscx`, `harmony-25.mscz`,
`harmony-26.mscz`, `harmony-42.mscz`, `harmony-51.mscz`, `harmony29.mscz`,
`musejazz-chords.mscz`, and `slurs-34.mscz`. For example, desktop MuseScore
exports `text="2"`, `text="#2"`, and `text="bb2"` in `harmony29`, whereas
Aria exports `text="sus2"` for those chord descriptions. MuseScore 4.7.5
normalizes both exports to the same result on import, but another MusicXML
reader may display the suffix differently. These are recorded as direct
warnings, separate from post-import music changes. The bundled 5.0 development
engine and desktop 4.7.5 derive `kind/@text` from different chord-description
data; this is not yet corrected.

The two converted 4.6 fixtures that initially lost MusicXML part names (`Piano`
and `Violin`) now pass after the exporter falls back to the saved track name.
