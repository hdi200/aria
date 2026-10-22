# Android dependency and source notes

Aria's MuseScore-derived application and engine are distributed with the root
[GPLv3 license](../LICENSE.txt). Existing font, SoundFont, Qt, FluidSynth and other
engine notices are in [the shared notices](../MuseReaderiOS/THIRD_PARTY_NOTICES.md)
and `MuseReaderiOS/MuseReaderiOS/Resources/Legal/`. Original dependency licenses
remain in their source directories; this document does not replace them.

## Patched dependencies included here

| Package | Upstream version / revision | License file | Changes |
| --- | --- | --- | --- |
| skip-ui | 1.63.0 / `fa339f6001bde88f02fbfd76417b805acd73b0aa` | [MPL-2.0](Aria/Vendor/skip-ui/LICENSE.txt) | [Aria patches](Aria/Vendor/skip-ui/ARIA_PATCHES.md) |
| skip-fuse-ui | 1.19.0 / `36479f246560f72c64af30fc8e8927c84550f70c` | [MPL-2.0](Aria/Vendor/skip-fuse-ui/LICENSE.txt) | [Aria patches](Aria/Vendor/skip-fuse-ui/ARIA_PATCHES.md) |
| swift-jni | 0.5.1 / `71385f88cfff14409fe105e27fcad3ebd44348d0` | [Apache-2.0](Aria/Vendor/swift-jni/LICENSE.txt) | [Aria patches](Aria/Vendor/swift-jni/ARIA_PATCHES.md) |

Retain the upstream copyright/license headers and Aria patch markers. The local
SwiftPM path dependencies select these modified sources rather than substituting
upstream binaries.

## Other build dependencies

- `Aria/Package.resolved` records public repository URLs and exact revisions for
  Skip, Skip Bridge, Skip Android Bridge, Skip Foundation, Skip Fuse, Skip Lib,
  Skip Model, Skip Unit and Swift Android Native. Obtain unmodified sources at
  those pinned revisions; no dependency upgrade is part of this publication.
- The shared engine sources include MuseScore Studio 4.7.5 and FluidSynth 2.3.3.
  Engine provenance and modifications are in `sandbox/engraving/compat/ENGINE.md`.
- Qt 6.11.1 Android/host SDKs are installed separately. Qt source and license
  information is available from [Qt's source repositories](https://code.qt.io/cgit/)
  and [Qt licensing](https://www.qt.io/licensing). Use the matching 6.11.1 sources
  and the applicable module licenses when obtaining or redistributing Qt.
- Google Play Billing 8.0.0 and Play In-App Review 2.0.2, AndroidX/Compose and Kotlin
  dependencies are resolved by Gradle from their declared public repositories.
- Generated Material icon assets use Google's Material Design icons. The
  generator records their upstream location; the icons use Apache-2.0.
- Android SDK/NDK, Swift, JDK, Gradle, CMake, Ninja and Skip's compiler/plugin tools
  are separately installed build tools. Installed SDKs, caches and tool binaries
  are not committed as application source.

This inventory describes the published inputs. It is not a legal determination
about every third-party distribution obligation or the terms of a store release.
