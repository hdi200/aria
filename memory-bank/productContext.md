# Product Context

## Why This Project Exists

MuseScore files already contain rich notation data, but the desktop app is not an iPad-native reader/editor experience. The goal of MuseReader is to provide a native Apple UI for opening and interacting with MuseScore scores on iPad, while reusing MuseScore's existing score engine where it provides the most value.

## User Problem

Users need a practical way to:

- open `.mscz` and `.mscx` on iPad
- browse real score pages instead of raw package contents
- inspect basic score metadata quickly
- keep imported scores available inside the app without depending on the original Files location
- make a few high-value score edits without needing the desktop app nearby

The longer-term product problem is larger:

- users will eventually expect playback
- users will likely want at least limited editing
- those capabilities need to build on the same canonical document model, not a throwaway read-only prototype

## Current Product Shape

The app currently behaves as a native score reader with inspection tools and an internal library:

- left pane: library/import entry point
- main library area: score-card grid with direct reader launch
- score info: lightweight popover from each card for quick metadata
- full-screen reader: page-focused reading surface backed by live rendering when available
- reader editing: a floating left editor rail for durable note-entry and edit controls, plus a bottom pitch keyboard deck for selected-note pitch changes inside a full-screen scrollable page canvas with minimal floating chrome
- imported scores: copied into MuseReader-managed storage so reading, playback, and save-back all target the app-owned copy
- library styling: a crisp connected split layout with a branded sidebar, white surfaces, indigo actions, and pastel score cards that should feel at home on iPad

## UX Goals

- feel like a native iPad app, not a ported desktop UI
- make the library screen feel polished and product-ready rather than utilitarian
- make importing from Files straightforward and durable
- show useful score information without forcing the user through a heavy intermediate detail screen
- degrade gracefully when only embedded previews are available
- keep the product honest about current capability levels
- avoid making the user care whether the original file provider is still reachable after import
- make basic notation editing feel native to iPad instead of copying desktop MuseScore interaction patterns
- keep the editor surfaces contextual; do not show the app a full desktop-style palette when the engine only supports a narrow editing slice
- make the editing layout feel tablet-native: durable mode and rhythm controls on the side, pitch-oriented interaction near the bottom where a keyboard metaphor makes sense
- let editing feel like working on the score itself, not stepping through separate page cards; scrolling between pages should feel natural while the tool surfaces stay out of the way
- keep top-level reader chrome sparse: a way back to the library and a way to play/pause are enough until more transport is truly necessary

## Product Direction

The intended progression is:

1. reader-first
2. playback on the same open score session
3. narrow notation editing on the same open score session
4. broader editing commands and save-back on the same open score session

That sequence matters because it keeps the architecture aligned with a real notation app instead of a gallery of thumbnails.
