# Active Context

## Current Focus

The project has moved past a one-shot rendering prototype and now has a session-oriented reading path, native playback, score-following playback UI, a first real notation-editing slice, and an app-owned internal score library. The immediate focus is validating the new note-editing path on iPad, making sure those edits save cleanly against the imported canonical copy, and tuning the new editor surfaces based on device feel rather than expanding scope immediately.

## Recent Changes

- Added a reusable C++ `ScoreRenderSession` in `sandbox/engraving/score_render_core.*`.
- Added an ObjC++ bridge session type, `MSRRenderSession`, in `MuseReaderiOS/MuseReaderiOS/Bridge/MuseScoreRenderCoreBridge.*`.
- Changed `ScoreSessionService` so score opening prefers a live MuseScore render session and falls back to embedded previews when necessary.
- Added `LiveScoreRenderSession` and `ScoreReaderState` so Swift can lazily request pages and cache them.
- Refactored `ScoreReaderView` to load/render pages on demand instead of assuming all pages are materialized up front.
- Updated `ScoreDetailView` messaging so documents with no embedded previews can still open the live reader cleanly.
- Reworked the native SwiftUI presentation layer to better match the intended tablet product direction:
  - Maestro-style white/indigo/pastel library shell modeled on the latest product mock
  - fixed connected split layout with a docked sidebar, search header, and import CTA
  - pastel score-card dashboard for the library grid state
  - library thumbnails now use real embedded preview art when available instead of always falling back to placeholder lines
  - when a real preview exists, the decorative color header is removed and the full rounded card becomes a first-page preview surface
  - imported/opened scores now backfill their library card image with a cached live render of page 1, so the dashboard can graduate from low-res embedded package thumbnails without rendering every card live
  - library cards now open the full-screen reader directly instead of swapping the right pane back to the old detail screen
  - each library card now exposes a compact info popover for composer, subtitle, format, import date, storage location, and MuseScore version
  - stronger score detail hero and horizontal preview strip
  - cleaner page-based reader chrome with top controls and floating zoom
- Replaced `NavigationSplitView` with a fixed connected split layout in the library shell so the sidebar stays docked and cannot slide over the detail pane on iPad.
- Added MIDI export support to the reusable score session instead of trying to pull MuseScore's full desktop playback stack into the iOS build.
- Added a native `NativeMIDIPlaybackController` using `AVAudioSession`, `AVAudioEngine`, `AVAudioSequencer`, and Apple’s `MIDISynth` music device.
- Wired the reader state and reader UI to a compact playback strip with play, pause, stop, position, and error reporting.
- Replaced the first playback attempt that depended on external sound bank discovery with the iOS MIDI synth path in AudioToolbox.
- Added a score-detail export action that writes the live session's playback MIDI to a temporary `.mid` file and opens the native iOS share sheet for debugging/export.
- Confirmed on-device that the exported MIDI file is valid and plays correctly outside MuseReader, which rules out MuseScore's MIDI export as the current playback blocker.
- Added a first bundled-bank attempt by copying `MS Basic.sf3` into the app resources and loading it into `AUMIDISynth` before playback.
- Fixed the `AudioUnitSetProperty(... kMusicDeviceProperty_SoundBankURL ...)` call so Swift passes the sound-bank URL as an object pointer payload instead of taking an unsafe pointer to the bridged `CFURL` value, which had been causing a runtime breakpoint.
- Bundled `MuseScore_General.sf2` into the iOS app resources so the playback layer has a compatible SoundFont 2 bank available in the app bundle.
- Replaced the temporary default iOS graph fallback with an `AVAudioEngine`-hosted Apple `MIDISynth` music device that loads the bundled `MuseScore_General.sf2` bank and plays the exported MuseScore MIDI through `AVAudioSequencer`.
- Extended the reusable C++ `ScoreRenderSession` to export playback measure regions with real page-relative measure rectangles and repeat-aware playback timing.
- Extended `MuseScoreRenderCoreBridge` and `LiveScoreRenderSession` so Swift can request those playback measure regions once and cache them beside page renders and MIDI data.
- Updated `ScoreReaderState` so playback polling now derives an active measure highlight from the cached playback regions and auto-follows playback to the active page while the score is playing.
- Updated `ZoomableImageView` to draw the active measure highlight and progress fill inside the zoomed page content so the overlay stays aligned during zooming and panning.
- Tightened score-follow timing by reducing playback polling to 50ms and adding a small iOS output-latency compensation offset for the active-bar overlay/page-follow logic.
- Extended the reusable C++ `ScoreRenderSession` so it now supports metadata mutation and save-back to the original `.mscz` or directory-style `.mscx` file.
- Extended `MuseScoreRenderCoreBridge` and `LiveScoreRenderSession` so Swift can call `updateMetadata(...)` and `save()` on the live score session without exposing Qt or MuseScore types directly.
- Updated `ScoreSessionService` capability reporting so editing is surfaced as an available capability when the live session supports it.
- Added an app-model save flow in `MuseReaderAppModel` that applies metadata edits through the live session, saves back to disk, reopens the document as a fresh `ScoreSession`, and refreshes the recent-file record.
- Added a first native metadata editor sheet in `ScoreDetailView` for title, subtitle, composer, arranger, and lyricist, with `Edit Info` entry points in both the detail hero and the score-summary section.
- Changed the iOS save path so `MuseReaderAppModel` now coordinates writes with `NSFileCoordinator` and passes the coordinated file URL down into the live render session.
- Removed the macOS-only `.withSecurityScope` bookmark flags from the iOS app model; iPad recents now use plain bookmark data plus `startAccessingSecurityScopedResource()` on the resolved URL.
- Extended `ScoreRenderSession` and `MuseScoreRenderCoreBridge` with a save-to-path/save-to-URL override so the render core can write to the exact URL handed back by iOS file coordination.
- Added `ManagedScoreLibrary`, which copies imported `.mscz` or `.mscx` documents into `Application Support/MuseReaderLibrary` and resolves canonical internal URLs for the app.
- Moved the library index out of `UserDefaults` into a JSON file under `Application Support`, while keeping a one-time migration path for legacy bookmark-backed entries.
- Changed import/reopen flow in `MuseReaderAppModel` so new imports and reopened legacy entries are funneled into the internal library before opening a `ScoreSession`.
- Updated the library UI copy so it now clearly describes import into MuseReader’s private library instead of bookmarking external Files locations.
- Extended the reusable C++ `ScoreRenderSession` with note-editing state and commands for selection, note input, duration, rest mode, pitch movement, delete, undo, and redo.
- Extended `MuseScoreRenderCoreBridge` and `LiveScoreRenderSession` so Swift can fetch current editing state and drive those commands without exposing MuseScore types directly.
- Added `ScoreEditingState`, `ScoreSelectedElement`, and `ScoreNoteDuration` on the Swift side so the reader can reflect selection and note-input state natively.
- Updated `ScoreReaderState` so reader taps can either select notation elements or insert notes, and score mutations now invalidate rendered pages plus cached playback artifacts.
- Reworked `ScoreReaderView` so the old compact edit strip is now split into:
  - a floating left editor rail for note-input mode, duration, rest mode, delete, undo/redo, and save
  - a contextual bottom editor deck that now behaves like a pitch keyboard for selected-note editing instead of a generic utility strip
- Extended the reusable editing bridge so Swift now receives the selected note’s MIDI pitch and can:
  - shift the selected note chromatically by semitone
  - shift the selected note by octave
  - retune the selected note to a chosen pitch class from a keyboard-style control
- Fixed the keyboard pitch action so it now retunes the selected note to the requested pitch class in the current octave through an exact MuseScore pitch-change command instead of relying on relative nearest-step movement.
- Extended note input into a continuous workflow: the bottom keyboard now stores the next pitch while note-input mode is active, the first staff tap places that pitch and establishes the MuseScore input cursor, and later keyboard taps insert at the advancing cursor through the live C++ session.
- Changed duration/subdivision changes so note-input mode updates only the next input duration instead of modifying the last inserted selected note.
- Split the top-left editor rail mode control into separate cursor and note-input buttons so mode selection is explicit instead of one ambiguous toggle.
- Reworked the reader shell from a page-snapping `TabView` into a full-screen vertical page stack so editing can feel like one scrollable canvas, while the editor rail and bottom keyboard float above the stacked pages.
- Simplified the reader chrome again so the old top information bar is gone; the score now keeps only a floating `Library` button on the top left and a floating play/pause button on the top right.
- Updated `ZoomableImageView` so the page overlay now supports both playback highlighting and a live selection rectangle, and can report normalized tap locations back to the reader state.

## Current Working Mental Model

The app should be treated as a native shell around a live score session:

- package inspection provides quick metadata and previews
- a live score session provides authoritative page rendering
- the live score session provides authoritative score data for future features
- imported files should be treated as app-owned canonical copies, not the long-term source of truth in external Files locations
- the library shell should feel like a polished iPad document app with a crisp connected split layout, bright white surfaces, indigo accents, and pastel score cards
- library cards should behave like direct reader launch points; lightweight metadata belongs in a popover, not a mode switch back to the old inspection pane
- library thumbnails should come from cached rendered page-1 images when possible, not from live per-card rendering at dashboard time
- playback currently comes from exporting MIDI from that live session and handing it to a native iOS audio engine
- score-following playback currently comes from a measure timeline exported by the live session and matched against the native playback clock
- editing now includes a narrow note/rest workflow through the live session, not just metadata mutation
- the reader’s editor UI should now feel like an actual tablet editor surface instead of a temporary debug strip
- the left rail should own explicit mode controls plus durable note-entry/edit controls, while the bottom deck should behave like a pitch-entry surface
- in note-input mode, the bottom keyboard should choose the next pitch and then keep entering notes at the advancing MuseScore cursor after the first staff placement
- the editing reader should feel like a full-screen canvas with stacked pages rather than a swipe-between-pages viewer
- reader chrome should stay minimal; informational labels should not compete with the score while editing
- broader editing should continue to attach to the live session layer instead of bypassing it

## Immediate Next Steps

1. Test selection and tap-to-enter note on iPad with real treble/bass staff scores.
2. Re-test delete, keyboard-driven pitch changes, duration change, rest toggle, undo/redo, and save against imported `.mscz` files using the new full-screen scroll editor UI.
3. Test continuous note entry on iPad: choose a keyboard pitch, tap a standard staff once, then keep pressing keyboard notes and verify the cursor advances musically.
4. Confirm playback export/follow state refreshes correctly after notation edits, not just metadata edits.
5. Re-test save and reopen on iPad so notation edits survive relaunch against the app-owned library copy.
6. Decide the next editing slice only after this one feels stable:
   - better note-input affordances
   - richer selection visuals
   - stronger keyboard-driven entry behavior
   - non-note element editing
7. Tune the full-screen scroll reader only after the new editing flow feels correct on device:
   - keyboard centering and touch feel
   - page spacing and overlay clearance
   - whether playback follow should auto-scroll more aggressively
   - whether the new top-left/top-right floating controls feel balanced enough without extra chrome

## Active Decisions

- Native iOS UI is preferred over React Native for the notation experience.
- MuseScore C++ is being reused for score/session/render logic, not for the UI shell.
- Read-only is the current feature scope, but the architecture must not assume the app will stay read-only.
- Embedded previews are a fallback, not the primary rendering strategy.
- The reader/editor now uses a full-screen stacked-page scroll layout for editing, but still keeps the existing page-based render/cache model under the hood.
- The library should stay visually stable while opening scores; tapping a score should not replace the dashboard with the legacy detail UI.
- Playback should use native iOS audio over exported MIDI for now instead of forcing MuseScore's full notation/audio stack into the iOS build.
- The current playback UI should stay compact; no full bottom transport bar yet.
- Annotation tools should not be shown until the underlying capabilities exist.
- Exporting the generated MIDI file is now part of the playback debugging strategy on device.
- The playback foundation should stay on `AVAudioEngine` rather than the default `MusicPlayer` graph so the app has a less disposable audio architecture.
- Score-following playback should come from the MuseScore session's own timing and measure geometry, not from inferred page timing on the Swift side.
- The first notation-editing slice should stay narrow and mobile-native rather than copying MuseScore desktop UI.
- Custom iPad editing UX is acceptable as long as the actual score mutations still route through the MuseScore core.
- The app should now prefer app-owned canonical score copies in `Application Support` over bookmarking external Files locations.
- The editor should keep moving toward a tablet-specific layout: durable controls on the left, pitch-focused controls on the bottom, and no attempt to mirror desktop MuseScore palettes exactly.
- Editing should happen inside a full-screen scrollable page stack rather than a page-snap reader when that makes the score feel more direct and touch-native.
- Playback controls in the reader should stay as light as possible unless richer transport is actually needed.
- Post-edit page refreshes should not blank the score or drop into a blocking placeholder if a stale live render is already available. Keeping the old page visible while a fresh render replaces it is the preferred behavior.

## Important Constraints

- The render core depends on a Qt for iOS SDK and matching host Qt SDK.
- The iOS project uses a custom build phase that compiles the render core into `/tmp`.
- Simulator support is constrained by the available Qt iOS SDK; the current setup excludes `arm64` for the simulator.
- Real-device validation matters more than simulator polish right now.
- Native playback currently depends on Apple’s `MIDISynth` music device plus the bundled `MuseScore_General.sf2` bank, so runtime validation still matters.
- The exported MIDI has now been verified externally, so the current playback issue is in the app's native iOS playback configuration rather than MuseScore export correctness.
- The active-bar overlay depends on normalized measure rectangles from the render core and a polling playback clock in Swift, so on-device validation matters for both timing feel and visual alignment.
- The current timing pass intentionally compensates only the score-follow overlay/page-follow logic, not the audio path itself.
- The new save path writes through `NSFileCoordinator` on iOS and then through the live session, so `.mscx` directory saves and external-file-provider behavior still need real-device validation.
- The internal library index and score copies now live under `Application Support`, so migration from old bookmark-backed entries depends on reopening them at least once.
- The new note-entry path is currently standard-staff only; drum/tab-specific editing is intentionally deferred.
- Editing currently uses raw engraving-level hit-testing and command calls rather than the full MuseScore desktop notation scene, so touch behavior will need device tuning.

## Learnings

- MuseScore package inspection is useful immediately, even before editing exists.
- The wrong architecture for this app would be eager full-document rendering; it wastes memory and does not scale toward playback/editing.
- A persistent score session is the correct boundary between the native UI and the MuseScore engine.
- For iOS playback, exporting MIDI from the live score session is much more practical than dragging in MuseScore's desktop playback runtime.
- `AVMIDIPlayer` was the wrong abstraction here because it requires an explicit SoundFont/DLS file on iOS and gives less control over the playback graph.
- Apple’s default iOS `MusicSequence` graph is not the right long-term foundation for multi-track MuseScore playback on iPad.
- `AVAudioEngine` can still host Apple audio units, so the app can keep a more modern engine shell while relying on the multitimbral `MIDISynth` music device for GM playback.
- `src/notation/internal/positionswriter.cpp` already contains the important MuseScore logic for repeat-aware measure timing and page-relative measure geometry, so the iOS app should reuse that model instead of inventing a Swift-only approximation.
- Metadata editing is the correct first editing slice because it proves the live session can mutate authoritative score state, save the original file, and reopen cleanly without introducing note-entry UI complexity yet.
- iOS bookmark APIs differ from macOS here: `.withSecurityScope` is unavailable on iOS, so persistent file access has to rely on plain bookmark data plus coordinated reads/writes and security-scoped URL access on the resolved file URL.
- MuseReader’s product model is cleaner if Files import is just ingestion; once copied into `Application Support`, the app can own save-back and future editing without depending on external provider semantics.
- MuseScore compatibility does not require copying desktop MuseScore interaction patterns; it requires routing edits through MuseScore’s own score model and save path.
- A bottom keyboard can be a real editing control here as long as it retunes the authoritative selected MuseScore note instead of inventing a separate pitch model in Swift.
- Continuous keyboard entry works best when Swift owns only pending pitch/UI state and MuseScore owns the actual input cursor, note insertion, undo, relayout, and save.
- The full-page loading placeholder was acceptable for first-load and missing-page states, but it is too disruptive after edits. A small in-place loading indicator is enough when rerendering an already visible page.
