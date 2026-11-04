# Onboarding: how Aria works

Read this first if you're new to the project, human or agent. It explains how the pieces
fit together, how a change travels from the engine to the screen, how to check your work,
and the rules the owner works by. It links to the detailed docs rather than repeating them.

## What Aria is

Aria reads, plays and edits MuseScore (`.mscz`, `.mscx`) and MusicXML scores on iPhone,
iPad, iPhone Duo and Android phones and tablets. Notation, playback, saving and export all
come from MuseScore Studio's own engine (4.7.6), so a score saved in Aria opens unchanged
in desktop MuseScore Studio. The UI is touch-first SwiftUI, and Android runs the same
Swift.

One person maintains both apps. That drives two of the rules below: share code instead
of duplicating it, and keep iOS and Android the same.

## Read next

| Doc | When |
| --- | --- |
| [README.md](README.md) | Getting the source (Git LFS), iOS build requirements, Qt setup, architecture summary |
| [AGENTS.md](AGENTS.md) | Hard rules for builds and file compatibility (short; always applies) |
| [MuseReaderAndroid/AGENTS.md](MuseReaderAndroid/AGENTS.md) | Before touching anything under `MuseReaderAndroid/` |
| [MuseReaderAndroid/README.md](MuseReaderAndroid/README.md) | Android build commands and Skip porting notes |
| [sandbox/engraving/compat/ENGINE.md](sandbox/engraving/compat/ENGINE.md) | Engine version, Aria's patches to it, how to move to a newer MuseScore release |
| [sandbox/engraving/compat/README.md](sandbox/engraving/compat/README.md) | Round-trip, layout, MusicXML and playback checks against desktop MuseScore |
| [MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md](MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md) | The backlog: what users asked for and its status |
| [MuseReaderAndroid/IOS_CHANGES.md](MuseReaderAndroid/IOS_CHANGES.md) | Log of every shared/iOS change, with iOS test steps |
| [MuseReaderiOS/PlaybackArchitectureNotes.md](MuseReaderiOS/PlaybackArchitectureNotes.md) | How playback and the audio engine fit together |
| [MuseReaderiOS/VIDEO_EXPORT_HANDOFF.md](MuseReaderiOS/VIDEO_EXPORT_HANDOFF.md) | Video export design and checks |

## Repository map

| Path | What's there |
| --- | --- |
| `src/`, `thirdparty/`, other upstream folders | MuseScore Studio 4.7.6 source with a few Aria patches. Treat as upstream: change only through the steps in `ENGINE.md`. |
| `sandbox/engraving/` | Aria's **render core**: a C++ layer over the engine that opens, renders, edits, plays, saves and exports scores. One class, `msr::render::ScoreRenderSession`. |
| `sandbox/engraving/compat/` | Compatibility checks against desktop MuseScore, and engine-update notes. |
| `sandbox/engraving/tests/` | Native tests for the render core. |
| `MuseReaderiOS/Aria.xcodeproj` | The iOS app (scheme `Aria`, bundle ID `com.hdi200.ariascore`). |
| `MuseReaderiOS/MuseReaderiOS/` | The app's Swift, shared with Android: `App/`, `Bridge/`, `Models/`, `Services/`, `Views/`, `Resources/`. |
| `MuseReaderiOS/MuseReaderiOSTests/`, `MuseReaderiOSUITests/` | Unit tests and UI tests (the UI tests also take layout screenshots). |
| `MuseReaderiOS/Checks/` | Source checks that run without Xcode (video export). |
| `MuseReaderAndroid/` | The Android app: Skip/Gradle project, Android engine bridge, Apple-framework stand-ins, Kotlin platform code. Same repository. |
| `promo/` | Marketing: App Store and Play screenshots, promo videos, and their build scripts. **Git-ignored**; each topic has its own folder. |

## How it works

### The path from a tap to the screen (iOS)

1. `MuseReaderiOSApp` shows `LibraryView`. `MuseReaderAppModel` (`App/`) owns the library: imports, recents, setlists, new scores, the paywall, and opening scores.
2. `MuseScoreSessionService` (`Services/ScoreSessionService.swift`) inspects the file and opens a **live session**.
3. `ScoreReaderView` (`Views/`) owns `ScoreReaderState` (`Models/`, split into `ScoreReaderState*.swift` by concern: pages, editing, playback, autosave). It coordinates page images, selection, edits, playback, parts and saving.
4. `LiveScoreRenderSession` (`Services/`) is a Swift actor around the bridge, so engine calls stay off the main thread and in order.
5. `MuseScoreRenderCoreBridge.mm` (`Bridge/`) is Objective-C++ that maps Swift calls onto `ScoreRenderSession` and converts results into Objective-C types.
6. `sandbox/engraving/score_render_*.cpp` does the real work with MuseScore's engraving, playback and save APIs.

**Edits always go through the engine.** Swift never edits a score itself. It sends a
command, gets back the new edit state (what's selected, what the toolbar should show), and
redraws the affected pages. That keeps undo, layout and saved files identical to desktop
MuseScore.

### Android

Android runs the same Swift files (compiled natively by Skip Fuse; SwiftUI is shown through
Jetpack Compose). Only the edges differ:

- **Engine bridge:** `MuseReaderAndroid/Aria/Sources/AriaEngine/` (`MSRRenderSession.swift`, `BridgeTypes.swift`, `BridgeConversions.swift`) plays the role of the `.mm` bridge, using Swift's C++ interop.
- **Apple frameworks:** stand-ins with the same API in `Aria/Sources/AndroidShims/`.
- **Platform features** (files, sharing, billing, MIDI, video): Kotlin in `Aria/Android/app/src/main/kotlin/`.
- **Android-only behaviour in shared files** goes behind `#if os(Android)`.

Details, and Skip's quirks, are in [MuseReaderAndroid/AGENTS.md](MuseReaderAndroid/AGENTS.md).

### Phone, iPad and iPhone Duo layouts

- Views ask `AriaWindowLayout.shared.usesPhoneLayout` (`Models/AriaWindowLayout.swift`), not the device type. The iPad layout is used when the window is at least 744 pt on both sides, so split view and the Duo get the right layout. Device behaviour (orientation lock, Pencil) still checks the device.
- **iPhone Duo:** `DuoHingeWatcher` (`Views/`) reads the hinge, and `DuoPose` (`Models/`) names the pose: closed, open flat, book (fold top to bottom) or stand (fold across). `DuoReaderRegions.swift` places views per pose, and `ScoreReaderDuoStandPanel.swift` is the music-stand control panel on the flat half. Everything Duo-specific is gated on the hinge, so other devices are unaffected.

## Adding an editing feature

Most features follow the same path through every layer. Using "toggle double dot" as the
example, a new command touches:

1. **Engine:** implement it in `sandbox/engraving/score_render_edit_commands.cpp`, declare it in `score_render_core.h`, and forward it in `score_render_core_facade.inc`. Use MuseScore's undoable commands (`startCmd`/`endCmd`, `undoChangeProperty`) so undo and saving behave as on desktop. If the toolbar needs new state, add it to the edit state (`score_render_edit_state.cpp`).
2. **iOS bridge:** expose it in `MuseScoreRenderCoreBridge.h` / `.mm`, including any new edit-state fields.
3. **Android bridge:** the same in `MuseReaderAndroid/Aria/Sources/AriaEngine/` (`MSRRenderSession.swift`; `BridgeTypes.swift` and `BridgeConversions.swift` for new state fields).
4. **Session:** add the call to `LiveScoreRenderSession.swift`.
5. **State:** add the action to `ScoreReaderStateEditing.swift` (it applies the returned edit state and refreshes pages).
6. **UI:** add the control, usually in `ScoreReaderContextToolbars.swift`, `ScoreReaderEditingDeck.swift` or `ScoreReaderFloatingPalette.swift`. Check the iPad row, the phone layout and the Duo poses.
7. **Log it:** add an entry to `MuseReaderAndroid/IOS_CHANGES.md` (what changed, how to test on iOS), and update the item in `FEATURE_REQUESTS_AND_BUGS.md`.

Rebuild the native engine after step 1 (see below), and run the compatibility checks if
the change affects what gets saved.

## Building and checking

### Swift changes: typecheck without Xcode

A full Xcode build always rebuilds the engine through CMake, which is slow. For Swift-only
changes, typecheck instead. Run this from `MuseReaderiOS/`. It uses the same concurrency
settings as the Xcode project:

```sh
find MuseReaderiOS -name '*.swift' -print0 | xargs -0 xcrun swiftc -typecheck \
  -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature MemberImportVisibility \
  -target arm64-apple-ios17.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -module-name Aria -module-cache-path "$TMPDIR/aria-modcache" \
  -import-objc-header MuseReaderiOS/Bridge/MuseReaderiOS-Bridging-Header.h 2> "$TMPDIR/typecheck.txt"
grep -c ' error:' "$TMPDIR/typecheck.txt"; grep -c ' warning:' "$TMPDIR/typecheck.txt"
```

Expect 0 errors, and no more warnings than before your change (72 as of November 2026).
Compare warnings per file to find new ones.

### Engine changes

- The render core builds into `/tmp/musescore-score-render-core-ios` (device) and `/tmp/musescore-score-render-core-simulator` (simulator). Reuse them and never clean them. macOS purges `/tmp`, so a cold build recompiles the engine (about 15 minutes).
- Rebuild only when `sandbox/engraving`, the engine, its Qt dependencies or the bridge's link requirements change.
- After any engine or writer change, run the checks in [compat/README.md](sandbox/engraving/compat/README.md) and compare the reports with the previous run. The host build lives in `build-aria-475-host`.

### Running on simulators

- iOS simulators run Aria natively on arm64, using a separate simulator Qt (`MUSEREADER_QT_IOS_SIMULATOR_SDK_DIR` in `Local.xcconfig`, built by `MuseReaderiOS/scripts/build-qt-ios-simulator.sh`).
- Build Release for the simulator (Debug engine builds assert):

  ```sh
  xcodebuild -project MuseReaderiOS/Aria.xcodeproj -scheme Aria -configuration Release \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO -derivedDataPath "$TMPDIR/aria-dd" build
  ```

- **iPhone Duo poses** are set in Xcode's Device Hub (Closed / Partially Open / Open); there's no `simctl` command for them. Inner and cover screens are separate displays for `simctl io … screenshot --display=`.
- When nobody can grant simulator access, drive the app with the UI tests (`MuseReaderiOSUITests/LayoutScreenshotUITests.swift`), run with `-parallel-testing-enabled NO`.

### Android

Build, then stop Gradle, then start one emulator: the Mac runs out of memory when they
run together. Commands, emulators and Play Console rules are in
[MuseReaderAndroid/AGENTS.md](MuseReaderAndroid/AGENTS.md).

### Tests

- iOS: `xcodebuild test -project MuseReaderiOS/Aria.xcodeproj -scheme Aria` (needs the render core built).
- Video export source check: `python3 MuseReaderiOS/Checks/check_video_export.py`.
- Engine: native tests and edit sweeps in `sandbox/engraving/tests/`; compatibility sweeps in `sandbox/engraving/compat/`.

## File compatibility (non-negotiable)

- Scores Aria saves must open unchanged in the current desktop MuseScore Studio (4.7.6, file format 4.70).
- Never merge upstream MuseScore `main` into `src/`. It's MuseScore 5 development and writes format 5.00, which desktop 4.7 rejects. Move only between release tags, following `ENGINE.md`.
- Newer files are opened anyway (like desktop's "Open anyway") and saved back as 4.70.

## Tracking work

- **Backlog:** `MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md`. New features get the next `IOS-###`, bugs the next `BUG-###`. Keep the status and notes current, including what was and wasn't tested.
- **Shared/iOS change log:** `MuseReaderAndroid/IOS_CHANGES.md`, newest first. Every change to shared or iOS code gets an entry with iOS test steps.
- **Android to-dos:** `MuseReaderAndroid/FEATURES_TODO.md`.

## Working with the owner

- **Ask before anything that can't be undone or that leaves this machine:** pushing, App Store Connect or Play Console actions, uploads, deleting files you didn't make, uninstalling apps that hold scores.
- **Never push** unless asked. Commit only when asked.
- **Commits:** no `Co-Authored-By: Claude` trailer, and no machine paths (`/Users/…`, `/tmp/…`), simulator IDs, keys or passwords in commits, messages or PRs. Check the staged diff before committing.
- **Never handle passwords, signing keys, payment, tax or bank details.** The owner does those.
- **Share code between iOS and Android,** and keep their features and behaviour the same unless a platform convention says otherwise.
- **Verify before saying something works.** Run it on a simulator or emulator, and say plainly what you didn't test.
- **Marketing output** (screenshots, videos, their scripts) goes in `promo/<topic>/`, never only in a temp folder.
- **Support replies** are written as the owner, in the first person singular and signed "Jack": never "we" or "the team". Check each answer against the current code.
- **During design iteration** on UI the owner is actively reviewing, show changes quickly. Run the full checks (typecheck, Android build, phone/iPad comparison) before committing, not after every tweak.

## Where to find things

| Need | Look in |
| --- | --- |
| Library, imports, recents, paywall | `App/MuseReaderAppModel.swift`, `Views/LibraryView.swift` |
| Reader screen and its state | `Views/ScoreReaderView.swift`, `Models/ScoreReaderState*.swift` |
| Edit toolbars and note entry | `Views/ScoreReaderContextToolbars.swift`, `ScoreReaderEditingDeck.swift`, `ScoreReaderNoteEntrySurface.swift`, `ScoreReaderPitchKeyboard.swift` |
| Playback | `Models/ScoreReaderStatePlayback.swift`, `Services/NativePlaybackController.swift`, `sandbox/engraving/score_render_playback.cpp` |
| Export (PDF, MusicXML, MIDI, audio, images, video) | `Views/ScoreReaderExportPanel.swift`, `Services/ScoreVideoExporter.swift`, `sandbox/engraving/score_render_export.cpp` |
| Opening and saving files | `sandbox/engraving/score_render_open_save.cpp` |
| Engine commands | `sandbox/engraving/score_render_edit_commands.cpp` |
| Phone/iPad/Duo layout decisions | `Models/AriaWindowLayout.swift`, `Models/DuoPose.swift`, `Views/DuoReaderRegions.swift` |
| Score templates for New Score | `Resources/ScoreTemplates.bundle/` |
| Licences and notices | `MuseReaderiOS/THIRD_PARTY_NOTICES.md`, `MuseReaderiOS/OPEN_SOURCE_COMPLIANCE.md` |
| Android specifics | [MuseReaderAndroid/AGENTS.md](MuseReaderAndroid/AGENTS.md) "Where to find things" |
