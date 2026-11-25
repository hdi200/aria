# MuseReader iOS Feature Requests and Bugs

This file is the shared backlog for feature ideas and known bugs specific to the MuseReader iOS app.
i em
## How to add an item

Add a row to the appropriate backlog with a short title and enough context to understand the user need or failure. Use the next available `IOS-###` identifier for a feature request and `BUG-###` for a bug.

Statuses:

- `Proposed` — captured for review
- `Investigating` — reported and being verified
- `Planned` — accepted for a future release
- `In progress` — currently being implemented
- `Done` — released or otherwise completed
- `Declined` — not currently planned; explain why in Notes

Priorities:

- `High` — important or time-sensitive
- `Medium` — valuable, but not urgent
- `Low` — useful enhancement

## Feature requests

| ID | Feature request | User need | Priority | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| IOS-001 | Global score transposition | Change the key of a song and transpose the entire score in one action. | High | Done | Available from More; notes, chord symbols, the initial key, and later key changes are transposed. |
| IOS-002 | Temporary transpose in View mode | Quickly view a score in another key without entering Edit mode or changing the underlying file. | High | Done | Uses a temporary presentation copy; PDF, image, and print sharing reflect that view while editable exports retain the original score. |
| IOS-003 | Preview a chord by tapping it | Hear whether a chord sounds correct without starting score playback. | Medium | Done | Tapping an existing chord symbol in Edit mode previews MuseScore's realized pitches. |
| IOS-004 | Reposition supported score elements by dragging | Directly reposition commonly adjusted text and markings instead of having them locked in place. | Medium | Done | First phase: text, dynamics/expressions, tempo, markers/jumps/rehearsal marks, and chord symbols. |
| IOS-005 | Import multiple files at once | Bring several score files into ARIA in a single import operation. | High | Done | The document picker allows multiple selection on iOS and Android; the Choose Scores review imports the selected files together. |
| IOS-006 | Duplicate scores | Copy a score to try changes or keep versions. | Medium | In progress | Duplicate is in the library's hold-down menu and makes an exact copy (same title; the music is untouched). Rename was dropped: Edit Info already changes the title. |
| IOS-007 | Add Fine | Mark where a D.C./D.S. al Fine ending stops. | Medium | Proposed | Fine is missing from the markers/jumps that can be added. A note also said "Vom", meaning not yet confirmed. |
| IOS-008 | Style text | Change how text looks (font, size, bold/italic), for example a tempo description like "Allegro". | Medium | Proposed | For tempo text, staff, system and score text. |
| IOS-009 | Multimeasure rests on/off | Show long rests as one multimeasure rest, as in parts. | Medium | Proposed | A toggle for the score/part's multimeasure rest setting. |
| IOS-010 | More note-entry durations and options | Enter faster notes and less common durations without leaving note entry. | Medium | In progress | An up arrow at the right end of the note-entry toolbar opens a row with 32nd and 64th notes, double dot, a Beam menu, acciaccatura, appoggiatura, trill, mordent, turn, arpeggio, a Tremolo menu, double flat and double sharp. Full width on iPad, a scrolling strip on phones; stays open until closed. Keys 2 and 1 enter 32nd and 64th notes. Tested on iPad, iPhone and the Android phone emulator; not yet on a device or Android tablet. |
| IOS-011 | Metronome tempo in View mode | Change the playback tempo without entering Edit mode. | Medium | In progress | From the metronome button in View mode; doesn't change the score. Covered by the practice speed in the Playback & Practice panel (IOS-030), which works in View mode. |
| IOS-012 | Fingering entry under Text | Add or remove finger numbers beside individual notes with large touch controls. | Medium | Done | Text > Fingering opens 1–5 and remove keys, keeping the score tappable. Digits auto-advance; Remove erases the current fingering and selects the previous note, skipping rests. Native note attachments support replacement, Undo/Redo and linked parts. Fingerings can now be dragged using MuseScore offsets while retaining the same parent note; a guide shows that fixed attachment. Native attachment/save/reopen and desktop compatibility checks pass; iPhone/iPad touch drag/Undo pass. Medium iPhone 17 Pro outline passes explicit fingering-selection, touch drag and Undo checks; tablet outline unchanged. Android drag and expanded Duo checks remain pending after the owner prioritized the iPhone preview. Android entry panels pass phone/tablet runtime checks. |
| IOS-013 | Chord builder in the Text deck | Build chord symbols with touch buttons while keeping the score visible, and prefill existing symbols when navigating. | Medium | Done | Text > Chord Text uses roots, qualities, extensions and alteration buttons with Done and Previous/Next, replacing the chord keyboard for this flow. Changed drafts commit before navigating; existing symbols prefill in both directions. Swift and composition checks pass; regular iPad touch checks verified prefill and Done. Done now returns to Text on both phone and tablet decks; Lyrics uses the same destination. |
| IOS-014 | Tempo editor with optional tempo text | Enter a readable marking such as Allegro followed by a metronome tempo that remains playable and desktop-compatible. | Medium | Done | Large beat/BPM preview, optional text, beat-unit buttons and number pad. Stores a native MuseScore TempoText with escaped description before the equation, Follow Text and real playback speed. iPad entry, reopening/prefill and Undo verified. Shared with Android; both builds, native and desktop compatibility checks pass. Android phone/tablet tempo text entry passes keyboard visibility/input checks and screenshot review after fixing fixed-height sheet placement above the keyboard. |
| IOS-015 | Note and chord editing usability pass | Selection, tool switching, note replacement and harmonic chord entry work as one predictable editing experience. | High | Proposed | From the November 9, 2026 master backlog (item 10). Umbrella for BUG-006 to BUG-009 and BUG-014; do after those are fixed. |
| IOS-016 | Consecutive identical time signatures | Add the same time signature twice in a row (4/4 then another 4/4). | Medium | Built, untested | Master backlog item 11. The sheet required a different value; desktop allows both, and the engine (cmdAddTimeSig) ignores only an identical one on the same bar. Test in TO_TEST.md. |
| IOS-017 | Tie three-dot menu | Copy, Select Similar and other actions on a selected tie. | Medium | Proposed | Master backlog item 12. |
| IOS-018 | Reset beams | Restore default (automatic) beaming in one action. | Medium | Proposed | Master backlog item 13. Related: the Beam menu in IOS-010. |
| IOS-019 | Double barline at system start | Show a double barline at the start of a system where appropriate. | Low | Proposed | Master backlog item 14. Needs investigation: check how desktop MuseScore 4.7 handles it. |
| IOS-020 | Keyboard-based note entry | Faster note entry from an external keyboard or keyboard-style controls. | Medium | Proposed | Master backlog item 15. Exploratory. |
| IOS-021 | Chord-symbol entry with a text field | A keyboard for chord entry while keeping a text field at the top for typing chord names. | Medium | Proposed | Master backlog item 16. Builds on IOS-013 and the plain typing keyboard (IOS_CHANGES #88). |
| IOS-022 | More chord-symbol formats | Enter add4, sus2, sus4 and optional parentheses. | Medium | Proposed | Master backlog item 17. Chord Entry has "sus" and "add" keys; check that sus2/sus4/add4 and parentheses parse and render as on desktop. |
| IOS-023 | Diminished major seventh chords | E°(maj7) and equivalent spellings are recognized, formatted and played correctly. | Medium | Proposed | Master backlog item 18. |
| IOS-024 | Easier lyric re-entry | Return to existing lyrics and continue entry predictably. | Medium | Proposed | Master backlog item 19. See also BUG-011. |
| IOS-025 | Lyric auto-capitalization | No unwanted capitalization while entering lyrics. | Medium | Proposed | Master backlog item 20. Review whether the keyboard's auto-capitalization should be off for lyrics. |
| IOS-026 | Chord-style lyric workflow | Enter lyrics like chord symbols, with simple navigation between notes and syllables. | Medium | Proposed | Master backlog item 21. Exploratory; builds on IOS-013. |
| IOS-027 | Dotted half-note tempo unit | Use a dotted half note as the beat unit in tempo markings. | Medium | Proposed | Master backlog item 22. Beat units today: quarter, eighth, half, dotted quarter (`TempoBeatUnit`). |
| IOS-028 | Triplet tempo units | Use triplet-based beat units or rhythmic relationships in tempo markings. | Low | Proposed | Master backlog item 23. |
| IOS-029 | Dot and triplet tempo modifiers | Apply dot and triplet as modifiers to a tempo note value instead of separate options. | Low | Proposed | Master backlog item 24. Would cover IOS-027 and IOS-028. |
| IOS-030 | Practice playback speed | Play at 25% to 200% with an easy reset to 100%, without changing the score. | High | In progress | Master backlog item 25. Overlaps IOS-011; see IOS-031 to IOS-033. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. 25-150% with presets; Verified on the iPad simulator and Android tablet emulator. At 50%, Widmung's playback duration went from 2:14 to 4:29. |
| IOS-031 | Speed keeps tempo changes and pitch | A practice speed scales every tempo change in the piece and doesn't change pitch. | High | In progress | Master backlog item 26. Part of IOS-030. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. Native playback tests preserve the pitches and scale both 120 BPM and 60 BPM passages at 50% and 150%. |
| IOS-032 | Practice speed per score | Each score remembers its own practice speed. | Medium | In progress | Master backlog item 27. Not saved in the score file, so desktop compatibility is unaffected. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. 50% persisted across relaunch on the iPad and iPhone simulators and both Android emulators. |
| IOS-033 | Practice speed with loop, metronome, count-in | Looping, the metronome and count-in follow the practice speed. | High | In progress | Master backlog item 28. Part of IOS-030. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. On the Android tablet, bars 3–4 still looped after changing from 70% to 50% and pressing Play again. Native tests verified the two-bar click sequence at 50%, including a pickup. Metronome cadence still needs a listening check. |
| IOS-034 | Metronome and playback settings page | A discoverable settings page instead of tap-to-toggle and hold-for-options, with relative tempo (e.g. 70%) and clear metronome controls. | Medium | In progress | Master backlog item 29. Overlaps IOS-011 and IOS-030. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. Replaces tap-to-toggle / hold-for-options. Not yet: relative tempo beyond the speed control, accent first beat. |
| IOS-035 | Tempo ramp practice | Optionally raise or otherwise change the playback speed step by step while practicing. | Low | In progress | Master backlog item 30. Depends on IOS-030. The original one-repeat ramp was verified on iPad and Android emulators (IOS_CHANGES #93). On iPad the 70% → 100% ramp reached 100% on loop 7 and End ramp restored the previous speed. Android tablet playback logs show count-in only before the first loop and about 0.26–0.31 seconds between speeds. The sheet now supports a configurable number of repeats and estimates the time to target (IOS_CHANGES #95). Ramp selection is available in View mode. Edit-mode range selection still needs a Tempo Ramp action. |
| IOS-036 | Count-in options | Turn count-in on or off, with a two-bar count-in or a short starting delay. | Medium | In progress | Master backlog item 31. Built November 10, 2026 (IOS_CHANGES #92): Playback & Practice panel from the metronome button. Off / 1 bar / 2 bars. Not yet: a short starting delay. |
| IOS-037 | Smooth playback following | Score following and auto-scroll stay smooth, especially at the bottom system. | Medium | Done | Master backlog item 32. Likely shares a cause with BUG-009 and BUG-010. Checked November 10, 2026: View mode (page turn) follows playback and turns pages cleanly. In Edit mode on the iPad, following never scrolls to the playing bar: the list stays put until the page changes, then jumps to the page top, so a page's lower systems play behind the edit panel. The same happens on the committed build, so it predates the November 10 fixes. Not fixed yet. Fixed November 10, 2026: while editing, playback is followed inside the page view so the playing bar stays in the free area above the edit panel (iOS `followPlaybackAbovePanel`, also sideways when zoomed on phones; Android scrolls the page list with an anchored scrollTo). Verified on the iPad simulator (page 1 and page 2 lower systems, last system), the iPhone 17 Pro simulator (vertical and sideways) and the Android tablet emulator (Widmung, both pages). Verified on the Android phone emulator in portrait: playback followed into Wiegenlied's final system and kept the playing bar above the panel. Entering Edit locks phones to portrait, so the landscape Edit scenario cannot run with the current orientation policy. |
| IOS-038 | Playback keyboard doesn't cover the score | The on-screen piano keyboard never hides the last measure or other content during playback. | Medium | Done | Master backlog item 33. Related to BUG-010 and BUG-002. Same root as IOS-037: in Edit mode the playing bar on a page's lower systems stays behind the edit panel and keyboard (iPad, November 10, 2026). Not fixed yet. Fixed with IOS-037 (November 10, 2026): the playing bar no longer plays behind the edit panel or keyboard. Same devices as IOS-037. |
| IOS-039 | Tap a note to hear it | Hear a note's pitch by tapping it, without starting playback. | Medium | Proposed | Master backlog item 34. Chord symbols already preview (IOS-003); check what tapping a note does today in View and Edit mode. |
| IOS-040 | Jazz font and Style menu | A jazz notation font and possibly a Style menu for the score's look. | Low | Proposed | Master backlog item 35. Related to IOS-008. Must save as MuseScore 4.70 style settings so desktop shows the same font. |
| IOS-041 | Scan printed sheet music | Turn a photo, camera scan or PDF of printed music into an editable score. | High | In progress | November 15, 2026 (IOS_CHANGES #105–106). ScannerCore 0.1.4 (IOS_CHANGES #107) reads notes, chord names, the printed title, composer, tempo, rehearsal marks, navigation and staff text offline on every supported iOS version; printed D.S./D.C., To Coda and Fine play as jumps when their segno and coda were found (engine patch: upstream #33802). The normal scan-and-import flow passed on all 20 benchmark pages and a chordless piano page in the iPhone 17 Pro simulator. Physical iPhone and paywall tests are pending. PDFs and pictures shared to Aria, opened in it or dropped on the library are scanned (IOS_CHANGES #108). ScannerCore 0.1.5–0.1.9 (IOS_CHANGES #109–113): 1st/2nd endings play in printed order ("1.2."/"3." endings not supported); plain treble clefs no longer read as octave-down and italic chord names no longer as "pp"; printed part names and short names are read and give each part its instrument (transposed only when the key is printed); stemless slash bars come out as silent slash notation (stemmed and half-note slashes not yet). Lyrics are read and put on their notes (0.1.9); a long instruction sentence under notes can still come through as lyrics. Each was checked in the simulator (Smiles, a generated string quartet and wind quintet) and with desktop MuseScore 4.7.6; slash bars on a MuseScore lead sheet and the benchmark pages. Not yet tested on a phone or on real photos of ensemble scores. Scan in the library reserves a slot, reads a camera scan, photo, or PDF/image from Files and imports the MusicXML as an editable .mscz that opens in View mode. Android port tracked in FEATURES_TODO.md. First-scan notice wording refreshed November 17 (IOS_CHANGES #119); removed the first-scan caption and changed iPhone presentation to measured content height. Simulator sizing check pending. ScannerCore pinned to 0.1.19 with visible gap rests and GPL/source notices (IOS_CHANGES #120); all 157 scanner unit tests pass. Source publication and device release checks remain gates. November 19 (IOS_CHANGES #132): a small outlined BETA capsule now overlays the shared Scan button; native SwiftUI phone/tablet component previews and syntax checks pass. The requested Release iPhone build passed, was installed over the existing app and launched; interactive badge/menu/VoiceOver review remains pending. Follow-up #133 moves the badge outside the native menu label after the owner observed temporary clipping during menu dismissal; the updated phone build was installed for retesting (relaunch blocked by the locked phone). |
| IOS-042 | Voice picker on phones | Choose voices 1–4 from the expanded note-entry tools on iPhone and Android phones. | Medium | Done | More Notes starts with a V1 dropdown using the existing engine action. Verified November 17 on the iPhone 17 Pro simulator and Pixel 10 Pro emulator. All four menu choices and current-voice checkmark displayed. Voices 2, 3 and 4 changed the selected note through the engine, and Undo restored Voice 1 after each change. Swift typecheck and iOS/Android builds passed. |
| IOS-043 | Select frames and put page breaks on them | Start the music on a new page after an intro text frame, in the full score and in each part, without desktop MuseScore. | Medium | Proposed | From a November 2026 support request: a score with an intro text page and a page break before the music. Each part showed the music on the intro page. Desktop MuseScore does the same, because building a part drops page and system breaks (only section breaks are copied, `excerpt.cpp` `cloneMeasure`). The desktop fix is to select the frame in each part and add a page break. Aria can't do that: tapping a bar puts the break after that bar, and vertical and text frames aren't selectable. Plan: add VBox/TBox to `isDirectlySelectable` and `pageForItem` (HBox is already there), make Add/Remove Layout Break use a selected frame instead of `activeMeasure`, and report a frame selection type through both bridges. Then add a small frame toolbar (Page Break, System Break, maybe Delete), checked on phone, iPad and Duo. No engine patch needed: `Score::cmdToggleLayoutBreak` already handles selected frames, and the saved file matches desktop. Needs a native test and the compatibility checks. Related, not in scope: parts also drop frame images (an image read from a file gets track 0 and is skipped in parts without that staff) and reset frame height, margins and auto size, except `copyValues` on the first title frame (auto size not copied). Desktop behaves the same; editing frame height in Aria could be a later item. |
| IOS-044 | Stand-in fonts for desktop fonts | Scores set in desktop fonts the phone lacks (Arial Black, Calibri, Arial on Android) should keep their look and line breaks. | High | In progress | November 25, 2026 (IOS_CHANGES #136): the render core bundles Liberation Sans/Serif/Mono, Carlito, Caladea and Archivo Black (SIL OFL 1.1) and substitutes them only when the named font is missing; saved files keep the original font name. Native tests pass. Licensing the real fonts was rejected: Monotype app licenses run about $1,000+ per style per year. Later option: let users add their own font files. Render core rebuild for iOS/Android and device checks pending. |

## Request details

Use this section when a request needs more detail than fits in the table.

### IOS-001 — Global score transposition

**Problem**

Changing the key currently requires more work than users expect. They want one action that transposes the full score rather than changing elements individually.

**Proposed outcome**

Add a global Transpose action, suggested for the More menu, that changes the key and transposes the whole score.

**Acceptance criteria**

- The user can choose a destination key or transposition interval.
- Notes, key signatures, and chord symbols are transposed consistently.
- The change is applied to the editable score and can be undone.

**References**

- Original feedback (Portuguese): “Falta uma opção de mudar o tom da música, e ele já transpor tudo.”
- A second user independently requested global transpose in the More menu.

**Implementation note**

The permanent transpose path also transposes key-signature changes later in the score, not only the opening key.

### IOS-002 — Temporary transpose in View mode

**Problem**

A user may need to read a score in a different key during rehearsal or performance, but entering Edit mode and modifying the file is too disruptive.

**Proposed outcome**

Add a quick Transpose control in View mode. It should change the displayed key temporarily while leaving the original score file untouched.

**Acceptance criteria**

- Transpose is accessible without entering Edit mode.
- The user can choose a destination key or transposition interval.
- The displayed notation and chord symbols stay consistent with each other.
- The original score remains unchanged.
- The user can quickly return to the score's original key.

**References**

- Requested specifically as a view-only alternative to global, file-changing transpose.

**Implementation note**

View mode renders and plays a temporary transposed score while saving continues to use the original editable score. The key selector identifies the source key as “Original Key.” PDF, PNG, and printing share the displayed transposed presentation in View mode; MuseScore, MusicXML, MIDI, and audio exports continue using the underlying score.

### IOS-003 — Preview a chord by tapping it

**Problem**

Users want to verify a chord by ear without starting playback for the entire score.

**Proposed outcome**

When a user taps a chord, provide a way to play a short audio preview of that chord.

**Acceptance criteria**

- A chord can be previewed without starting normal score playback.
- The preview uses the pitches represented by the selected chord.
- Previewing one chord does not unexpectedly change the score.
- Starting score playback stops any active chord preview first.

**References**

- Original feedback (Portuguese): “Ao clicar nos acordes eles poderiam tocar pra gente ouvir se o acorde está certo sem precisar dar play na música.”

**Implementation note**

Chord preview is available when selecting an existing chord symbol in Edit mode. It uses MuseScore's realized harmony notes and the owning instrument's playback setup; View-mode taps retain their navigation behavior.

### IOS-004 — Reposition supported score elements by dragging

**Problem**

Users feel constrained when layout items are fixed in place.

**Proposed outcome**

Allow a sensible first group of movable score elements to be repositioned directly with drag gestures:

- Regular text, staff text, and system text
- Dynamics and expressions
- Tempo markings
- Markers, jumps, and rehearsal marks, including Coda, Segno, D.S., and D.C.
- Chord symbols

**Acceptance criteria**

- The listed item types can be moved with a direct drag gesture in Edit mode.
- New positions are saved with the score when appropriate.
- The engine determines whether the selected element is movable before enabling the gesture.
- Dragging refreshes the affected score area and preserves the selection.

**References**

- Original feedback (Portuguese): “Outra coisa seria poder arrastar os itens dos layout, que nada ficasse preso.”
- This first phase deliberately excludes notes, lyrics, and spanners, which need interaction rules of their own.

### IOS-005 — Import multiple files at once

**Problem**

Importing score files individually is slow when a user wants to add a collection to ARIA.

**Proposed outcome**

Allow the document picker and share/import flow to accept multiple compatible files in one operation.

**Acceptance criteria**

- The user can select multiple supported score files at once.
- ARIA imports every valid selected file and reports any file that fails.
- One failed file does not prevent the remaining valid files from importing.
- Imported files appear in the library without requiring the flow to be repeated for each file.

**References**

- Original feedback (Portuguese): “E o mais importante, que desse pra enviar vários arquivos de uma só vez para dentro do ARIA.”

## Bugs

| ID | Bug | User-visible failure | Priority | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| BUG-001 | Add Instruments actions move off-screen | With seven or more selected instruments, the sheet can overflow vertically; at nine, Cancel and Add Instruments may become unreachable. | High | Done | The iPad selected/in-score column now scrolls inside the fixed-height sheet, leaving the action header fixed. |
| BUG-002 | Edit panel covers the last page's bottom system on iPad | On iPad, the edit keyboard and toolbar panel sometimes covers the bottom system of the last page, in any score (1-page scores too), and it can't be scrolled into view. | Medium | Done | iOS only. Corrected November 9, 2026: it's the bottom system (not bar) of whichever page is last, not only in 2-page scores. Likely the same bug as BUG-010. Reproduced November 9, 2026; steps and cause in BUG-009. Earlier attempt, before that correction: not reproduced November 2, 2026 on the iPad Pro 13" simulator (portrait, 1- and 2-page scores, with and without More open, a bar selected near the bottom): the page list always scrolled the last bar above the panel. Needs the exact steps. |
| BUG-003 | Segno drawn too small | A segno looked smaller than expected. | Low | Not reproduced | Checked November 2, 2026: a segno in an opened score draws at exactly the same size as in MuseScore 4.7.5. A segno just added in Aria was not checked separately. |
| BUG-004 | Highlighter strokes change shape after editing | On iOS, after editing and going back, highlighter strokes can change shape or break into dots; reopening the score shows them normally. | Medium | Done | Strokes hang from per-measure rects. After an edit those were refetched in Edit mode and View mode kept them (only an empty list was refetched). Leaving Edit now refetches them for View mode. Not yet verified on a device. Safety net still to do: keep one gesture's pieces together. Verified November 10, 2026 on the iPad simulator: a highlighter stroke across bars 6-8 of Widmung kept its shape after changing a note in bar 6 and returning to View mode. |
| BUG-005 | Fingering locks editing after the last note | Entering a fingering on the last note before empty bars leaves the keys and editing controls disabled. | High | Done | Rest skipping now compares stable navigation position rather than volatile render data. Production-action regression fails before and passes after. iPhone 17 Pro UI entry (1/2/3/5), last-note replacement, deck exit and Undo all pass; test edits were removed. iOS typecheck/build and Android debug build pass. |
| BUG-006 | Note entry unpredictable after selecting a note | After selecting an existing note, changing pitch or duration or switching tools can unexpectedly affect other editing states. | High | Not reproduced | From the November 9, 2026 master backlog (item 1). Needs exact steps. Checked November 10, 2026 on the iPad simulator after the chord fixes: selecting a note, changing its value, raising its pitch, switching to Text and back, and Undo each changed only what was asked; selection, value and tool stayed consistent. Undo/Redo keep note input (native test). Reopen with exact steps if it recurs. |
| BUG-007 | Chord tool turns off when selecting another note | With a note selected, turning on harmonic chord entry and then selecting another note sometimes turns the tool off and changes the note instead. | High | Done | Master backlog item 2. The tool should stay on. Fixed November 10, 2026 (IOS_CHANGES #90): chord mode chosen with the Chord button stays on across selections. Verified on the Android tablet emulator (key added as a chord, Undo restores). Also verified November 10 on the iPhone 17 Pro simulator and the Android phone emulator, after a second fix: a key now adds to the selected note instead of replacing it (native test "chord mode adds to the selected note"). Verified on the iPad simulator with Fingering Placement QA. Chord stayed selected after tapping another note and the next key added a pitch. |
| BUG-008 | Note value changes during chord editing | Editing a selected note, or using harmonic chord entry, can change the note value shown in the duration selector. | High | Done | Master backlog item 3. Possibly the same cause as BUG-007. Fixed November 10, 2026: adding to a selected note's chord started note input with the toolbar's earlier value, so the selector showed a different value than the chord (a whole note showed a quarter). The pitch key now starts note input with the selected chord's own value (`handleKeyboardPitch`). Native test "adding to a chord keeps the note value"; verified on the iPad simulator (a half note stays half, selector stays on half). On the Android tablet emulator, adding a pitch to Widmung bar 3 kept the half-note selector and the existing half note. |
| BUG-009 | Bottom system recenters or snaps back | Selecting or editing the bottom system of a page sometimes jumps toward the top or snaps back, especially on the last page. | High | Done | Master backlog item 4. Reproduced November 9, 2026 on the iPad Pro 13" simulator (Wiegenlied, 1 page; Ave Maria, page 1 of 2): select a bar in a page's last system, tap Note Entry (the bar lifts above the panel), then tap Select, or Undo when it turns note input off. The page jumps back to its top and the bar is hidden under the panel. Cause: the extra scroll room that lifts the bar exists only while note-entry focus is on (`updateActiveNotationContentInsets` in `ZoomableImageView.swift`); turning focus off removes it and clamps the offset. In Select mode the reader also scrolls to the page, not the selected bar (`activeNotationFocusIsActive`). Same root as BUG-002 and BUG-010. Fix written November 9, 2026 (IOS_CHANGES #89): any Edit-mode selection keeps the room, and Select-mode taps nudge a hidden bar into view. iOS typecheck passes. Verified on the iPad Pro 13" simulator (Release build): Note Entry then Select and note entry then Undo keep the bar in place on Wiegenlied (1 page) and Ave Maria page 2 (last page); a Select tap on a half-hidden bar scrolls it just clear of the panel; a tap on a visible bar doesn't move the page. iPhone not checked. Android (Medium_Tablet emulator, landscape, debug build, November 9, 2026; Widmung, last page) also has it, differently: with nothing selected the furthest scroll leaves the last system's bottom staff under the panel; the first Note Entry on a bar there sent the page far past it (bar off the top of the screen, only the footer showing); Select then left it there (no snap-back); dragging down recovered it. A second Note Entry from a visible bar was fine. Android cause: `AndroidZoomableImageView.scrollToActiveNotation` places the bar as if the page's top were at the top of the screen; iOS also moves the page list to make that true, but Skip ignores the scroll anchor, so on Android the result depends on where the page is (fine with the page top on screen, far off when it is scrolled up). Android fix not written yet. Android: see BUG-010. |
| BUG-010 | Keyboard covers the final system | The last system can't always be scrolled above the editing keyboard; the last page behaves differently from the others. | High | Done | Master backlog item 5. Reproduced November 9, 2026; cause in BUG-009. Likely the same bug as BUG-002 (the last page's bottom system, in any score length) and the same cause as BUG-009. Android fixed November 10, 2026 (#90): last system and footer scroll clear of the panel; Note Entry then Select keeps the bar in view on the tablet emulator. Also verified on the iPhone 17 Pro simulator and the Android phone emulator (last system clears the panel; Note Entry then Select keeps it in view). |
| BUG-011 | Lyrics spacing and recentering on page 1's last system | Entering or re-entering lyrics on the final system of page 1 gives strange spacing and recentering. | High | Done | Master backlog item 6. Check whether it shares a cause with BUG-009. Fixed November 10, 2026: entering Lyrics zooms to 1.7x, and both the page list and the page's own view scrolled to the bar, moving it twice, so the lyric line was pushed off screen. When zoomed, only the page view places it now (`activeNotationAnchorOffset`), and it follows lyric and chord-symbol selections. Verified on the iPad simulator (Widmung bar 14: the lyric and its staff sit above the lyric box; closing it keeps the system in view). The iPhone still needs a device check. On Android, lyric and chord-symbol follow added, but on the phone emulator opening Lyrics still resets the zoomed page to its top-left (the keyboard rebuilds the page view). Verified the `AndroidZoomableImageView.updateBounds` fix on the Pixel phone emulator (Wiegenlied bar 9) and the tablet emulator (Widmung bars 10 and 5). Opening Lyrics or Chord Text kept the selected system visible. Closing Lyrics on the tablet jumped back to page top (BUG-017). |
| BUG-012 | Landscape page turns unreliable | In landscape, especially single-page mode, tapping outside the page doesn't always turn the page. | High | Done | Master backlog item 7. Fixed November 10, 2026 (#90): View-mode taps in the margin beside the page turn it. Verified both directions on the Android tablet emulator. Reproduced on the iPad simulator with Widmung in landscape. The recognizer attached to the score overlay could not receive touches in the viewport margin. Moved side-margin recognition to the scroll view and verified both directions on iPad. |
| BUG-013 | View Mode key setting resets | Changing the key in View Mode's Edit interface and returning to View Mode resets it. | High | Done | Master backlog item 8. Related to IOS-002 (temporary transpose). Fixed November 10, 2026 (#90): the temporary key is reapplied after Edit. Verified on the iPad simulator and Android phone emulator (Ab kept after Edit → Done). |
| BUG-014 | Chord mode Enter changes to Continue | The chord button changes from Enter to Continue when no chord has been entered. | High | Done | Master backlog item 9. No "Continue" label found in Chord Entry code on November 9, 2026, after the plain typing keyboard (IOS_CHANGES #88); check against the current build and get steps or a screenshot. Checked November 10, 2026: the Chord Entry button always reads "Enter" since the plain typing keyboard (#88). Not reproduced on screen. |
| BUG-015 | Score renamed after editing | After any edit (even one undone), the library shows the score's top heading as its title, e.g. Wiegenlied became "5 Lieder, Op.49", Widmung became "Myrthen, Op.25". | High | Done | Found November 9, 2026 on iPad and Android. The engine read the printed Title text before the Work Title field the library uses. Fixed November 10, 2026 (IOS_CHANGES #90). Verified on the iPad simulator and Android phone emulator (edit, undo, back: still "Wiegenlied"). Round trip unchanged (890/892). |
| BUG-016 | Tempo Ramp misnumbers bars after a pickup | In Wiegenlied, select printed bars 5–8. The range highlights and plays the correct bars, but the sheet says 6–9. | Medium | Done | Reproduced on iPad and Android. The redesigned sheet omits the bar-number banner and shows the target loop and estimated time. |
| BUG-017 | Closing Lyrics jumps back to the page top on Android | On the tablet, open Lyrics at Widmung bar 10 and close the entry panel without typing. The reader jumps to the top. | Medium | Investigating | Also saw a saved empty lyric flagged by Review Score Fixes after this check. Removed the empty lyric from the emulator score using the app's backed-up repair. |
| BUG-018 | Seeking late in a Tempo Ramp can count an extra loop | With a ramp active, seek to the last quarter of the loop. The audio player restarts at the first bar and the ramp can advance. | Medium | Open | Reproduced with the current seek and repeat logic in a focused Swift check. The reader records the requested position while the player lands at the loop start. Verify with the playback scrubber on iPhone Duo. |
| BUG-019 | Android lyrics field loses focus after the first character | On the Pixel 10 Pro emulator, open Wiegenlied, select the voice's half note in bar 11, Text > Lyrics, and type a word. Only the first letter stays and the keyboard closes; later key presses do nothing until the field is tapped again. | High | Open | Found 12 Nov 2026 while filming the promo (adb typing and on-screen key taps both hit it). Field: `MuseReaderAndroid/Aria/Sources/AriaSkip/AndroidTextInputFields.swift` (`ScoreReaderLyricsTextInputField`). Not yet checked by hand on a real phone. Recording: `promo/youtube/capture/discarded/android-lyrics-bug.mp4`. |
| BUG-020 | Third-party stylus leaves Note Entry on staff taps | Explicit Note Entry switches to Select when the stylus reports a normal touch. | High | In progress | Implemented November 17, 2026 (IOS_CHANGES #117): explicit staff entry accepts direct taps; automatic Pencil entry keeps finger selection. Interaction checks, iOS typecheck and repeated direct-touch staff entry on the Release iPad simulator pass. Physical stylus check pending. |
| BUG-021 | Screen auto-lock interrupts playback | iPhone auto-lock dims/locks the score while music is playing (GitHub #9). | High | In progress | Implemented foreground playback/count-in screen-awake ownership shared with video export; request cleanup is covered by policy checks. Real 30-second auto-lock, background and completion checks pending. |
| BUG-022 | Instrument replacement leaves linked parts stale | Changing an instrument updates the full score while an existing part retains the old sound/name. | High | In progress | Reproduced and fixed across master/excerpts with desktop transposition and undoable title changes. Native playback setup, undo/redo, save and reopen pass; device listening pending. |
| BUG-023 | Imported individual parts reuse a grouped excerpt | Five different instruments all show Komp section and the same grouped score (B-01). | High | In progress | Exact synthetic MSCZ reproduction now yields separate individual views. The custom group survives save/reopen. Native regression passes; original user file unavailable and iPad UI check pending. |
| BUG-024 | Instrument drag previews can disagree with score order | Cancelled/outside-row drops can leave a reordered list without an engine edit. | Medium | In progress | Accepted-drop-only commits in both instrument views; stable part IDs survive queued moves. Production drop delegates and native edit sweep pass. iPad drag/save/undo smoke check pending. |
| BUG-025 | Choir-to-flute MSCZ reportedly plays piano | Instrument-change import sometimes uses piano instead of choir/flute. | Medium | Investigating | Standard MSCZ import/part/save/reopen regression passes. A custom/unrecognized instrument ID reproduces the engine's piano fallback despite a choir MIDI program; fixture retained without changing sound selection. Need the reported original score. |
| BUG-026 | Android Choose Photo does nothing | Scan > Choose Photo closes its menu without opening a picker; the file route works. | High | Done | Fixed November 18, 2026: attach the PhotosUI task directly because the shim has no generated Java ViewModifier peer. Exact-AAB test APK on Pixel emulator opens the image-only picker, cancels/reopens, scans Maple Leaf Rag, plays and saves MSCZ. Material camera asset also verified in the first-scan notice. iOS behavior unchanged. |
| BUG-027 | Android scanning beta notice flickers | The first-scan notice repeatedly changes height. | High | Done | Fixed November 18, 2026: mark inner content with popoverPanelScrollContent, matching the metronome/parts panels, instead of measuring the outer viewport. Three matching title/button bounds over 2.48 seconds before dismissal; owner also confirmed the flicker was fixed. iOS typecheck: 0 errors, existing 72 warnings; iOS sizing unchanged. |

| BUG-028 | Invalid tuplets crash headless warning dialog | Add Tuplet can dereference an absent InteractiveProvider. | High | Done | Build23 Play stack reproduced with a 512th-note quintuplet. Missing provider now returns Cancel; rejected tuplets roll back the whole bridge command. Focused tests and full native 10/10 suites pass; all compatibility results unchanged. Android engine rebuilt; earlier iOS IPA is unchanged. |
| BUG-029 | Transposed keyboard replacement can treat a rest as a chord | Low written MIDI pitch on a transposing staff can become the rest sentinel and crash upNote. | High | Done | Written MIDI1 on B-flat staff reproduced the Play upNote+28 fault. Bridge preflights sounding MIDI range; engine checks actual inserted element type and nonempty chord. Regression/control/rollback tests and compatibility comparisons pass. Exact production score is unknown. |
| BUG-030 | Android scan progress sheet jitters | The scanning sheet moves up and down while a scan runs. | High | Done | Fixed November 18, 2026: the sheet measures its own content (`popoverPanelScrollContent`), like the metronome/parts panels and beta notice. Code audit applied the same fix to the pickup, time and key signature editors in phone landscape (not run on a device). Rule recorded in `MuseReaderAndroid/AGENTS.md`. Android 1.3.0 (26). |
| BUG-031 | iOS loop highlighting queues a page turn | Holding a bar near a page edge, dragging to highlight a loop and lifting turns the page before playback. | Medium | Fixed | Implemented November 19, 2026: iOS simultaneous swipe navigation yields while a playback selection is pending, including asynchronous bar loading. Production policy checks and full typecheck pass (0 errors, unchanged 72 warnings). Owner confirmed the fix on iPad November 21; iPhone check remains in TO_TEST.md. |
| BUG-032 | Score fixes misfire and keep coming back | Review Score Fixes offered "Lyric Hyphens" on scores made in desktop MuseScore, and the sheet reappeared every time a score with skipped fixes was opened. | High | In progress | November 25, 2026 (IOS_CHANGES #135): the Lyric Hyphens check is removed (desktop scores have literal hyphens too, from imports, pasted text or older versions; the Aria bug it cleaned up was fixed October 7). Kinds of fixes left unfixed when the sheet closes are remembered per score and not offered again; new kinds still are. iOS typecheck passes; native score-fix tests pass on the host build. Render core rebuild for iOS and Android and device checks pending. |
| BUG-035 | Android import from Samsung My Files does nothing | Galaxy Tab S7 (One UI): Import opens only Samsung's file browser, and after picking an .mscz nothing happens. | High | Fixed | November 25, 2026, Android only. Cause: when the picked document couldn't be read (no read grant from the picking app, a name query the app refuses, a `file://` path), `AriaDocumentPicker.kt` returned an empty result, which the Swift side treats as a cancel, so nothing showed. Picked files named without an extension (file managers label .mscz `application/octet-stream`) also kept no extension, which the import goes by. Fix: Import asks for Android's own picker by name when another app is the default; each failure comes back as an "Import Failed" message; picked files get the same octet-stream/zip check as Open with; Open with shows a toast when it can't read the file. Verified on the Medium_Tablet emulator (Tab S7 screen, debug build): an extensionless octet-stream score imports and opens; with Android's picker turned off, the stand-in file manager `MuseReaderAndroid/scripts/fake-file-manager` showed the no-permission, no-file and no-name cases (errors shown; the no-name file was saved as `12345.mscz`). Open with/Share from that app not run. Needs a check on a real Samsung: whether My Files is the default picker there, and an import from it. |
| BUG-036 | Add/Remove Instruments sheet cut off on Android tablets | While editing on a Galaxy Tab S7, the Add/Remove Instruments sheet doesn't fit on screen and the Remove Instrument controls at the bottom are cut off. | High | Fixed | November 25, 2026 (IOS_CHANGES #138). Reproduced on the Medium_Tablet emulator in landscape with the keyboard up (search field): the tablet sheet keeps a 560 pt minimum height, taller than the space left, so Close/Done went off the top and the list off the bottom (Samsung's taskbar and larger screen zoom take more height still). Portrait, and landscape without the keyboard, fit. On Android the sheet (and the New Score template sheet, same sizing) now never grows taller than the space; the In Score list already scrolls (BUG-001). iOS unchanged. Verified on the emulator: with the keyboard up and 10 instruments, Close/Done and search stay visible, the In Score list scrolls to the last Remove button, and the Remove confirmation is fully on screen and works. Not checked with Samsung's taskbar or keyboard on a real Tab S7. |
| BUG-037 | Android scan camera never starts | On a Galaxy Tab S7, Scan with Camera never opens the camera. | High | Fixed | November 25, 2026, Android only. Aria doesn't use CameraX or the camera permission: the camera is Google Play services' document scanner, which downloads its module on first use and needs current Play services. When it failed or never answered, Aria waited with no time limit. Now, if the scanner fails or hasn't opened within 15 s, Aria opens the device's camera app (`ACTION_IMAGE_CAPTURE`, any camera layout, front-only included, no permission needed) and scans the photo like Choose Photo. Verified on the Medium_Tablet emulator: the normal scanner still opens; with Play services turned off, the camera app opened, and the photo came back and was read. The 15 s time-out path was not triggered. The real cause on the Tab S7 (Play services version, module download) is not confirmed: needs the device. |
| BUG-038 | Android library buttons squeezed in tablet landscape | On Android tablets in landscape, the library header's Scan and Import buttons were squeezed to "Sca" and "Impor" (32 and 48 dp instead of about 101 and 114), with the gaps between buttons gone, while about 335 dp stood empty after the title. | Medium | Fixed | November 25, 2026 (IOS_CHANGES #139), found while checking BUG-035. Present since the labelled Scan/Import buttons (November 13). Cause: iOS keeps the buttons' width with `layoutPriority`, which Skip doesn't support (Aria's shim ignores it); the search field also makes the button group a filling view like the title, so Skip split the row in half between them. Android now lays the controls over the title's trailing edge at their own width, and the title gives way by that width (`onGeometryChange`). iOS unchanged. Verified on the Medium_Tablet emulator in landscape: Scan 101, Import 114 and + 52 dp with 16 dp gaps; Scan's menu and Import's picker open; a long setlist name truncates before the buttons. Portrait was not affected (title on its own row). |

### BUG-001 — Add Instruments actions move off-screen

**Reported behavior**

The Add Instruments window grows downward as instruments are selected. With nine selected instruments, the Cancel and Add Instruments buttons can fall outside the visible frame, and the user cannot scroll back to reach them.

**Root cause**

The iPad sheet placed every selected-instrument row in an unbounded vertical stack inside a fixed-height modal. Unlike the separate iPhone layout, that column did not have its own scrolling behavior.

**Expected behavior**

- Cancel and Add/Done remain visible regardless of the number of selected instruments.
- The iPad selected-instrument column scrolls within the fixed-height modal.
- Users can still remove and reorder selected instruments.
- The existing iPhone picker layout remains unchanged.

**Reference**

- Original feedback (French): “Quand je suis sur la fenêtre « Add Instruments », quand 7 instruments ou plus sont sélectionnés, tout défile vers le bas et à partir de 9 les boutons « Cancel » et « Add X Instruments » sont carrément hors du cadre et on ne peut pas remonter pour les atteindre.”

## Scanner release integration — November 19, 2026

Both apps now resolve public ScannerCore 0.1.23 at `d14c2a2dbbda5c1e4aad98c1ba20dc51be5b5ce0`. Large scores/photocopies, page-part matching, instrument transposition, drums, clefs and lyrics improve; the page-foot text crash is fixed. Scanner unit tests: 167/167 in 19 suites. Release builds and device checks are recorded separately; no new distribution has been submitted.
