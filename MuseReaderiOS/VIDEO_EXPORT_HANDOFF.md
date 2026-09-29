# Video export: handoff brief (updated 2026-09-29)

Export → **Video** renders a play-along MP4 of the displayed score, either the full
score or each selected part, with its playback audio. The approved scrolling
appearance, score fonts, photo background, and tapered cursor are committed.
The new video sheet and performance changes are implemented locally and **not
committed yet**. Current changes have been checked on the Mac and against the iOS
SDK; **the new UI and optimized pipeline still need an iPad run**.

## Approved UI and styles

Selecting Video opens a dedicated **Video export** sheet. It has an × at the top
right and a full-width **Render video** button at the bottom. Layout, appearance,
background photo, and page orientation are configured here. Content/part selection,
filename, and existing part export options remain in the general export panel.
The panel's Video settings row/button reopens the sheet.

- **Scrolling** (default, 1920×1080): a continuous score on white paper, with a wide
  blue cursor, dimmed played notation, soft left/right fades, and a blue progress
  bar. There is **no measure highlight**. Title and composer stay centered above
  the music, with extra space above and below the notation.
- **Photo background** (`.scrollingPhoto`, 1920×1080): scrolling with white
  notation, staves, lyrics, title, cursor, and progress over a blurred/darkened
  image chosen by the user. A photo is required before rendering. Background blur
  and conversion to white ink are computed once per background/tile.
- **Pages**, landscape 16:9 or portrait 9:16 (1920×1080 / 1080×1920): pages stacked
  on a dark backdrop. A critically damped spring camera follows each system,
  looking 0.4 s ahead; measure highlights and playhead remain. A title card fades
  out during the opening 4.5 s.

The sheet shows a representative preview from an actual cached score page. For
scrolling it crops the first system; it does **not** reflow the live score or start
audio rendering. Photo decoding and preview composition run off the main thread.
The caption explains that the exported video has its own layout.

During rendering, settings and dismissal are disabled and progress/errors appear
inside the sheet. On success, `pendingVideoShareItems` and the sheet's `onDismiss`
callback ensure the video sheet closes before the system share sheet opens. Aria
keeps the screen awake during export.

## Scroll timing: current decision

The user approved MuseScore's rhythmic spacing with `measureSpacing = 1.7` for
video. The earlier statement that proportional spacing was rejected is obsolete.
This uses the engine's continuous/LINE presentation layout; the original spacing
and PAGE layout are restored afterward, including on failure.

Motion is **timed by bar**, following playback regions and their actual tempo and
repeat order. `ScoreVideoScrollPath` builds monotone cubic paths through bar
boundaries, with separate stretches for repeats/jumps. The painter takes a
weighted average over ±0.6 s to soften changes in speed between bars. Beat points
are used to start at the first playable beat, avoiding a sweep across the initial
clef/key/time header; they do not drive exact per-note cursor synchronization.

The score starts still while the cursor moves toward the center. A 160 px handoff
eases into scrolling, then the cursor stays near the middle; it moves farther
right during the final eight seconds to frame the ending. The cached cursor is
140 px wide, with an 84 px vertical taper extending beyond the notation bounds,
so its glow has no hard cutoff above or below the staves.

The former proposed tolerance/corridor fit is **not the current plan**. Preserve
the approved bar timing, spacing, opening handoff, and tapered cursor.

## Score title fonts

Native metadata reports title/composer font family, bold, and italic, including
the first visible text fragment's overrides. `videoTextFonts()` carries these
through the bridge into `ScoreVideoExportOptions`. The exporter resolves the
requested family and traits against installed fonts, falling back to Edwin, then
the system font when unavailable. Font resources include Edwin and FreeSerif.
Amazing Grace's checked title uses Times New Roman and its composer uses FreeSerif.

Both the scrolling title and page-style title card now render once into cached
overlays. Their bounds align to output pixels, preserving the original text
placement without resampling the cached title at fractional positions.

## Implemented performance changes

1. **Mix-only video audio.**
   `playbackAudioChunk(..., includePartSamples: Bool = true)` now exists through
   Swift, the bridge, and native audio rendering. Video passes `false`; existing
   playback callers keep stems by default, and the old ObjC selector still works.
   Native code skips per-part PCM allocation/accumulation and the bridge avoids
   copying those arrays. Synth routing, mixed-sample summation, and sequential
   stream reuse are unchanged. Silent output clears stale stems.
2. **Cached static overlays.** Title/font lookup, title drawing, paper fades,
   cursor glow, and page highlights/playheads are cached, in addition to the
   existing score tiles, page images, and background. PDF rasterization stays at
   the required output resolution.
3. **Audio preparation overlaps frames.** `ScoreVideoAudioStream` is an actor.
   `ScoreVideoAudioPrefetch` prepares one chunk ahead, keeping one ready/in-flight
   chunk plus the current chunk. The writer polls readiness while continuing to
   draw frames, feeds whichever encoder input is ready/behind, and preserves
   sample-based timestamps. It checks audio-format consistency and drains the
   producer before restoring layout or switching parts. Parent cancellation is
   forwarded to the detached render task; failures remove partial outputs.
4. **GPU frame composition.** `ScoreVideoGPUCompositor` uses a reusable
   Metal-backed `CIContext`, a bounded cache of source images, and sRGB output.
   Cached full-resolution layers compose directly into the encoder's
   Metal-compatible, IOSurface-backed BGRA buffers. Core Graphics handles PDF/tile
   rasterization and cached overlays; it also provides a fallback when Metal is
   unavailable. An autorelease pool bounds per-frame temporary objects.

Encoding remains H.264 High, 1080p, 30 fps by default, 10 Mb/s video and 192 kb/s
AAC, with the same 2 s tail and default reverb send of 0.3. No resolution, frame
rate, or bitrate was reduced.

**Speedups remain estimates, not measured results.** The earlier discussion of
10–30% for stems/title, 20–50% overall with audio overlap, and potentially 2–3×
when drawing dominates was conditional. Do not add those estimates together or
promise them. No iPad benchmark of the optimized path has been run. The old
handoff's Mac render times describe the previous pipeline, not this implementation.

## Files (relative to repository root)

- `MuseReaderiOS/MuseReaderiOS/Services/ScoreVideoExporter.swift`: timing, camera,
  page/tile sources, cached layers, GPU/CPU composition, reverb audio stream,
  bounded prefetch, writer, cleanup and cancellation.
- `MuseReaderiOS/MuseReaderiOS/Views/ScoreReaderExportPanel.swift`: general export
  panel, dedicated `ScoreReaderVideoExportSheet`, and preview renderer.
- `MuseReaderiOS/MuseReaderiOS/Views/ScoreReaderView.swift`: video export targets,
  score font/background options, progress, awake state and dismissal/share handoff.
- `MuseReaderiOS/MuseReaderiOS/Services/LiveScoreRenderSession.swift`: layout,
  playback regions/beat points, video fonts, audio chunk options.
- `MuseReaderiOS/MuseReaderiOS/Bridge/MuseScoreRenderCoreBridge.h/.mm`: metadata,
  continuous layout, beat points, and the backward-compatible mix-only selector.
- `sandbox/engraving/score_render_open_save.cpp`: temporary video layout/spacing.
- `sandbox/engraving/score_render_playback.cpp`: playback beat points.
- `sandbox/engraving/score_render_audio.cpp`, `score_render_runtime.cpp`,
  `score_render_core.h`, `score_render_core_facade.inc`: mix-only native API,
  stream rendering and forwarding. Count-in and normal playback paths are retained.
- `MuseReaderiOS/MuseReaderiOSTests/ScoreVideoExporterTests.swift`: existing
  timeline/canvas/path/repeat/camera tests.
- `MuseReaderiOS/Checks/`: standalone Swift pipeline checks and runner; see its
  README. These do not build the app or render core.
- `sandbox/engraving/tests/score_render_audio_mix_tests.cpp`: actual native PCM
  equivalence/default-stem tests, registered in `sandbox/engraving/CMakeLists.txt`.
- `MuseReaderiOS/MuseReaderiOS/Services/SetlistShareExporter.swift`: video extension
  mapping exists; video is still not offered for setlist export.

## Commit state

- `1e7b499770` — Improve scrolling score video and add photo backdrop.
- `a05ec9a244` — "latest", includes the score title-font changes among other work.
- `56b9f5ec5f` — Fade video cursor glow beyond notation bounds (current HEAD).
- **Uncommitted:** dedicated video sheet, parent integration, GPU/static-layer
  cache, audio prefetch/cancellation, native mix-only API, new checks, and this
  updated handoff. Do not treat these as already included in HEAD.

## Verification completed in this session

- Existing native **iOS Release** cache rebuilt successfully for the audio API
  change; host native build also passed. No cache was cleaned.
- ObjC++ bridge syntax passed with native support enabled and disabled. Both old
  and new audio selectors passed imported Swift API checks against the iOS SDK.
- Native mix-only tests passed on count-in and Amazing Grace fixtures: **bit-for-bit
  identical mixed PCM**, default stems preserved, sequential mode switching,
  metronome, selected-part routing, and stale-stem cleanup in silent tails.
- Real exporter Swift SDK typechecks passed; the UI sheet typechecked with small
  dependency stand-ins and the actual SwiftUI/UIKit SDK. Modified Swift files
  passed parsing and `git diff --check` passed. No full app build was run for the
  Swift-only verification.
- Representative frames from all four styles were generated on Mac Catalyst with
  Metal available and compared against the prior renderer. This caught and fixed
  a flipped page background gradient and fractional-pixel cached title placement.
  Scrolling paper/photo stills were visually inspected. These were correctness
  checks, not rendering benchmarks.
- A four-second synthetic export using the real Swift exporter passed checks for
  video/audio tracks, 1080p/30 fps, duration/tail, bounded sequential audio
  prefetch, mix-only requests, format-change errors, partial-file cleanup,
  cancellation and layout restoration. Audio/reverb dependencies are stand-ins;
  native audio equivalence is covered separately above.

Reproduce the lightweight Swift checks from the repository root:

```sh
python3 MuseReaderiOS/Checks/check_video_export.py
# Apple Silicon Mac; requires Metal/IOSurface and encoder access:
python3 MuseReaderiOS/Checks/check_video_export.py --run
```

Scratch evidence, which may disappear:

- `aria-audio-mix-tests.log`
- `aria-amazing-grace-audio-mix-tests.log`
- `aria-video-frames-current/` and `aria-video-frames-baseline/`
- `aria-video-pipeline-results/`
- `aria-roundtrip-mix-audio/report.md`

Approved pre-optimization previews are kept locally, outside the repository:
`amazing-grace-opening-tracker-wide-margins.mp4`,
`amazing-grace-white-photo-soft-cursor.mp4`, and its `-still.png`.
`video-settings-preview.html` is the approved interactive modal mockup.

## Remaining verification and build guidance

- Run the new UI and an export on the intended iPad: layout/orientation/photo
  selection, failure/retry, progress, dismissal then sharing, audio/reverb and
  displayed full-score/part routing. Native selected-part PCM tests pass, but the
  complete app's multi-target video flow has not been device-tested.
- Measure wall time and memory on that iPad before quoting a speedup. Long scores,
  many parts, very wide continuous layouts, and sustained rendering still need
  device memory/thermal checks.
- The original handoff recorded a `score_render_edit_sweep_tests` failure. It has
  not been rerun in this update; its cause was not established. The new focused
  audio tests passing does not resolve that historical result.
- Desktop 4.7.5 compatibility fixture checks were rerun but remain blocked by the
  existing `4.7.5-cannot-open-input` environment failure. No format/writer change
  was made for the audio optimization; do not report the blocked round-trip as a pass.
- Active project/scheme: **`MuseReaderiOS/Aria.xcodeproj` / `Aria`**. Follow root
  `AGENTS.md`: Swift/SwiftUI-only checks must not routinely trigger full Xcode or
  CMake builds. Preserve `/tmp/musescore-score-render-core-ios`; the current native
  API change has already been built there. Native/bridge changes require the
  appropriate incremental verification, without cleaning the cache.
- Engine baseline remains MuseScore **4.7.5**, format **4.70**. Do not merge
  upstream MuseScore 5 development or relabel output versions.
