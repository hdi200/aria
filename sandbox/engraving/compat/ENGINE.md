# Aria's MuseScore engine

`src/`, `share/`, `buildscripts/`, `thirdparty/`, `fonts/` and the root CMake files are
MuseScore Studio **4.7.7** (tag `v4.7.7`, commit `b750c43`) plus a small set of Aria
patches listed below. Aria saves genuine 4.70 files that 4.7.5, 4.7.6 and 4.7.7 open without
warnings (4.7.7 kept file format 4.70).

November 21, 2026: moved from 4.7.6 to 4.7.7 the same way as the 4.7.6 move below. The patch
(249 files) applied with no conflicts and no binary changes. What matters to Aria: new
instruments Double Bass (plucked) and Acoustic Bass Guitar (`double-bass-plucked`,
`acoustic-bass-guitar`) with their playback sounds, a lower euphonium range (B♭1), and the
Big Band, Jazz Combo and Bluegrass Band templates using the plucked double bass. The rest is
desktop-only: FFmpeg 9, the convert-to-score dialog, cloud fixes, a macOS CoreMIDI fix and
translations. 4.7.7 contains none of the patches below.

November 2026: moved from 4.7.5 to 4.7.6 by applying the `v4.7.5`..`v4.7.6` difference of
the engine folders to this tree. It applied with no conflicts, so every patch below carried
over unchanged.

Before September 2026 the engine was an April 2026 snapshot of upstream `main`
(commit `e280c3b6`, format 5.00) that relabeled its saves as 4.70. That relabel is gone.

## Aria patches on top of 4.7.7

They were first made on a branch `aria-475` (based on `v4.7.5`) in a separate MuseScore
clone. To see the current patch set, diff these folders against a checkout of `v4.7.7`.

Headless editing (Play Console build 23 regressions):
- `framework/global/internal/interactive.cpp`: synchronous standard dialogs with no UI
  provider log a diagnostic and return Cancel. Desktop dialogs retain their provider path;
  missing UI never silently approves replacing score content.
- `dom/noteentry.cpp`: after `setNoteRest`, `addPitch` checks that the returned segment
  contains a nonempty chord before calling `upNote`. A rest-valued `NoteVal` or failed
  insertion must not be cast to `Chord`.
- Bridge `score_render_edit_commands.cpp` rolls back a rejected tuplet instead of reporting
  success, and rejects keyboard pitches outside MIDI range after instrument transposition
  before replacing notes or rests. Tests cover 512th-note quintuplet rejection and valid
  triplet undo/redo, plus transposing keyboard boundaries and the rest-result engine path.

Crash guards for measures that are not laid out on a system (`measure->system()` null):
- `dom/measure.cpp`, `dom/score.cpp`, `rendering/score/horizontalspacing.cpp`,
  `markerlayout.cpp`, `masklayout.cpp`, `slurtielayout.cpp`, `systemlayout.cpp`
- `rendering/score/score{page,horizontal,vertical}viewlayout.cpp`: only jump to a
  multimeasure rest when multimeasure rests are enabled.
- `rendering/score/chordlayout.cpp`: dot placement falls back instead of asserting.

Parts and loading:
- `dom/excerpt.cpp`, `dom/masterscore.{h,cpp}`, `rw/mscloader.cpp`, `rw/read114/read114.cpp`:
  parts read from a file are marked initialized so they are not rebuilt later.
- `editing/edit.cpp`: linked copies of spanners get a clean parent (`moveToDummy`).
- `dom/spanner.cpp`: non-positive spanner lengths are repaired and logged instead of asserting.
- `rw/read410/tread.cpp`, `rw/read460/tread.cpp`: skip invalid or overlapping system locks.
- `editing/addremoveelement.cpp`: `removeNote` iterates over copies of a note's spanner lists,
  which removing a spanner modifies (read past the end with two or more attached lines), and skips
  spanners already removed with a companion (a guitar bend's hold). Found by the random-edit
  stress test, e.g. creating a tuplet over a note with a guitar bend.
- `editing/edit.cpp`: `undoRemoveMeasures` removes each crossing spanner once, not again through
  its linked copy (a staff linked to tablature), which freed it twice when the score closed.
- `dom/range.cpp`: `TrackList::writeTuplet` opens the next bar's part of a split tuplet also when
  the barline falls inside the tuplet's last note. Upstream left the rest of that note in the
  previous bar's tuplet, so one tuplet spanned two bars with its notes out of order; the next time
  signature change (`ScoreRange::read` → `skipTuplet`) then went back to it and copied it without
  end until the system killed the app for memory. Found by the random-edit stress test
  (`vtest/scores/tuplets-7.mscz`, seed 29010: 6/8 then another change).
- `editing/cmd.cpp`, `editing/undo.h`, `editing/addremoveelement.h`: `Score::endCmd` drops a
  command's `RemoveElement` of a tuplet that chords still use when the command ends. Entering a
  note over a tuplet's only chord removes the chord, which also removed the emptied tuplet, and
  then `makeGap`/`setNoteRest` put the new note and the refilled rest back into it. For a tuplet
  `RemoveElement` only makes the undo stack its owner, so the next removal owned it again and
  closing the score freed it twice (`RemoveElement::cleanup`). Found by the stress test
  (tuplets-7, articulation-11, beams-21); test `a note over a tuplet's only chord keeps the
  tuplet` fails under AddressSanitizer without it.
- `editing/edit.cpp`: `deleteMeasures` deselects in every score of the master, not only its own.
  Removing bars while a part is shown runs on the full score, and the part's selection kept
  pointing into the removed bars, so the next edit there (adding text) used a removed measure.
- `editing/edit.cpp`: `deleteRangeAtTrack` skips an anchored element it already removed with a
  grace note. `collectElementsAnchoredToChordRest` lists a grace note's articulations as well as
  the grace note, whose own anchored elements are removed first; depending on the order of that
  pointer set the articulation was removed again, and closing the score freed it twice. Found by
  the Goldberg paste replay (`compat/README.md`); test `deleting grace note articulations removes
  each once` fails under AddressSanitizer without it.
- `dom/range.cpp`: `ScoreRange::read` unlinks an incoming tie (undoably) before removing it.
  Only this score's tie is removed there and an unlinked clone is added back, so a part's linked
  tie kept the removed tie in its link list; removing the part's tie later removed it a second
  time, and closing the score freed it twice. Found by the stress test (articulation-11, seed
  29002: a duration change made the tie, two time signature changes followed). No native test
  reaches it (a short time signature test doesn't remove the incoming tie); the replay is the
  proof.
- `dom/score.cpp`: `changeSelectedElementsVoice` moves articulations from a copy of the list;
  moving one removes it from the list being walked, so every second articulation was left on
  the removed chord (AddressSanitizer: container overflow).
- `dom/stafflines.cpp`: `StaffLines::pagePos` falls back to the measure's position when the
  measure has no system or the system lacks the staff, instead of dereferencing null (Play build
  29 crash while drawing a page; not reproduced).
- `editing/undo.h`: `UndoStack::clearHistory()` drops every undo and redo step and keeps whether
  the score counts as modified. The bridge calls it when it builds a part score
  (`setActivePartIndex` in `score_render_open_save.cpp`, also reached by exporting parts): Aria
  builds parts outside undo, so undoing an edit made before that changed only the full score and
  left the part linked to deleted elements (stress test mmrest-25-systemLock, seed 29001: note
  entry then undo read freed memory). Desktop records part creation as an undoable step instead.
- `infrastructure/mscreader.cpp`: `excerptFileNames` sorts parts by their `<index>_` file-name
  prefix, so a score saved as a folder (not a zip) reopens with its parts in order rather than
  in directory order. Zipped files are already in that order.

- `dom/masterscore.cpp`: `clone()` gives the copy the original's file-info provider before
  laying it out. Without it, header and footer macros that read file info (`$f`, `$F`, `$m`,
  `$M`, `$D`) crashed when Aria set a temporary viewing key (Play Console, Android).

MusicXML import:
- `importexport/musicxml/internal/import/importmusicxmlpass2.cpp`: unfinished-tie cleanup skips
  laissez-vibrer ties. A repeated cleanup entry could otherwise attach an end-note backlink to
  a let-ring tie, then delete that tie and leave layout reading freed memory. The scan-result
  regression and ordinary-tie control cover import, layout, save and reopen in
  `sandbox/engraving/tests/score_render_accidental_tests.cpp`.
- `importexport/musicxml/internal/import/importmusicxmlpass2.cpp` (+ its tests and reference files): explicit
  `<sound>` jump and marker attributes (`dacapo`, `dalsegno`, `fine`, `segno`, `coda`, `tocoda`) are imported as
  jumps and markers whatever the "infer text type" setting (off in Aria), and the words beside a D.C./D.S. refine
  it ("D.C. al Fine"). Upstream commit `cfddbc801e` (MuseScore #33802, for #33801), applied unchanged. Scanned
  scores (ScannerCore 0.1.4) write these attributes so their printed D.S. al Coda plays. Files are unaffected:
  the round trip stayed 890 of 892 (lyrics-15/16 as before).

Rendering hook:
- `rendering/paintoptions.h`, `dom/engravingitem.cpp`: `PaintOptions::overrideItemColor`
  (ported from MuseScore 5) so Aria can draw its own selection colors. Display only.

Performance:
- `src/framework/draw/internal/qimageprovider.cpp`: `createPixmap` keeps a picture's
  original bytes and reads its size from the header, instead of decoding it and
  re-encoding it as PNG (about 2 s for a large title-frame picture). Every reader decodes
  a `Pixmap` with `loadFromData`, so the drawn pixels are the same. Files are unaffected.

iOS and Android build plumbing (no effect on the Mac build):
- `src/framework/draw/CMakeLists.txt`, `drawmodule.cpp`: iOS uses Qt's font provider only
  (`DRAW_QT_FONT_PROVIDER_ONLY`), no FreeType/HarfBuzz font engine.
- `src/framework/draw/cmake/SetupHarfBuzz.cmake`: use Qt's bundled HarfBuzz on iOS.
- `src/framework/global/CMakeLists.txt`, `buildscripts/cmake/SetupBuildEnvironment.cmake`:
  macOS-only pieces (AppKit helper) are skipped for iOS, which CMake also reports as `OS_IS_MAC`.
- `src/framework/global/internal/interactive.cpp`: iOS uses the QML file-dialog path
  (as Linux does) because the render core has no QtWidgets.
- `src/engraving/CMakeLists.txt`: `ENGRAVING_NO_API` option; dtl include path.
- Android builds take the same branches as iOS in `draw/CMakeLists.txt`,
  `global/CMakeLists.txt` and `SetupBuildEnvironment.cmake` (Qt font provider only, no
  macOS helper). Android code otherwise takes the engine's Linux paths (`Q_OS_LINUX`).

Compiler fixes: `global/api/interactiveapi.cpp` (Qt 6.11 needs `<QMetaEnum>`),
`global/api/apiutils.h`, `global/io/internal/filesystem.h`, `audio/devtools/inputlag.h`,
`fluidsynth_priv.h`, `playback/renderers/bendsrenderer.cpp`.

Bridge-side adaptations (in `sandbox/engraving/`, not the engine):
- `score_render_application_stub.h` reports version 4.7.7 / revision b750c43, which the
  engine writes into `<programVersion>`/`<programRevision>`.
- Files newer than 4.70 (MuseScore 5) are opened anyway, like desktop's "Open anyway",
  and saved back as 4.70 (`loadScoreForRenderCore`).
- After loading, Aria runs the same setup as desktop's `EngravingProject::setupMasterScore`
  (`setupLoadedMasterScore` in `score_render_runtime.cpp`) and its post-layout compat step.
  Without the padding-table rebuild, files whose spacing style differs from the defaults
  (mostly 2.x/3.x) were spaced differently from desktop.
- Opened scores start from the default style, as desktop does, so files that store no
  page size get Letter or A4 from the device region (`score_render_open_save.cpp`).
- The bundled templates in `ScoreTemplates.bundle` are MuseScore 4.7.5's own templates
  (4.7.6 did not change them), except Big Band, Jazz Combo and Bluegrass Band, which are
  4.7.7's.

## Updating to a newer MuseScore release

How the moves to 4.7.6 and 4.7.7 were done (no patch branch needed):

1. Download the new release's source (`codeload.github.com/musescore/MuseScore/tar.gz/refs/tags/<tag>`)
   and extract the current tag from git (`git archive <tag>`; the 4.7.7 move downloaded both tags instead).
2. Diff the engine folders (`src share buildscripts thirdparty fonts` and the root CMake files)
   between the two and apply that patch here with `patch -p1`; resolve any conflict with an
   Aria patch by hand and copy changed binary files. The GitHub source archive leaves out
   `buildscripts/ci/crashdumps`, so restore that folder from git afterwards.
3. Update the version and revision in `sandbox/engraving/score_render_application_stub.h`.
4. Build the Mac host (`build-aria-475-host`, see README.md) and run: the native tests
   (`ctest`), `roundtrip_475.py` (default and `--direct`) against the matching desktop release,
   `playback_sweep.py`, `layout_compare.py`, and `musicxml_export_sweep.py`. Then rebuild the
   iOS and Android engines.
