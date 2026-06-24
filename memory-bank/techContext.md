# Tech Context

## Main Technologies

- SwiftUI for the iPad app shell
- Swift concurrency for async session opening and page loading
- AVFoundation plus AudioToolbox for native MIDI playback on iPad
- ObjC++ for the native bridge into C++
- MuseScore C++ engraving/render infrastructure
- Qt 6 for core runtime dependencies used by the reusable render core
- CMake + Ninja for render-core builds
- Xcode project for the iOS app target

## Key Project Areas

- `MuseReaderiOS/` contains the native app target
- `MuseReaderiOS/MuseReaderiOS/Bridge/` contains ObjC++ and C++ bridge files
- `MuseReaderiOS/MuseReaderiOS/Services/` contains app-facing service abstractions
- `MuseReaderiOS/MuseReaderiOS/Models/` contains document/session/reader models
- `MuseReaderiOS/MuseReaderiOS/Views/` contains the SwiftUI screens
- `sandbox/engraving/` contains the standalone reusable render core build

## Build Setup

The iOS app uses a custom Xcode build phase to compile `MuseScoreRenderCore` from `sandbox/engraving/` into a framework-like artifact under `/tmp`.

Important environment variables:

- `MUSEREADER_QT_IOS_SDK_DIR`
- `MUSEREADER_QT_HOST_SDK_DIR`

Important build facts:

- the current simulator path excludes `arm64`
- device builds target `arm64`
- the render core build uses `cmake` and `ninja`
- the render core relies on Qt static plugin import for iOS integration
- playback is enabled by exporting MIDI from the score core rather than linking MuseScore's full notation/audio runtime
- playback-follow UI is enabled by exporting measure timing and normalized measure rectangles from the score core rather than reconstructing that data in Swift
- editing/save-back is enabled by extending `ScoreRenderSession` directly rather than linking MuseScore's full `notation`/`project` app stack into the iOS target
- the first notation-editing slice is also enabled by extending `ScoreRenderSession` directly rather than linking MuseScore's full desktop notation scene into the iOS target
- iOS save-back now coordinates writes with `NSFileCoordinator` and passes the coordinated file URL into `ScoreRenderSession::saveToPath(...)`
- imported score copies and the persisted library index now live under `Application Support/MuseReaderLibrary`

## Current Technical Constraints

- The Qt iOS SDK available in this workspace currently drives simulator constraints.
- The render core is produced outside the Xcode build products directory and linked back into the app from `/tmp`.
- CoreSimulator behavior in this environment is noisy and unreliable; device builds are more trustworthy for validation.
- Native playback now depends on `AVAudioEngine`, Apple’s `MIDISynth` music device, and a bundled `MuseScore_General.sf2` bank, so real-device audio validation is still required.
- Measure-follow highlighting now depends on normalized measure rectangles from the render core plus the native playback clock, so real-device validation is still required for both audio and overlay timing.
- Metadata editing/save APIs and a first note/rest editing API are now wired, but broader notation editing is not.
- The current note-editing bridge is intentionally limited to standard-staff note/rest workflows.
- `.mscx` save-back uses a directory rewrite/replace path, so directory-style scores need specific device validation.
- iOS bookmark creation/resolution uses plain bookmark data; `.withSecurityScope` bookmark options are unavailable on iOS in this target.
- Legacy bookmark-backed entries may still exist until they are reopened and migrated into the internal library.

## Dependency Notes

The render core is intentionally minimal compared with the full MuseScore app. It pulls in:

- `muse::global`
- `muse::draw`
- `engraving`
- MIDI export sources from `src/importexport/midi/internal/`
- Qt Core/Gui/Svg/Qml/Network

The render core intentionally does not pull in MuseScore's `notation`, `project`, or `audio` modules for iOS playback right now.

The app also contains:

- a separate lightweight package bridge for archive inspection and thumbnail extraction that does not depend on the full live renderer
- a managed-library service that copies imported scores into `Application Support` and resolves canonical internal URLs
- a native playback layer built around `AVAudioSession`, `AVAudioEngine`, `AVAudioSequencer`, and Apple’s `MIDISynth` audio unit
- a playback-follow data path built around `ScoreRenderSession::playbackMeasureRegions(...)`, the ObjC bridge, and `ScoreReaderState`
- a first edit/save path built around `ScoreRenderSession::updateMetadata(...)`, `ScoreRenderSession::saveToPath(...)`, the ObjC bridge, `NSFileCoordinator`, and `MuseReaderAppModel.saveMetadata(...)`
- a first notation-editing path built around `ScoreRenderSession` selection/note-input methods, the ObjC bridge, `LiveScoreRenderSession`, `ScoreReaderState`, and the reader overlay/edit strip UI

## Tooling Preferences

- Prefer `rg` for search.
- Use `apply_patch` for manual edits.
- Validate with targeted `xcodebuild` commands, especially `iphoneos` builds when simulator state is suspect.
- Keep the Swift-facing layer free of Qt types.
