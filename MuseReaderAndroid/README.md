# Aria for Android

This directory is part of the public Aria source repository. It contains the Android
application and build inputs, alongside the shared iOS/Swift and MuseScore-derived
sources in the parent directory. See [source releases](SOURCE_RELEASES.md) for the
versioned snapshots and [third-party notices](THIRD_PARTY_NOTICES.md) for dependencies.

## Source layout

- `Aria/`: Skip/Swift package and Android Gradle project.
- `Aria/Sources/AriaSkip/`: Android-specific views and adapters. `Shared/` contains
  relative symlinks to the Swift files listed in `ios-shared-sources.txt`.
- `Aria/Sources/AndroidShims/`: implementations of the Apple framework APIs used by
  the shared Swift code, backed by Android graphics, audio and platform services.
- `Aria/Sources/AriaEngine/`: Swift/C++ engine bridge; `AriaRenderCoreCxx/` exposes
  headers from `engine/`, the iOS bridge and the shared render core.
- `Aria/Android/app/src/main/`: Kotlin platform integration, manifest and app assets.
- `Aria/Android/soundbank/`: install-time Play asset pack for the shared SoundFont.
- `Aria/Vendor/`: patched Skip UI, Skip Fuse UI and Swift JNI sources. Each includes
  its upstream license and an `ARIA_PATCHES.md` describing local modifications.
- `engine/`: Android engine initialization and AAudio output, linked to the shared
  MuseScore render core in `../sandbox/engraving` and MuseScore 4.7.5 in `../src`.
- `scripts/`: native builds, shared-source linking, asset/bridge generation, bundle
  inspection, and an interactive helper for creating your own signing configuration.

Swift runs natively through Skip Fuse; SwiftUI views are presented using Jetpack
Compose. The notation engine is shared with iOS. App resources are linked from
`../MuseReaderiOS/MuseReaderiOS/Resources` rather than duplicated.

## Build requirements

The release toolchain used on macOS is:

- Xcode with the iOS SDK, Swift 6.4.1, and the matching Swift Android SDK.
- Skip 1.9.16; dependency revisions are recorded in `Aria/Package.resolved`.
- JDK 21, Gradle 9.8.1, CMake and Ninja.
- Android SDK platform 36 and NDK 27.2.12479018 (r27c).
- Qt 6.11.1 for Android arm64-v8a and its matching macOS host tools.
- Git LFS for the shared MuseScore General SoundFont.

The app targets API 36, supports API 28+ (Android 9), and builds for `arm64-v8a`.
This is a macOS build recipe; Linux/Windows host builds have not been qualified.
No Android Studio project generation, signing passwords or store account is needed
for a local debug build. Install the SDKs/tools separately; their installed binaries
are not committed to this repository.

## Build a debug APK

From the repository root, fetch LFS resources:

```sh
git lfs pull
```

Set the installed SDK locations. The defaults below are also used by the native
scripts; the Gradle Qt Java dependency currently uses the same default Qt location.

```sh
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.2.12479018"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export QT_ANDROID="$HOME/Qt/android/6.11.1/android_arm64_v8a"
export QT_HOST="$HOME/Qt/android/6.11.1/macos"
```

Install the matching Swift Android SDK through Skip (`skip android sdk install`),
then run:

```sh
cd MuseReaderAndroid
scripts/link-ios-sources.sh
scripts/build-render-core.sh
scripts/build-engine.sh
cd Aria/Android
SKIP_COMMAND_OVERRIDE="$PWD/../../scripts/skip-arm64-only.sh" gradle :app:assembleDebug
gradle --stop
```

The APK is `Aria/.build/Android/app/outputs/apk/debug/app-debug.apk`, relative to
`MuseReaderAndroid/`. Debug builds include the SoundFont and use local debug signing.
Do not rebuild the native engine for routine Swift/Kotlin-only changes; reuse the
native outputs unless native sources or their dependencies changed.

Skip generates bridge/Kotlin build intermediates and the dependency version catalog
from the pinned packages. Generated files stay in the ignored build directories.
Keep `Package.resolved` and the vendored packages when reproducing a release; do not
replace the patched packages with unmodified upstream versions.

## Release builds

Create your own upload key/configuration using `scripts/setup-upload-key.py` when
needed. Signing credentials, keystores and machine-local SDK settings are excluded
from source control. A recipient builds with their own key; the publisher's key is
not required to compile or install a separately signed build.

Leave `ARIA_PHONE_AUDIT`, `ARIA_PERF_DIAGNOSTICS`, `ARIA_EDIT_AUDIT`,
`ARIA_VIDEO_AUDIT` and `ARIA_VIDEO_MAIN_BASELINE` unset. Local audit tooling and its
recordings are not part of the production source-release workflow.

From `Aria/Android`:

```sh
SKIP_COMMAND_OVERRIDE="$PWD/../../scripts/skip-arm64-only.sh" gradle :app:bundleRelease
gradle --stop
```

The AAB is `Aria/.build/Android/app/outputs/bundle/release/app-release.aab`.
Its SoundFont is exclusively in the install-time `soundbank` asset pack. To build
a local release APK with the bank included, use `:app:assembleRelease
-PariaSideloadApk` instead. Do not upload that sideload variant to Play.

`CURRENT_PROJECT_VERSION` in `Aria/Skip.env` identifies the Android build number.
`inspect-play-bundle.py` validates identity, signature, asset placement and native
16 KB alignment using an independently installed official bundletool JAR.

## Assets and local files

The source boundary follows the iOS project: application code, required app icons,
fonts, bundled score/template resources, licenses and build scripts are included.
The shared SoundFont is supplied through Git LFS. Optional video-background and
What's New/promotional media remain excluded by the existing iOS rules.

Store-listing/fastlane metadata, marketing screenshots, promo exports, audit
recordings/results, build outputs, private Git backups and credentials are not
part of this checkout. Required in-app artwork is retained; it is not a store
screenshot export. See the root `.gitignore` and this directory's `.gitignore`.
