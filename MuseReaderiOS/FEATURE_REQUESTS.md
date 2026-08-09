# MuseReader iOS Feature Requests

This file is the shared backlog for feature ideas specific to the MuseReader iOS app.

## How to add a request

Add a row to the backlog with a short title and enough context to understand the user need. Use the next available `IOS-###` identifier.

Statuses:

- `Proposed` — captured for review
- `Planned` — accepted for a future release
- `In progress` — currently being implemented
- `Done` — released or otherwise completed
- `Declined` — not currently planned; explain why in Notes

Priorities:

- `High` — important or time-sensitive
- `Medium` — valuable, but not urgent
- `Low` — useful enhancement

## Backlog

| ID | Feature request | User need | Priority | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| IOS-001 | Global score transposition | Change the key of a song and transpose the entire score in one action. | High | Proposed | Requested by multiple users; suggested location: More. |
| IOS-002 | Temporary transpose in View mode | Quickly view a score in another key without entering Edit mode or changing the underlying file. | High | Proposed | Keep separate from permanent score transposition. |
| IOS-003 | Preview a chord by tapping it | Hear whether a chord sounds correct without starting score playback. | Medium | Proposed |  |
| IOS-004 | Reposition layout items by dragging | Freely arrange layout items instead of having them locked in place. | Medium | Proposed | The exact items and layout surfaces still need clarification. |
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

### IOS-003 — Preview a chord by tapping it

**Problem**

Users want to verify a chord by ear without starting playback for the entire score.

**Proposed outcome**

When a user taps a chord, provide a way to play a short audio preview of that chord.

**Acceptance criteria**

- A chord can be previewed without starting normal score playback.
- The preview uses the pitches represented by the selected chord.
- Previewing one chord does not unexpectedly change the score.

**References**

- Original feedback (Portuguese): “Ao clicar nos acordes eles poderiam tocar pra gente ouvir se o acorde está certo sem precisar dar play na música.”

### IOS-004 — Reposition layout items by dragging

**Problem**

Users feel constrained when layout items are fixed in place.

**Proposed outcome**

Allow supported layout items to be repositioned directly with drag gestures.

**Acceptance criteria**

- The supported item types and screens are defined before implementation.
- Supported items can be moved with a direct drag gesture.
- New positions are saved with the score when appropriate.
- Movement includes safeguards against accidentally losing an item off-screen.

**References**

- Original feedback (Portuguese): “Outra coisa seria poder arrastar os itens dos layout, que nada ficasse preso.”
- Follow up with the requester to identify which layout items they most need to move.

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
