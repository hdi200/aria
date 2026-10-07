# Aria's MuseScore engine

`src/`, `share/`, `buildscripts/`, `thirdparty/`, `fonts/` and the root CMake files are
MuseScore Studio **4.7.5** (tag `v4.7.5`, commit `3654226`) plus a small set of Aria
patches listed below. Aria saves genuine 4.70 files that 4.7.5 opens without warnings.

Before September 2026 the engine was an April 2026 snapshot of upstream `main`
(commit `e280c3b6`, format 5.00) that relabeled its saves as 4.70. That relabel is gone.

## Aria patches on top of 4.7.5

They were produced on a branch `aria-475` (based on `v4.7.5`) in a separate MuseScore
clone. If that clone is gone, recreate the patch by diffing these folders against a
checkout of `v4.7.5`.

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
- `infrastructure/mscreader.cpp`: `excerptFileNames` sorts parts by their `<index>_` file-name
  prefix, so a score saved as a folder (not a zip) reopens with its parts in order rather than
  in directory order. Zipped files are already in that order.

Rendering hook:
- `rendering/paintoptions.h`, `dom/engravingitem.cpp`: `PaintOptions::overrideItemColor`
  (ported from MuseScore 5) so Aria can draw its own selection colors. Display only.

Performance:
- `src/framework/draw/internal/qimageprovider.cpp`: `createPixmap` keeps a picture's
  original bytes and reads its size from the header, instead of decoding it and
  re-encoding it as PNG (about 2 s for a large title-frame picture). Every reader decodes
  a `Pixmap` with `loadFromData`, so the drawn pixels are the same. Files are unaffected.

iOS build plumbing (no effect on the Mac build):
- `src/framework/draw/CMakeLists.txt`, `drawmodule.cpp`: iOS uses Qt's font provider only
  (`DRAW_QT_FONT_PROVIDER_ONLY`), no FreeType/HarfBuzz font engine.
- `src/framework/draw/cmake/SetupHarfBuzz.cmake`: use Qt's bundled HarfBuzz on iOS.
- `src/framework/global/CMakeLists.txt`, `buildscripts/cmake/SetupBuildEnvironment.cmake`:
  macOS-only pieces (AppKit helper) are skipped for iOS, which CMake also reports as `OS_IS_MAC`.
- `src/framework/global/internal/interactive.cpp`: iOS uses the QML file-dialog path
  (as Linux does) because the render core has no QtWidgets.
- `src/engraving/CMakeLists.txt`: `ENGRAVING_NO_API` option; dtl include path.

Compiler fixes: `global/api/interactiveapi.cpp` (Qt 6.11 needs `<QMetaEnum>`),
`global/api/apiutils.h`, `global/io/internal/filesystem.h`, `audio/devtools/inputlag.h`,
`fluidsynth_priv.h`, `playback/renderers/bendsrenderer.cpp`.

Bridge-side adaptations (in `sandbox/engraving/`, not the engine):
- `score_render_application_stub.h` reports version 4.7.5 / revision 3654226, which the
  engine writes into `<programVersion>`/`<programRevision>`.
- Files newer than 4.70 (MuseScore 5) are opened anyway, like desktop's "Open anyway",
  and saved back as 4.70 (`loadScoreForRenderCore`).
- After loading, Aria runs the same setup as desktop's `EngravingProject::setupMasterScore`
  (`setupLoadedMasterScore` in `score_render_runtime.cpp`) and its post-layout compat step.
  Without the padding-table rebuild, files whose spacing style differs from the defaults
  (mostly 2.x/3.x) were spaced differently from desktop.
- Opened scores start from the default style, as desktop does, so files that store no
  page size get Letter or A4 from the device region (`score_render_open_save.cpp`).
- The bundled templates in `ScoreTemplates.bundle` are MuseScore 4.7.5's own templates.

## Updating to a newer MuseScore release

1. In a MuseScore clone that has the patch branch (`aria-475`, based on `v4.7.5`),
   fetch the new tag and rebase: `git rebase --onto v4.7.6 v4.7.5 aria-475`.
   Drop any patch the new release already contains.
2. Copy `src share buildscripts thirdparty fonts` and the root CMake files into this repo.
3. Update the version and revision in `sandbox/engraving/score_render_application_stub.h`.
4. Build the Mac host (`build-aria-475-host`, see README.md) and run: the native tests
   (`ctest`), `roundtrip_475.py` (default and `--direct`), `playback_sweep.py`, `layout_compare.py`, and
   `musicxml_export_sweep.py`. Then build the iOS app.
