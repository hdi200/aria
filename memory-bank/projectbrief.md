# Project Brief

## Project

MuseReader is an iPad-native reader app being developed inside the `MuseScore-master` workspace, with the app target in `MuseReaderiOS/`. The app reads MuseScore documents (`.mscz` and `.mscx`) using a native SwiftUI interface layered over reusable MuseScore C++ rendering code and now treats imported scores as app-owned library items stored in `Application Support`.

## Core Goal

Ship a working iPad reader first, while preserving an architecture that can later support:

- live score playback
- incremental score editing and save-back
- broader document/session capabilities without rewriting the app shell

## Current Scope

The current implementation focuses on a reader-first internal library:

- import scores from the Files app into MuseReader-managed storage
- reopen imported scores from the app's internal library index
- inspect MuseScore package contents and metadata
- show embedded preview assets when present
- open a full-screen reader
- keep a live MuseScore-backed render session open and render pages on demand
- support native playback
- support first-pass metadata editing and save-back
- support a first narrow notation-editing slice:
  - tap note/rest to select
  - delete selection
  - pitch up/down
  - duration change
  - rest toggle
  - standard-staff tap-to-enter note
  - undo/redo/save

## Near-Term Priorities

1. Validate the first notation-editing slice on real iPad hardware.
2. Make the iPad reading experience and internal-library flow reliable on real devices.
3. Preserve the live session boundary so broader editing can attach to the same canonical document.

## Explicit Non-Goals For Now

- desktop MuseScore parity
- App Store licensing/distribution work
- iPhone-specific UI polish

## Success Criteria

- A user can import `.mscz` or `.mscx` from Files.
- The imported score is copied into MuseReader-owned storage and can be reopened without depending on the original Files location.
- The app can inspect the document and surface usable metadata.
- The app can open a full-screen reader on iPad.
- Live-rendered pages can be requested page-by-page from a persistent score session.
- Playback, metadata save-back, and the first notation-editing slice work against the imported library copy.
- The implementation remains open for future playback and editing instead of locking into a read-only architecture.
