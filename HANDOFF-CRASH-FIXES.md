# Handoff: engine crash fixes from the random-edit stress test (November 25, 2026)

Untracked working note. Paths are repo-relative.

**November 26: all fixes below are committed in `d1160b27d3`.** Rechecked before committing: layout
842/842, live drawing 376/380 (same four), fuzz seed 29 render mode 0 crashes, plain mode 1 crash
(mmrest-25-systemLock, open, below). Left to do: the owner's decision on mmrest-25, and rebuilding
the iOS render core and the Android engine before the next release. Delete this file after that.

**Later, November 26: mmrest-25 fixed in its own commit (BUG-045).** The owner chose to clear undo
when a part score is first built. Fuzz seed 29 now has 0 crashes in both modes. Only the iOS and
Android engine rebuilds before the next release are left.
Read `AGENTS.md`, `sandbox/engraving/compat/README.md` and `sandbox/engraving/compat/ENGINE.md` first.

## Already committed

- `9c5b9f4d08` iPad Pencil crash (BUG-033, another session's fix).
- `5dd56b1c72` Score details crash, BUG-034 time-signature runaway, fuzz page drawing
  (`ARIA_FUZZ_RENDER=1`) and the fuzz memory cap (`fuzz_edits.py --max-memory`).
- `fb3a31899b` Android keeps unchanged bundled files across updates.
- The owner then committed `2d3dd5b254` (release prep iOS 7.7.2 (19), Android 1.4.2 (30)).
  The fixes below are **not** in that release.

## Uncommitted in the working tree (all verified, not yet committed)

| Fix | Files | Verified by |
| --- | --- | --- |
| BUG-040: tuplet freed twice on close. `Score::endCmd` drops a command's `RemoveElement` of a tuplet that chords still use (note entry over a tuplet's only chord removed the chord, which removed the tuplet, then refilled it) | `src/engraving/editing/cmd.cpp` (`keepTupletsStillInUse`), `undo.h` (`takeChild`), `addremoveelement.h` (`removedElement`) | Fuzz replays tuplets-7 29000, articulation-11 29002, beams-21 29008 clean (Release and ASan). Test `a note over a tuplet's only chord keeps the tuplet` fails under ASan without the fix |
| BUG-041: part selection left in removed bars. `deleteMeasures` deselects in every score | `src/engraving/editing/edit.cpp` | tuplets-7 29000 with `--check-every 1000 --steps 60` and grace-11 29036 (render) no longer crash. Its test does **not** reproduce the crash (passes without the fix too); said so in its comment |
| Bridge ignores a note-input position in a removed bar | `sandbox/engraving/score_render_runtime.cpp` (`activeChordRest`) | Defensive; not shown to be needed alone |
| Voice change lost every second articulation (ASan container overflow) | `src/engraving/dom/score.cpp` (`changeSelectedElementsVoice`) | Test `a voice change moves every articulation` fails under ASan without the fix |
| Guard for Play build 29 `StaffLines::pagePos` crash | `src/engraving/dom/stafflines.cpp` | Not reproduced; null guard only |
| Docs | `sandbox/engraving/compat/ENGINE.md` (4 entries), `MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md` (BUG-040, BUG-041) | |
| Tests | `sandbox/engraving/tests/score_render_accidental_tests.cpp` (3 tests) | All pass in Release |

Also cleared by these fixes (replays no longer crash): measure-repeat-1 29038 (render, range-select
crash) and ornament-2 29021 (render and plain; tuplet layout crash).

No temporary diagnostics are left in the source (`grep -rn ARIA-DIAG src sandbox` is empty).

## Still to do, in order

1. ~~Goldberg paste finding~~ **Done (uncommitted), BUG-042.** The articulation was removed twice
   by one `deleteRangeAtTrack` call: once with its grace note's anchored elements, then again from
   the chord's anchored set, which had listed it already (order depends on pointer hashing).
   Fix in `src/engraving/editing/edit.cpp`; ENGINE.md, compat README and backlog updated. The ASan
   replay (seed 1039) now ends `DONE 12 failure(s)` with no ASan error (the checkpoint failures are
   the paste's stale/round-trip differences, same numbers as before the fix). Test `deleting grace
   note articulations removes each once` fails under ASan with the fix off, passes with it.
   Temporary trace removed.
**Status, evening of November 25:** Full checks passed on everything up to BUG-042 (ctest 10/10, round trip
890/892 both modes, layout 842/842, stale 376/380). Fresh fuzz: render mode 0 crashes (was 5); plain mode found two
new ones:
- **articulation-11 seed 29002: fixed (BUG-044)**, `src/engraving/dom/range.cpp` `ScoreRange::read` unlinks an incoming
  tie before removing it; ASan replay closes cleanly. No native test reproduces it.
- **mmrest-25-systemLock seed 29001: NOT fixed, needs the owner's decision.** Aria builds a part view outside undo
  (`initAndAddExcerpt(excerpt, true)` in `score_render_open_save.cpp`); undoing an edit made before the part existed
  changes only the full score, the part keeps a copy linked to the deleted element, and a later note entry + undo uses
  freed memory. Desktop records part creation as undoable. Options put to the owner: end undo history when a part is
  first built, make it undoable like desktop, or build all parts at open.
After the BUG-044 fix: host build, ctest 10/10, round trip 890/892 both modes (same lyrics-15/16). Layout (814/842),
stale sweep and the fuzz rerun were broken by the disk filling up (other processes; under 1 GB free), so **rerun
layout, stale and both fuzz modes** before committing.

2. **Full checks** (rule in `AGENTS.md` after any engine change), Release host build:
   ```sh
   cmake --build build-aria-475-host
   (cd build-aria-475-host && QT_QPA_PLATFORM=offscreen ctest -j4 --output-on-failure)   # expect 10/10
   python3 sandbox/engraving/compat/roundtrip_475.py --out <dir>            # baseline 890/892 (lyrics-15/16)
   python3 sandbox/engraving/compat/roundtrip_475.py --direct --out <dir>   # same
   PAPERSIZE=letter python3 sandbox/engraving/compat/layout_compare.py --out <dir>   # 842/842
   ARIA_STALE_RENDER_DIR=<dir> QT_QPA_PLATFORM=offscreen build-aria-475-host/score_render_edit_sweep_tests
   python3 sandbox/engraving/compat/compare_stale_renders.py <dir>          # 376/380, same four
   ```
3. **Fresh stress runs** with the fixes, both modes, and compare with the earlier counts
   (seed 29: plain 2 crashes, render 5 crashes):
   `python3 sandbox/engraving/compat/fuzz_edits.py --scores 40 --steps 150 --seed 29 --check-every 25 --out <dir>`
   and the same with `ARIA_FUZZ_RENDER=1`. Fix anything new the same way (replay, ASan, fix,
   test), then commit.
4. **Commit** the working-tree changes (one engine commit is fine). No Claude co-author trailer,
   no `/Users/...` or `/tmp` paths, don't push. Leave `HANDOFF-SCAN.md` (another session's,
   contains local paths) and this file out.
5. Before the next store release: rebuild the iOS render core and the Android engine
   (`MuseReaderAndroid/scripts/build-render-core.sh`, then `build-engine.sh`), since `src/` changed.

## Gotchas

- Release builds hide these bugs: freed memory often still looks valid, so crashes come and go.
  Use the ASan build `build-aria-475-asan` (RelWithDebInfo, already configured; build only the
  targets you need: `score_render_fuzz`, `score_render_accidental_tests`).
- `--check-every` and `--steps` change the edit sequence (checkpoints draw extra random edits).
  To shorten a repro keep `--check-every` the same and lower `--steps`.
- Run a single native test with `ARIA_TEST_FILTER="<part of its name>"`.
- The shell is zsh: `set -- $var` doesn't split words; pass arguments explicitly.
- Disk filled twice today (once from the BUG-034 runaway through swap). Check `df -h /` before
  long runs; `fuzz_edits.py` now stops a score at 4 GB.
- Parts merge two or more empty bars into a multi-bar rest, which hit testing doesn't report as a
  rest; tests find bars through notes.
