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
| IOS-016 | Consecutive identical time signatures | Add the same time signature twice in a row (4/4 then another 4/4). | Medium | Proposed | Master backlog item 11. The second entry is currently prevented; check what desktop MuseScore allows so files stay compatible. |
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
