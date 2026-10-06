# Video export: handoff brief (updated 2026-09-29)

Export → **Video** renders a play-along MP4 of the displayed score, either the full
score or each selected part, with its playback audio. The approved scrolling
appearance, score fonts, photo background, and tapered cursor are committed.
The new video sheet and performance changes are implemented locally and **not
committed yet**. Current changes have been checked on the Mac and against the iOS
SDK; **the new UI and optimized pipeline still need an iPad run**.

## Approved UI and styles

Selecting Video closes the export popover and the reader presents a dedicated
**Video export** sheet (`ScoreReaderVideoExportSheet`; a sheet presented from the
popover stays small on iPad). Closing it without a finished video reopens the popover.
The sheet is
styled after the user's mockup: large bold title with a circled ×; a preview card
with "16:9 • Scrolling" under it; **Layout** as an accent-outlined segmented control
(`ScoreReaderVideoSegmentedControl`) with a one-line description; for scrolling,
**Appearance** as two picture cards, "Score only" (the paper frame) and "Photo"
(the chosen photo); for pages, **Orientation**. Choosing Photo without a photo
opens the Photos picker; once chosen, "Change photo" sits above the photo card
(Photos only, no Files route for now). On iPad (iOS 18) the sheet is
page height and at most 800 pt wide (`ScoreReaderVideoPanelSizing`), on a material
background. `ScoreReaderVideoSettingsLayout` measures the controls first and gives
the preview the remaining height (minimum 100 pt); below 580 pt it switches to
compact spacing and shorter appearance cards, and only then scrolls. Footer: "Keep Aria open
while rendering." and **Render video** (reads "Choose photo" until there is one;
disabled while the preview loads). While rendering: percentage, bar and **Cancel**
(cancels the stored export task quietly). When done: **Video ready** with the
system player, a list for several parts, **Full screen** and **Share**, and a back
button to the settings. Closing returns to the score.

**The preview is a real frame** (`ScoreVideoExporter.previewMaterial` +
`previewFrame`), drawn by the same painters as the export, at time 0 (the video's first frame). Scrolling material switches
the score to one line and back, like the export; `ScoreVideoPreviewCache` in
`ScoreReaderView` loads each layout once per sheet, never twice at once, and is
reset when the sheet closes. Render is disabled while a preview loads so the two
layout switches cannot overlap. (The previous hand-drawn preview, and its use of
layout-break markers as system positions, is gone.)

- **Scrolling** (default, 1920×1080): a continuous score on white paper, with a wide
  blue cursor, dimmed played notation, soft left/right fades, and a blue progress
  bar. There is **no measure highlight**. Title and composer stay centered above
  the music, with extra space above and below the notation. A **sticky header**
  (part names, clefs, key and time signature from the start of the line) stays at
  the left edge while the music slides under it with a short fade; it is cut at
  the blank gap before the first note, found by scanning the rendered strip. It
  shows the opening clef/key only, not later changes.
- **Photo background** (`.scrollingPhoto`, 1920×1080): scrolling with white
  notation, staves, lyrics, title, cursor, and progress over a blurred/darkened
  image chosen by the user. A photo is required before rendering. Background blur
  and conversion to white ink are computed once per background/tile. Tapping the
  photo row opens the Photos picker (`PhotosPicker`); "Choose from Files" is the
  secondary option.
- **Pages**, landscape 16:9 or portrait 9:16 (1920×1080 / 1080×1920): pages stacked
  on a dark backdrop. A critically damped spring camera follows each system,
  looking 0.4 s ahead; measure highlights and playhead remain. A title card fades
  out during the opening 4.5 s.

- **Piano** (`.piano`, `.pianoLight`, `.pianoPhoto`; 1920×1080): a piano-roll
  visualizer modeled on the Transcription app's `PianoRoll`. Notes fall onto a
  keyboard fitted to the music's range (at least three octaves, ending on white
  keys) and light their keys while sounding. Notes come from the audio's own
  playback sequence (`playbackNotes()`, native `collectFluidSynthPlaybackNotes`),
  so they match the sound exactly through repeats, pauses, fermatas and tempo
  changes; percussion is left out of the picture but still heard. Do not use the
  MIDI export for timing: MuseScore 4.7.5's `PauseMap::calculate` applies a
  section break's pause and the next section's tempo to every pass of a repeat
  ending there, so goldberg's MIDI ends 161 s late (the engine's notes start
  every one of its 2,017 measures exactly; `score_render_playback_notes_tests`).
  Each staff gets its own colour (numbered in score order), so a piano's treble
  and bass staves differ. The checks still build notes from a MIDI fixture. No pages are rendered
  and the layout is not switched; audio is the usual engine playback.
  Appearance: **Dark** (default: neon notes with a soft glow, a lit keyboard rail
  and flares where notes meet keys), **Light** (the piano-roll look with lanes,
  bar lines and a scrubber), and **Photo** (white-rimmed notes over the chosen
  photo, blurred once behind a light veil). `ScoreVideoPianoPainter.swift` draws
  notes and keyboard with Core Graphics, then Core Image (Metal) blurs the notes
  into a glow and composes the frame: about 8–15 ms per 1080p frame on the Mac,
  unmeasured on iPad. The preview shows the first note sounding.

The ending never scrolls backward: over the last 8 s the playhead glides right,
and where the final bars move more slowly than it, `scrollOffset(at:)` holds the
score still (the running minimum of the offset within the current stretch, on a
fixed 1/30 s grid). The cursor stays on the playing note. Checked by
`checkScrollingEnding` (a 10 s final bar).

Repeats and jumps cut: the scrolling camera's 1.2 s smoothing window is clamped to
the current path segment (`ScoreVideoScrollPath.segmentTimes`), so it never
averages across a jump and slides backward.

Scrolling layout details: notation fits 59% of the height, but a staff space is
capped at 2.4% of it (measured from staff lines in a measure), so one-staff scores
are large rather than tiny. Vertical placement uses the measured ink of the line (`inkRows`:
markings above the staves and lyrics below, not just the staves): everything is
centred, starting no higher than 17% down, and the title sits 5% of the height
above the topmost ink. Everything must also fit in 72% of the height. The
pinned header is on only when the video has several parts
(`ScoreVideoExportOptions.pinsStaffHeader`: off for part exports and one-part
scores; the preview also turns it off while the reader shows a part). With it
off, the clef and first-bar text scroll away with the music. When on, the
pinned header covers the full band. Loose text that reaches into it (not
connected to the staves: a rehearsal mark, tempo), plus loose shapes within 4 px
of that text, is `OpeningText`: it is painted out of the header and the scrolling
tiles and drawn as its own layer that fades out, finishing 0.4 s before the score
starts to move (never before 0.6 s). Other text scrolls and passes under the header.

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

1. **Mix-only video audio, using the user's current mix.**
   Pressing Render snapshots `readerState.mixerSettings` before any await, and
   reuses that snapshot for every target and chunk. Video uses the separate
   `playbackExportAudioChunk` → `playbackMixedAudioData` API. Native rendering
   applies each part's volume, stereo balance, mute and solo before summation,
   without allocating/copying full stems. Solo is resolved among the target's
   actual parts; a solo outside a selected-part export does not silence it.
   Reverb receives the post-fader mix, and master volume/mute/balance apply after
   dry + reverb. The video still omits the metronome.
   Normal playback's Swift chunk method, both existing ObjC selectors, and
   native summation arithmetic remain unchanged; the new native mix branch is
   used only by the export API. No score/writer/settings mutation is involved.
   **Existing master-pan limitation:** normal playback sets `mainMixerNode.pan`,
   which had no effect in an offline AVAudioEngine check (pan applies to a
   downstream mixer's input bus). That playback code is untouched. Video applies
   the chosen master stereo balance explicitly, so a nonzero master pan can
   sound different from current playback.
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

### Current-mix verification (2026-09-29)

- Native tests compare export PCM against independently mixed playback stems for
  default settings, volume/pan, mute, solo, muted-solo, inactive solo, sequential
  chunks and selected parts on count-in and the two-part guitar-bends fixture.
- Normal playback was compared with a renderer compiled from the pre-change
  HEAD: **7,752,696 and 8,419,968 bytes identical**, including PCM, stems,
  seeking, metronome, part selection and count-in.
- Native host and iOS libraries rebuilt; ObjC++ syntax and imported Swift audio
  APIs checked. The exporter was typechecked against the iOS SDK.
- Export-to-playback checks prove that temporary gain/solo/mute settings do not
  affect the next normal chunk or its stems. Production master-mix checks passed
  volume, both balance directions, hard left/right, neutral PCM and master mute.
- The compatibility fixture check matches the prior report: two pre-existing
  `4.7.5-cannot-open-input` results. This is **not** a compatibility pass.
- This is audio correctness verification, not an iPad performance measurement.

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
