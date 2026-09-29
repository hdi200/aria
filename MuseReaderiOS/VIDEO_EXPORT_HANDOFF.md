# Video export: handoff brief (2026-09-28)

Export → **Video** renders a play-along MP4 of the displayed score (full score or each
selected part) with its audio. Built and verified on the Mac only; **not yet run on a
device**. Needs a native rebuild before the next iOS build (native API was added).

## Styles (picker in the export panel, `ScoreVideoStyle`)
- **Scrolling** (default, 1920×1080): the whole piece on one continuous line (MuseScore's
  own continuous/LINE layout) sliding right-to-left under a fixed blue playhead at ~32% of
  the width. All-white frame, played music dimmed, line fades at left/right edges, blue
  measure highlight, title + composer **pinned at the top** for the whole video, blue
  progress bar at the bottom.
- **Pages 16:9 / Pages 9:16**: pages stacked in a column on a dark backdrop; a
  critically damped spring camera glides to each system (aims 0.4 s ahead); blue
  highlight + playhead; title card for the first ~4 s.
- User feedback so far: likes the blue accents; wanted white (not dark) around the music
  in the scrolling style; wanted the title pinned. Both done.

## Files
- `MuseReaderiOS/Services/ScoreVideoExporter.swift`: everything: timeline, page canvas,
  camera, `ScoreVideoScrollPath`, painters (`ScoreVideoPagesPainter`,
  `ScoreVideoScrollingPainter`), audio stream (adds the in-app reverb via
  `MSRPlaybackReverb`, send 0.3), AVAssetWriter loop.
- `MuseReaderiOSTests/ScoreVideoExporterTests.swift`: timeline, canvas, scroll path
  (barline + beat-point + repeat cases), camera.
- `Views/ScoreReaderExportPanel.swift`: `.video` format, style picker, "Rendering N%".
- `Views/ScoreReaderView.swift`: `writeVideoExports()`; keeps the screen awake while rendering.
- `Services/SetlistShareExporter.swift`: `.video` case (mp4); not offered for setlists.
- `Services/LiveScoreRenderSession.swift`: `setContinuousLayout(_:)`, `playbackBeatPoints()`.
- `Models/ScoreSession.swift`: `ScorePlaybackBeatPoint`.
- Bridge (`MuseScoreRenderCoreBridge.h/.mm`): `setContinuousLayout:totalPageCount:error:`,
  `MSRPlaybackBeatPoint`, `playbackBeatPointsWithError:`.
- Native (`sandbox/engraving/`):
  - `score_render_open_save.cpp` `setContinuousLayout` switches the *presentation* score
    between LINE and PAGE layout; view only, saving unaffected. The exporter turns it on for
    the render and always turns it back off (also on error).
  - `score_render_playback.cpp` `playbackBeatPoints`: one point per beat (compound meters
    beat in dotted quarters) with x interpolated between surrounding chord/rest segments,
    time from the repeat list; `startsSegment` at repeats/jumps; an end point at the last
    barline of each stretch. Declared in `score_render_core.h`, forwarded in
    `score_render_core_facade.inc`.

Commit state: most of the exporter/UI/`setContinuousLayout` is in commit `92e602206b`
("latest"). The beat-point API (native + bridge + Swift), the pinned title and the beat
path are **uncommitted**. Another agent was editing the same native files (count-in feature:
`PlaybackCountIn` in `score_render_core.h`, `score_render_runtime.cpp`,
`score_render_audio.cpp`) at the same time; don't clobber their work.

## Scroll sync: where it stands (the open design question)
The scroll path is a monotone cubic (Fritsch–Carlson) through (time, x) knots per stretch.
Tried three knot sets on Amazing Grace:
1. **Barlines**: steady speed inside each bar; playhead drifts off the notes within a bar;
   also swept across the clef/key/time header at the start.
2. **Every chord/rest**: exact note sync; speed varies ~4× note to note.
3. **Every beat** (current): exact on every beat, header problem fixed, but speed still
   varies ~4.9× beat to beat (only ~half the beats within −30%/+40% of the median) because
   MuseScore spacing is not proportional (long-note beats are packed, eighth-note beats spread).

The user rejected strictly proportional spacing (it distorts the notation). **Proposed next
step (not started):** a tolerance-based path that lets the playhead lead/lag the beat by up to
~¼ beat and picks the steadiest route inside that corridor (e.g. smooth the beat
knots' x-vs-time with a constrained fit, keeping monotonicity and repeat cuts). Tune by eye;
render Amazing Grace to compare.

## How it was verified (Mac, no device)
- Mac Catalyst harness: compiles the real `ScoreVideoExporter.swift` with stand-ins for the
  app types (`Stubs.swift`), fed from files dumped by the host render core
  (`video_dump.cpp`: page PDFs, measure regions, full audio; `beat_probe.cpp`: beat points
  in line layout). Reverb is stubbed out there, so harness audio is dry. Harness and dumps
  lived in a previous session's temporary scratchpad
  (`claude-501/.../3cf3f6e8-.../scratchpad/vharness`, `vdump`); they may be
  gone and can be rebuilt the same way.
- Checked: valid MP4s (size, 30 fps, duration = music + 2 s tail, non-silent AAC), playhead
  position tracked from frame pixels, frames inspected at note onsets (user allowed looking at
  the Amazing Grace demo only; don't open the user's own scores without asking).
- Beat points probed on demos Amazing Grace, All_Dudes, Triumph, goldberg (repeats: 4/5/75
  stretches): times never go backwards, x only goes back at a stretch start, last time equals
  the audio end. goldberg's line is 183,860 pt wide; it's drawn in 1024 px tiles with a small cache.
- Render speed on the Mac: ~4–7 s for 40 s of video (scrolling/pages landscape), ~11–13 s portrait.
- Whole app type-checks for iOS 17 (`swiftc -typecheck` with the bridging header); tests
  type-check with the Swift Testing macro plugin; their expectations were run against the real
  code on the Mac. Bridge syntax-checks against the iOS SDK. Per `AGENTS.md`, don't run the
  full Xcode build for Swift-only checks.

## Open issues
- `score_render_edit_sweep_tests` **failed** once after the beat-point change (it passed
  earlier the same day). Not diagnosed; the other agent's concurrent native edits are a likely
  factor. `playbackBeatPoints` is read-only. Rerun `ctest` in `build-aria-475-host` once the
  native files are stable.
- Not device-tested: look, render time on a phone (guess: a few minutes for a 5-minute
  piece), memory on very long scores.
- Part videos use whatever audio Aria plays in that part's view; unconfirmed whether that's
  the full band or the part alone.
- Scrolling style leaves a lot of white above/below short scores; could scale the line up.
- The highlight box of measure 1 still includes the clef/key/time header (cosmetic).
