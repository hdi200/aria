# MuseReader iOS Feature Requests and Bugs

This file is the shared backlog for feature ideas and known bugs specific to the MuseReader iOS app.

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
| IOS-005 | Import multiple files at once | Bring several score files into ARIA in a single import operation. | High | Proposed | The requester described this as the most important item. |

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
