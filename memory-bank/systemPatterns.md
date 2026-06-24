# System Patterns

## Architecture Overview

The current architecture is a hybrid system:

1. SwiftUI app shell and native iOS media services
2. ObjC++ bridge layer
3. MuseScore/Qt/C++ score core

This keeps the native iPad UI separate from the score engine while still reusing MuseScore's rendering, file-loading, playback-export, and editing/save-back capabilities. Playback is intentionally native on iOS even though score loading, layout, and score mutation are reused from MuseScore. The app now also owns a private score library in `Application Support`, so imported files are treated as app-managed copies rather than external Files documents.

## Primary Flow

1. `MuseReaderAppModel` coordinates Files import, internal-library records, and the currently opened `ScoreSession`.
2. `ManagedScoreLibrary` copies imported scores into `Application Support/MuseReaderLibrary` and resolves canonical internal URLs.
3. `MuseScoreSessionService` opens a canonical score URL.
4. `MuseScoreDocumentService` inspects the file/package and extracts metadata, package entries, root score XML, and preview assets.
5. The render bridge attempts to open a live `MSRRenderSession`.
6. Swift builds a `ScoreSession` that combines:
   - document metadata
   - preview pages, if any
   - capability flags
   - an optional live render session
7. `RecentDocumentsStore` persists the app-owned library index as JSON under `Application Support` and still understands legacy bookmark-backed entries.
8. `MuseReaderAppModel` backfills a cached rendered page-1 library thumbnail after a successful session open when the live renderer is available.
9. `ScoreReaderState` manages page selection, lazy loading, caching, page render errors, and reader playback state.
10. `ScoreDetailView` can now open a metadata editor, and `MuseReaderAppModel` routes the resulting save through the live session before reopening a fresh `ScoreSession`.
11. `ScoreReaderView` now exposes a floating left editor rail plus a bottom pitch keyboard deck over a full-screen vertical page stack, with only a floating library button and a floating play/pause button at the top, and `ScoreReaderState` routes page taps plus edit commands through the same live session.

## Key Design Patterns

### Session-Oriented Document Model

`ScoreSession` is the central app model for an opened score. It is intentionally broader than “a list of pages.” This is the future attachment point for playback, editing commands, save-back, and richer document state.

### App-Owned Library

MuseReader now treats imported scores as internal library items:

- Files import is only the ingest path
- imported scores are copied into `Application Support/MuseReaderLibrary`
- the persisted library index stores metadata plus the relative path to the app-owned canonical file
- legacy bookmark-backed entries can still be reopened, but the preferred path is to import them into the managed library and replace the old record

This keeps save-back, playback, and future editing attached to app-owned documents instead of fragile external file-provider URLs.

### Cached Rendered Library Thumbnails

The library dashboard should not render scores live card-by-card while it is visible. The current pattern is:

- use embedded package preview data immediately when it exists
- after a score opens successfully, ask the live render session for page 1 at thumbnail DPI
- persist that rendered image into the app-owned library record
- preserve the best existing thumbnail across normal record refreshes unless an explicit rendered replacement is available

This gives the dashboard sharper score art over time without turning the library into a live rendering surface.

### Fallback Rendering Strategy

The system uses a tiered approach:

- preferred: live MuseScore render session
- fallback: embedded preview assets stored inside the package
- failure state: metadata/inspection can still surface errors usefully

### Native Shell, Reused Engine

The UI layer is SwiftUI/UIKit-friendly and stays native. The bridge layer hides Qt/C++ details from Swift. The C++ layer owns score loading, layout, and page rendering.

### MIDI Export + Native Playback

Playback does not currently use MuseScore's desktop playback/runtime stack on iOS. The live C++ session exports MIDI bytes for the loaded score, and Swift plays them through `AVAudioEngine` with `AVAudioSequencer` plus Apple’s multitimbral `MIDISynth` music device. The app now bundles `MuseScore_General.sf2` so the synth has a compatible GM bank in the app bundle.

This keeps the playback path native on iPad while preserving the existing live score session as the document authority. It also avoids the default iOS `MusicSequence` graph, which is a weaker foundation for multi-track GM playback on iOS.

### Playback Timeline From The Score Core

Score-following UI does not guess measure positions on the Swift side. The reusable C++ `ScoreRenderSession` now exports repeat-aware playback measure regions: page index, start/end time, and normalized measure rectangle. Swift caches those regions in `LiveScoreRenderSession` and resolves the active measure from the current playback clock.

This keeps playback following tied to the same authoritative score session that renders pages and exports MIDI.

### Live-Session Save Back

Editing currently starts with score metadata only, but the important pattern is already in place:

- Swift gathers edited values in a native sheet
- `MuseReaderAppModel` invokes the live session
- the ObjC bridge forwards those values into the C++ `ScoreRenderSession`
- the C++ layer mutates MuseScore metadata/text objects, relayouts the score, and saves back to the canonical imported library copy
- Swift then reopens a fresh `ScoreSession` from disk

This keeps mutation and save-back attached to the same session boundary used for rendering and playback, which is the correct long-term pattern for broader editing.

### Thin Mobile Editing Bridge

The notation-editing path intentionally does not reuse MuseScore's desktop interaction shell. The current pattern is:

- Swift owns the iPad editing state machine and controls
- the ObjC++ bridge exposes a narrow editing API
- the C++ `ScoreRenderSession` performs hit-testing, selection export, note-entry settings, note/rest mutation, undo/redo, and save
- Swift only holds normalized geometry and UI-facing editing state, not an independent notation model

This preserves file compatibility while allowing the iPad UX to diverge from desktop MuseScore.

### Pitch Keyboard Over Selected MuseScore Notes

The bottom editor deck is no longer just a collection of generic action buttons. The current pattern is:

- the C++ session exports the selected note's MIDI pitch as part of editing state
- Swift uses that pitch only as UI-facing state for highlighting and pitch naming
- keyboard actions route back into the C++ session as semitone shift, octave shift, or target pitch-class retune commands
- the MuseScore score remains the only authoritative notation model and spelling source of truth

This makes the bottom keyboard honest: it is a real editor surface for the selected score note, not a decorative mockup.

### Continuous Note Input

Note-input mode now treats the bottom keyboard as the pitch-entry surface:

- Swift owns pending pitch and spelling preference as UI state
- the first staff tap in note-input mode inserts the pending pitch and establishes MuseScore's input cursor
- subsequent keyboard taps call back into the C++ session to insert at the current MuseScore cursor
- MuseScore owns cursor advancement, undo grouping, relayout, playback invalidation, and save-back

This keeps the workflow tablet-native while avoiding a second notation model in Swift.

### Full-Screen Scroll Editor

The reader is no longer constrained to a page-snapping container for editing. The current pattern is:

- the score pages are rendered into a vertical stack inside a native `ScrollView`
- the floating library button, floating play/pause button, left tool rail, zoom controls, and bottom keyboard all float over that canvas
- per-page zoom/pan still exists, but the inner page scroll view yields vertical scrolling back to the outer editor when the page is not zoomed in

This keeps the score feeling like one large editable surface while preserving the existing page-based render/cache model.

### Lazy Reader Loading

The reader does not eagerly render every page. `ScoreReaderState` loads the selected page and nearby pages on demand, which is better aligned with large scores and future playback/editing.

## Component Relationships

### SwiftUI Layer

- `MuseReaderiOSApp` launches `ContentView`
- `ContentView` owns `MuseReaderAppModel`
- `LibraryView` is the app entry point and now uses a fixed connected two-pane shell instead of `NavigationSplitView`
- `ScoreDetailView` summarizes an opened session with a hero section and preview strip
- `ScoreReaderView` is now a full-screen stacked-page reader/editor surface
- `ScoreReaderState` is the reader-specific state holder and now also owns reader editing state plus mutation invalidation
- `ScoreReaderView` now treats the left rail as the durable editing surface and the bottom deck as a pitch-entry surface for selected notes
- `ScoreReaderView` presents selection mode and note-input mode as separate rail buttons, while `ScoreReaderState.setNoteInputEnabled(...)` performs the actual mode change
- `NativeMIDIPlaybackController` owns native audio session setup, `AVAudioEngine`, `AVAudioSequencer`, and the `MIDISynth` audio unit used for playback
- `ZoomableImageView` is a UIKit-backed zoom surface that now owns both the active-measure overlay and the selection/tap overlay inside the zoomed content, and yields vertical scrolling to the outer reader when the page is not zoomed
- `RecentDocumentsStore` also acts as the persistence point for upgraded rendered library thumbnails

### Bridge Layer

- `MuseScorePackageBridge` reads `.mscz` archives and `.mscx` files
- `MuseScoreRenderCoreBridge` exposes the reusable render core to Swift
- `MSRRenderSession` holds a live native-facing session handle

### Engine Layer

- `ScoreRenderCore::initializeIfNeeded()` sets up the render runtime
- `ScoreRenderSession::open(...)` loads and lays out a score
- `ScoreRenderSession::renderPage(...)` renders one page at a time
- `ScoreRenderSession::playbackMIDIData(...)` exports MIDI bytes for native playback
- `ScoreRenderSession::playbackMeasureRegions(...)` exports repeat-aware measure timing and normalized rectangles for score-following playback UI
- `ScoreRenderSession::updateMetadata(...)` mutates score metadata and visible title-page text items
- `ScoreRenderSession::save(...)` writes the updated score back to the original `.mscz` or `.mscx` target
- `ScoreRenderSession::currentEditState(...)` exports the current note-input, selection, selected-note pitch, and undo state for the native reader UI
- `ScoreRenderSession::selectElement(...)`, `insertNote(...)`, `insertNoteWithPitch(...)`, `insertPitchAtCursor(...)`, `applyDuration(...)`, `toggleRest(...)`, `moveSelectionPitch(...)`, `shiftSelectionPitchBySemitones(...)`, `shiftSelectionPitchByOctaves(...)`, `setSelectionPitchClass(...)`, `deleteSelection(...)`, `undo(...)`, and `redo(...)` provide the current narrow notation-editing surface

## Critical Implementation Paths

### Import / Open Path

- Files app URL
- security-scoped resource access
- internal library copy into `Application Support/MuseReaderLibrary`
- package inspection
- live session open attempt
- `ScoreSession` creation
- library index update with an internal relative path
- asynchronous backfill of a cached rendered page-1 thumbnail for future library-card use

### Reader Path

- `ScoreReaderView` asks `ScoreReaderState` for current/nearby pages
- `ScoreReaderState` requests pages from `LiveScoreRenderSession`
- bridge session renders PNG bytes for a page
- Swift wraps rendered bytes into `ScorePage`
- the current reader stacks full rendered pages vertically in a `ScrollView`, keeps floating zoom controls, and lets page turns happen through normal scrolling

### Playback Path

- `ScoreReaderState` asks `LiveScoreRenderSession` for cached or newly exported MIDI data
- `ScoreReaderState` also asks `LiveScoreRenderSession` for cached playback measure regions
- the bridge calls into `ScoreRenderSession::playbackMIDIData(...)`
- the bridge also calls into `ScoreRenderSession::playbackMeasureRegions(...)`
- `NativeMIDIPlaybackController` configures `AVAudioSession`, loads the bundled `MuseScore_General.sf2` bank into Apple’s `MIDISynth` music device, loads the exported MIDI into `AVAudioSequencer`, and drives playback through `AVAudioEngine`
- the reader polls native playback state for progress and button state
- `ScoreReaderState` matches the playback clock against the cached measure regions, updates the active highlight, and follows playback to the active page while playing
- `ZoomableImageView` draws the active measure highlight and in-measure progress fill directly on top of the zoomed page content so the overlay stays aligned while zooming
- `ScoreDetailView` can export the same generated MIDI bytes to a temporary `.mid` file and present a native share sheet so playback issues can be debugged outside the app

### Metadata Edit / Save Path

- `ScoreDetailView` presents a native `Edit Score Info` sheet
- the sheet edits `ScoreEditableMetadata`
- `MuseReaderAppModel.saveMetadata(...)` targets the internal library copy when available and only falls back to coordinated external writes for legacy paths
- `LiveScoreRenderSession` forwards `updateMetadata(...)` then `save()`
- the bridge maps Foundation strings to the C++ `ScoreMetadata` struct
- `ScoreRenderSession` updates MuseScore meta tags plus visible title-page text items, relayouts the score, saves back to disk, and returns control to Swift
- the app model reopens the same canonical document URL into a fresh `ScoreSession` and refreshes the library index

### Notation Editing Path

- `ScoreReaderView` renders the current page through `ZoomableImageView`
- the overlay reports normalized tap coordinates back to `ScoreReaderState`
- `ScoreReaderState` decides whether the tap means selection or note entry based on `editingState.noteInputEnabled`
- `LiveScoreRenderSession` forwards the request through the bridge
- `ScoreRenderSession` performs page hit-testing or standard-staff note insertion, mutates the MuseScore score, and returns a fresh `ScoreEditState`
- Swift updates the edit strip and selection overlay from that returned state
- Swift presents the editing state through a floating rail for durable actions and a contextual bottom keyboard deck for pitch operations on the selected note
- in note-input mode, Swift stores a pending pitch from the bottom keyboard, uses it for the first staff tap, then sends later keyboard taps to `insertPitchAtCursor(...)`
- duration changes in note-input mode update MuseScore's input duration only; selected-note duration mutation is reserved for normal selection mode
- score mutations invalidate cached rendered pages plus cached playback MIDI/measure-follow data so playback stays in sync after edits

Broader editing should continue to follow this pattern rather than introducing a second notation model on the Swift side.
