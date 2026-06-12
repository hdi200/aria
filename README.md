# Aria

Aria is an iOS score reader and editor for MuseScore and MusicXML files. It pairs a SwiftUI library/reader interface with a MuseScore Studio-derived render core so scores can be opened, rendered, edited, played back, saved, and exported on iPhone and iPad.

Aria is not affiliated with, sponsored by, or endorsed by MuseScore, Muse Group, or MuseScore Studio. MuseScore names are used descriptively to identify supported file formats and the upstream codebase this project derives from.

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.en.html)

## What Is Here

- `MuseReaderiOS/`: the iOS app, Xcode project, SwiftUI views, document library, import flow, playback, editing state, legal resources, tests, and Objective-C++ bridge.
- `sandbox/engraving/`: the reusable MuseScore-derived render core used by the app for page rendering, score edits, playback data, MusicXML export, and saving.
- `src/`, `thirdparty/`, and other MuseScore Studio source folders: the upstream-derived code needed by the render core build.
- `MuseReaderiOS/THIRD_PARTY_NOTICES.md`: third-party notices for MuseScore-derived code, bundled fonts, SoundFonts, FluidSynth, FreeType, Opus, Qt, and other dependencies.
- `MuseReaderiOS/OPEN_SOURCE_COMPLIANCE.md`: release checklist for publishing corresponding source, notices, and build inputs.

## Supported Files

Aria can import and open:

- `.mscz`
- `.mscx`
- `.mxl`
- `.musicxml`
- `.xml`

The app stores imported scores in its visible iOS Documents area under `Scores/`, keeps a private index in Application Support, and autosaves supported edits back to the managed score file.

## Architecture

At a high level:

1. `MuseReaderiOSApp` launches the SwiftUI app and shows `LibraryView`.
2. `MuseReaderAppModel` handles imports, recent scores, setlists, score creation, and opening sessions.
3. `MuseScoreSessionService` inspects the package, reads embedded previews, and opens a live render session when the render core is available.
4. `ScoreReaderView` owns `ScoreReaderState`, which coordinates page loading, selection, editing, playback, parts, concert pitch, export, and autosave.
5. `LiveScoreRenderSession` is a Swift actor wrapping `MSRRenderSession`.
6. `MuseScoreRenderCoreBridge.mm` maps Swift/Objective-C calls into `msr::render::ScoreRenderSession`.
7. `sandbox/engraving/score_render_core.*` uses MuseScore Studio engraving, MusicXML, playback, and save APIs for the actual notation behavior.

Edits are intentionally routed through the MuseScore-derived engine. The Swift layer manages UI state, page cache invalidation, playback invalidation, and save timing around the edit state returned by the render core.

## Getting The Source

This repository uses Git LFS for the required iOS SoundFont:

```sh
git clone https://github.com/hdi200/aria.git
cd aria
git lfs pull
```

Confirm that the required `.sf2` file is present as a real binary file, not an LFS pointer:

```sh
git lfs ls-files
wc -c MuseReaderiOS/MuseReaderiOS/Resources/MuseScore_General.sf2
```

`MuseReaderiOS/MuseReaderiOS/Resources/MuseScore_General.sf2` is required for current iOS playback. Do not remove it or replace it with only an `.sf3` file; the iOS audio path depends on the `.sf2` SoundFont.

## Build Requirements

- macOS with Xcode and the iOS SDK.
- CMake.
- Ninja.
- Git LFS.
- Qt for iOS and a matching host Qt SDK for the Qt build tools.

The Xcode project is:

```text
MuseReaderiOS/Aria.xcodeproj
```

Use the shared scheme:

```text
Aria
```

The app target bundle identifier is:

```text
com.hdi200.ariascore
```

The Xcode build phase builds `sandbox/engraving` into a `MuseScoreRenderCore` static library with CMake/Ninja. The project currently expects these build settings to point at local Qt installs:

```text
MUSEREADER_QT_IOS_SDK_DIR
MUSEREADER_QT_HOST_SDK_DIR
```

For example:

```sh
export MUSEREADER_QT_IOS_SDK_DIR="$HOME/Qt/6.11.0/ios"
export MUSEREADER_QT_HOST_SDK_DIR="$HOME/Qt/6.11.0/macos"
open MuseReaderiOS/Aria.xcodeproj
```

Build directories are created under `/tmp`:

- `/tmp/musescore-score-render-core-ios`
- `/tmp/musescore-score-render-core-simulator`

If you build for Simulator, make sure an iOS Simulator runtime is installed. A physical device build does not require a local Simulator runtime.

## Tests

The iOS test target includes parser, package inspection, session-opening, and render-core bridge coverage:

```sh
xcodebuild test -project MuseReaderiOS/Aria.xcodeproj -scheme Aria
```

Some tests require the render core and its Qt dependencies to build successfully first.

## Legal

Aria includes GPLv3-covered MuseScore Studio-derived code. See `LICENSE.txt` for the GPLv3 license text and `MuseReaderiOS/THIRD_PARTY_NOTICES.md` for third-party notices.

The bundled MuseScore General SoundFont files include their own license metadata and license files in `MuseReaderiOS/MuseReaderiOS/Resources/Legal/`.

If you distribute builds, publish the corresponding source for the exact version you distribute, including the iOS app source, bridge code, render-core source, build scripts, third-party notices, and the MuseScore-derived source snapshot used for the build.

## Development Notes

- Keep local build products, `DerivedData`, `.DS_Store`, `xcuserdata`, and personal backup folders out of Git.
- The app has local backup ignores for nested Git histories from earlier development; the public repo tracks `MuseReaderiOS/` and `sandbox/` as normal folders.
- Demo/export scratch files under `demos/All_Dudes pre_export.mscz` and `demos/Demos Pre IOS Export/` are intentionally ignored.
