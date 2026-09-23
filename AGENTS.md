# Repository Agent Notes

## MuseReader iOS builds

- The active Xcode project and scheme are `MuseReaderiOS/Aria.xcodeproj` and `Aria`.
- The `Aria` target has an always-out-of-date render-artifacts shell phase. Running a full `xcodebuild` therefore enters CMake/Ninja even for Swift-only work.
- For Swift or SwiftUI-only changes, Codex must not invoke that Xcode build or the CMake render-core target merely as a routine verification step. Preserve and reuse the outputs in `/tmp/musescore-score-render-core-ios`; do not clean them.
- Rebuild `MuseScoreRenderCore` only when the user explicitly asks, when `sandbox/engraving`, its MuseScore/Qt dependencies, or native bridge/link requirements change, or when a required native artifact is missing.
- Prefer lightweight source checks for SwiftUI-only edits and let the user run the app from Xcode when device verification is needed.

## MuseScore file compatibility

- Aria-saved scores must open unchanged in the current stable desktop MuseScore Studio (4.7.5, file format 4.70). Most users are on it, and MuseScore 5 is unreleased.
- The engine in `src/` is MuseScore 4.7.5 (tag `v4.7.5`) plus a few Aria patches, listed in `sandbox/engraving/compat/ENGINE.md`. It writes genuine 4.70 files; there is no version relabeling.
- Do not merge upstream `main` into `src/`; it is MuseScore 5 development and writes format 5.00. Move to a newer release tag only, using the steps in `ENGINE.md`.
- Files newer than 4.70 are opened anyway (like desktop's "Open anyway") and saved back as 4.70.
- After any engine or writer change, run the checks in `sandbox/engraving/compat/README.md` (host build in `build-aria-475-host`) and compare the reports with the previous run.
