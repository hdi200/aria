# Progress

## Current Status

MuseReader is in a working reader prototype stage with a real session-based rendering path on iPad, a working playback path, a first save-backed metadata feature, a first narrow notation-editing slice, and a new app-owned internal library model. The project is beyond static package inspection and beyond eager “render everything now” behavior.

## What Works

- importing `.mscz` and `.mscx` from Files
- copying imported `.mscz` and `.mscx` into `Application Support/MuseReaderLibrary`
- reopening imported scores from an app-owned library index
- one-time migration of legacy bookmark-backed entries when they are reopened
- security-scoped file access handling
- package inspection for `.mscz`
- extraction of root score XML, package entries, thumbnails, and preview assets
- metadata parsing for title, subtitle, composer, lyricist, arranger, MuseScore version, and part count
- opening a live MuseScore-backed score session
- on-demand page rendering from that live session
- full-screen reader UI with lazy page loading/caching
- refreshed iPad-native library/dashboard presentation into a Maestro-like white/indigo/pastel shell with a connected split layout and score-card grid
- opening a score directly from a library card into the full-screen reader without snapping back to the older detail pane
- card-level info popovers for quick metadata such as composer, format, import date, library storage, and MuseScore version
- library score cards showing real embedded preview images when the score package provides them
- library preview cards switching to a full-card first-page preview treatment when a real preview image exists
- refreshed score detail presentation with a hero cover and horizontal preview strip
- refreshed page-based reader chrome with top navigation and floating zoom controls
- exporting MIDI from the live score session for playback
- compact in-reader playback controls with play, pause, stop, and progress state
- native MIDI playback on iPad through `AVAudioEngine` + `AVAudioSequencer`
- exporting the generated playback `.mid` file from the score detail screen through the native iOS share sheet
- successful `iphoneos` arm64 builds producing a real app binary
- verification that exported playback MIDI from a real score plays correctly outside the app
- bundling `MuseScore_General.sf2` into the iOS app so the playback layer has a compatible SoundFont 2 bank
- switching playback over to `AVAudioEngine` with Apple’s `MIDISynth` music device instead of the temporary default `MusicSequence` graph
- exporting repeat-aware playback measure regions from the live MuseScore score session
- active-bar highlighting inside the page reader while playback is running or paused
- auto-following playback to the active page during playback
- tighter score-follow timing through faster playback polling and a small output-latency compensation offset
- editing score metadata from the native detail screen
- saving edited title/subtitle/composer/arranger/lyricist back to the original `.mscz` or `.mscx`
- reopening the saved score into a fresh `ScoreSession` after save
- refreshing recents after metadata save so the library reflects updated score info
- coordinating iOS file writes through `NSFileCoordinator` before the live render session saves the score back to disk
- persisting the library index as JSON under `Application Support` instead of `UserDefaults`
- tapping a rendered note/rest to select it in the reader
- showing a live selection rectangle over the selected score element in the reader
- toggling note-input mode from the reader
- changing note duration from the reader
- changing duration while note-input mode is active now changes the next entered note/rest instead of editing the last inserted note
- toggling rest-entry mode from the reader
- inserting notes on standard staves by tapping the rendered page while note-input mode is active
- deleting the selected note/rest from the reader
- moving the selected pitch up or down chromatically from the reader
- undoing and redoing notation edits from the reader
- saving notation edits back to the imported canonical score copy from the reader
- presenting those notation controls through a floating left rail plus a contextual bottom editor deck instead of a temporary debug-style control strip
- presenting duration, rest, delete, undo/redo, and save through a floating left rail while using a bottom keyboard-style deck for selected-note pitch changes
- presenting cursor mode and note-input mode as separate top rail buttons instead of one mode toggle
- retuning the selected note from a keyboard-style bottom panel through semitone shift, octave shift, and target pitch-class actions routed back into the MuseScore core
- retuning the selected note from the bottom keyboard through an exact pitch-change command instead of only relative pitch nudges
- continuous note entry from the bottom keyboard after the first staff tap establishes the MuseScore input cursor
- editing scores inside a full-screen vertical page stack so page turns now come from scrolling rather than a swipe-snapped page container
- simplifying the reader chrome down to a floating library button and a floating play/pause button instead of the old top header and bottom playback strip
- keeping stale live-rendered pages visible after edits while refreshed renders are generated, so score mutations no longer force the full loading placeholder back over the page

## What Is In Progress

- real-device playback validation, especially timing, synth behavior, and measure-follow alignment on iPad
- real-device validation of metadata save-back for both `.mscz` and `.mscx`
- real-device reader validation for larger and more varied scores
- validating the first notation-editing slice on real iPad hardware
- validating whether the new bottom keyboard feels intuitive enough for selected-note editing on iPad
- validating the new full-screen scroll editor feel on iPad, especially overlay spacing and page-turn ergonomics
- validating whether the stripped-down floating playback control is enough without bringing back heavier reader chrome
- tuning the new library/detail presentation based on device feel
- validating the new `AVAudioEngine` + `MIDISynth` + `MuseScore_General.sf2` path on real hardware
- checking whether Apple’s `MIDISynth` handles the MuseScore GM bank and exported program changes well enough for real scores
- confirming that playback repeats/page changes and the new measure overlay stay synchronized across representative scores
- validating the new internal-library import and reopen flow on real hardware

## What Is Not Built Yet

- advanced playback features such as scrubbing, tempo controls, or a full transport bar
- notation editing beyond the current narrow note/rest workflow
- full keyboard-driven note entry beyond the current standard-staff continuous entry path, including richer accidentals, voices, tuplets, and chord-entry controls
- explicit part/excerpt selection
- production-level performance tuning for very large scores
- formal tests around the new session-based rendering path

## Known Issues / Risks

- simulator support is constrained by the available Qt iOS setup
- build output depends on `/tmp` render-core artifacts, so cleanup can remove generated pieces
- the project still needs more runtime validation on real hardware
- playback currently depends on MIDI export plus Apple’s `MIDISynth` music device, so playback fidelity and instrument mapping may still differ from desktop MuseScore
- the exported MIDI is valid, so current silent playback points to the app's native synth/bank configuration rather than score export
- the app bundle now includes both `MS Basic.sf3` and `MuseScore_General.sf2`, but only the `.sf2` bank is used by the current playback path
- the new playback path still needs real-device validation to confirm that Apple’s `MIDISynth` accepts the bundled `.sf2` bank and produces audio reliably
- measure-following accuracy depends on how well the exported MuseScore measure timeline lines up with the native playback clock on device
- metadata editing currently targets score info only; it does not yet manage arbitrary title-frame cleanup or broader score properties
- note-entry/editing is currently limited to standard staves; drum, tab, and broader element editing are still deferred
- selection and note hit-testing now work through raw engraving/page geometry, so touch tuning on real iPad hardware still matters
- continuous bottom-keyboard note entry is currently standard-staff only and still needs device validation for cursor advancement, pitch spelling, and rest entry
- playback follow currently scrolls pages automatically only while playback is active; manual page browsing is now just native scrolling
- `.mscx` directory save-back has compiled successfully but still needs explicit device validation against real Files-provider scenarios
- the new coordinated `.mscz` save path has built successfully but still needs on-device confirmation against Files-provider URLs
- legacy bookmark-backed entries are only migrated once they are reopened; there is no bulk migration job yet
- licensing/distribution questions remain for eventual App Store plans

## Decision Evolution

- Initial direction: prove native file inspection and preview handling.
- Next direction: integrate the reusable MuseScore render core.
- Recent shift: replace eager full-document rendering with a persistent live session.
- Latest shift: use exported MIDI plus a native `AVAudioEngine` playback path with a bundled MuseScore `.sf2` bank rather than forcing MuseScore's desktop playback runtime into the iPad build.
- Current direction: validate the new internal-library model plus the first note/rest editing slice on device, with the editor now using a left-rail plus bottom-keyboard layout inside a full-screen scroll reader, then expand editing incrementally on top of the same live session boundary while continuing to harden playback and reader behavior.
