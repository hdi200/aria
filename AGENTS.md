# Repository Agent Notes

## MuseReader iOS builds

- The active Xcode project and scheme are `MuseReaderiOS/Aria.xcodeproj` and `Aria`.
- The `Aria` target has an always-out-of-date render-artifacts shell phase. Running a full `xcodebuild` therefore enters CMake/Ninja even for Swift-only work.
- For Swift or SwiftUI-only changes, Codex must not invoke that Xcode build or the CMake render-core target merely as a routine verification step. Preserve and reuse the outputs in `/tmp/musescore-score-render-core-ios`; do not clean them.
- Rebuild `MuseScoreRenderCore` only when the user explicitly asks, when `sandbox/engraving`, its MuseScore/Qt dependencies, or native bridge/link requirements change, or when a required native artifact is missing.
- Prefer lightweight source checks for SwiftUI-only edits and let the user run the app from Xcode when device verification is needed.
