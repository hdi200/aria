# Aria editing UI changes

Updated November 4, 2026. This summarizes the fingering, chord-entry and tempo work
from this editing session, including shared Android behavior and verification limits.also c

## Fingering

- Added **Text > Fingering**, with large 1–5 keys and a remove key. The panel keeps
  the score interactive and does not open a keyboard.
- Uses real MuseScore noand te-attached fingerings. Adding, replacing and removing
  fingerings supports Undo/Redo, linked parts, saving and reopening.
- Entering a digit advances to the next note, skipping rests. Remove erases the
  current note's fingering and moves to the preceding note, skipping rests.
- Fixed the end-of-notes lockup: terminal-rest navigation now compares stable score
  positions rather than freshly generated render data. The final note stays selected
  and the controls become available again, even when empty bars follow it.
- Fingerings can be nudged with the existing drag gesture. MuseScore visual offsets
  move the digit while its original parent note stays fixed, even when dropped near
  another note. A dashed guide shows that attachment.
- Used a pointing-finger icon. Adjusted the iPhone selection outline to give the
  digit moderate breathing room without the original wide text box. Tablet styling
  and the larger invisible touch target remain intact.
- Fixed the Android crash caused by the digit button range crossing Skip's bridge;
  the buttons now use an explicit array.

## Chord entry and Text navigation

- Replaced keyboard-based chord entry in the Text deck with **Chord Entry**: root,
  quality, extension, accidental, alteration, slash-bass and erase buttons, plus a
  live chord preview and Previous/Next controls.
- Previous and Next commit a changed, complete draft before navigating. Existing
  symbols prefill from the score when revisiting a position in either direction.
  Imported spellings remain unchanged until edited; incomplete drafts cannot commit.
- Renamed Apply to **Done**. Done commits a changed complete chord and returns to
  the Text menu. The compact gray back chevron returns without applying the draft.
- Lyrics Done and dismissal also return to Text. Both the compact phone and
  full-size tablet/folded layouts use this destination, retaining lyric-session
  cleanup and keyboard dismissal.
- iOS Chord Entry fits all extensions on one row, with smaller numbers in compact
  layouts. Unselected keys share a light gray fill. The quality row shows maj,
  min, °, ø, + and sus. The preview stays blank until there is a chord to show.
  Android phones keep two extension rows.
- The iOS chord preview has an underline and a blue caret. On iPhone, larger
  extension numbers and heavier root letters distinguish the rows, and the mode
  toolbar sits above the chord and Fingering Entry panels.
- On iPhone, the toolbar fade clears at the end of the scroll. Chord Text uses
  C7 again, and Fingering uses the open-hand icon on iPhone and iPad.
- On iPhone and iPad, flat and sharp follow B, the flat glyph is larger, and
  Enter keeps its arrow. Backspace sits directly after slash in the modifier row.
  Tap the active slash key to clear the bass, or tap a selected extension to clear it.
- Entry preview now uses the chord pitches MuseScore returns, including a slash
  bass, before advancing. Score playback and Undo keep their existing paths.

## Tempo

- Reworked the editor into a card with a large beat/BPM preview, beat-unit choices,
  a number pad, optional tempo text, Cancel and Done.
- Combined markings display the description, one space, then the metronome equation
  (for example, Allegro followed by quarter note = 112).
- Stores a native MuseScore TempoText with its tempo and Follow Text properties,
  rather than a plain text imitation. Descriptions are escaped, and the equation
  parser handles descriptions containing numbers or punctuation.
- Reopening restores the description, beat unit and BPM. Linked parts and Undo use
  the native command path.
- Hid the number pad while entering tempo text and kept the card compact, avoiding
  the tall empty column shown with the software keyboard.
- Fixed Android fixed-height sheet placement to account for the keyboard's height,
  keeping the tempo text field above it on phone and tablet layouts. The vendored
  SkipUI adjustment is recorded in its patch log.

## Verification completed

- Shared iOS Swift typechecking has passed with zero errors and 72 existing warnings.
- iOS simulator and Android debug builds passed for the new editing features and
  the fingering endpoint fix.
- iPhone/iPad interaction checks covered fingering entry, erase/back, chord
  Previous/Next prefill, tempo text, reopening and Undo. Fingering drag and Undo were
  checked on iPhone and iPad; the medium iPhone outline passed screenshot review.
- The iPhone 17 Pro endpoint regression passed entry of 1, 2, 3, 5, replacement on
  the final note, exiting the panel and undoing all five test commands. The saved
  fixture had no remaining fingerings, and the original reference score XML was
  unchanged.
- A focused regression executes the production fingering action with changing
  render payloads. It fails before the endpoint fix and passes afterward, covering
  leading/trailing rests, replacement and backward erase navigation.
- Android phone and tablet-layout instrumentation checked tempo field visibility,
  successful keyboard input, fingering-panel opening and chord-control bounds.
  Captured screenshots were inspected. Tablet layout used a reversible display
  configuration of the available Pixel emulator.
- Native tests covered fingering attachment, dragging near other notes, chord-note
  parents, linked parts, Undo/Redo, saved offsets and live/reopened layout. Native
  tempo tests covered optional text, units, parsing, linked parts and Undo.
- Desktop MuseScore Studio 4.7.6 compatibility checks passed normalized/direct
  round trips, page layout, MusicXML and playback comparisons for the fingering and
  tempo corpora. Saved scores retain genuine file format 4.70.

## Final Done-navigation check

The final navigation adjustment passes shared iOS typechecking with zero errors and
72 existing warnings, and the Release iPhone simulator build passes while reusing
existing native artifacts. Chord and Lyrics Done were checked through Device Hub on iPhone 17 Pro and both
visibly restored the Text choices. The separate QA score contains no leftover lyrics
or fingerings. The software keyboard was hidden during this final navigation check.
This final five-destination adjustment has not been rebuilt or interaction-tested
on Android, or interaction-tested on tablet/folded layouts.

## Remaining verification and deferred polish

- Android fingering drag and the last-note endpoint interaction have not been
  retested on the emulator; the shared fix compiled in the Android build.
- Expanded Duo Book/Stand drag checks remain unfinished. Earlier Duo fingering
  entry checks covered open portrait, Book and Closed poses.
- The final moderate selection-outline adjustment targets iPhone; Android retains
  its earlier tighter phone outline.

## Implementation references

- Shared panels: `MuseReaderiOS/Views/ScoreReaderChordEntry.swift`,
  `ScoreReaderNoteEntrySurface.swift`, `ScoreReaderMoreEditors.swift`.
- Editing and navigation: `MuseReaderiOS/Models/ScoreReaderStateEditing.swift`,
  `ScoreReaderChordDraft.swift`, `ScoreSession.swift`.
- Placement feedback: iOS `ZoomableImageView.swift` and Android
  `Aria/Sources/AriaSkip/AndroidZoomableImageView.swift`.
- Engine and both bridges: `sandbox/engraving/score_render_*`, iOS
  `MuseScoreRenderCoreBridge`, and Android `AriaEngine`.
- Checks: `Checks/check_fingering_navigation.py`, chord/tempo model tests, native
  engraving tests, iOS fingering UI tests and Android editing-panel instrumentation.
- Detailed history and test steps: [Android/shared change log](../MuseReaderAndroid/IOS_CHANGES.md),
  entries 64–80, and [feature/bug tracker](FEATURE_REQUESTS_AND_BUGS.md).

No commits, pushes, store submissions or purchases were made. Existing user scores
were preserved; our applied UI test edits were undone.
