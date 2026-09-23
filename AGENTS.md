# Repository Agent Notes

## MuseReader iOS builds

- The active Xcode project and scheme are `MuseReaderiOS/Aria.xcodeproj` and `Aria`.
- The `Aria` target has an always-out-of-date render-artifacts shell phase. Running a full `xcodebuild` therefore enters CMake/Ninja even for Swift-only work.
- For Swift or SwiftUI-only changes, Codex must not invoke that Xcode build or the CMake render-core target merely as a routine verification step. Preserve and reuse the outputs in `/tmp/musescore-score-render-core-ios`; do not clean them.
- Rebuild `MuseScoreRenderCore` only when the user explicitly asks, when `sandbox/engraving`, its MuseScore/Qt dependencies, or native bridge/link requirements change, or when a required native artifact is missing.
- Prefer lightweight source checks for SwiftUI-only edits and let the user run the app from Xcode when device verification is needed.

## MuseScore file compatibility

- Aria-saved scores must open unchanged in the current stable desktop MuseScore Studio (4.7.5, file format 4.70). Most users are on it, and MuseScore 5 is unreleased.
- The engine in `src/` is an upstream main snapshot from about April 2026, which writes format 5.00. `src/engraving/infrastructure/mscwriter.cpp` relabels saves as 4.70. That is only safe because this snapshot's writer still emits 4.70-compatible XML.
- Do not merge newer upstream main into `src/`. Later main changes break 4.70 round trips silently. Examples: text offsets migrated on `< 500`, enums written as text, stave sharing, `<BracketItem>`/`<InstrumentLabel>` labels, and the separate `Read500` reader.
- After any engine or writer change, run the round-trip check in `sandbox/engraving/compat/README.md` and compare its report with the previous run.
