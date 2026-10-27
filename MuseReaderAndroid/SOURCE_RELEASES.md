# Android source releases

The public source includes the Android application, Swift shims, Kotlin integration,
C++ bridge/audio code, shared iOS sources, MuseScore-derived engine, build scripts,
pinned SwiftPM dependencies and the modified vendored packages with their licenses.
Source snapshots exclude the same local/marketing material as iOS; see README.md.

## Release snapshots

| Source tag | Android build | Shared application baseline | Upload AAB SHA-256 |
| --- | --- | --- | --- |
| `android-1.0.0-5` | 1.0.0 (5), observed live before this publication | `b2973a5685` | `5964dec98cd5dc10c2cffb41aec1821558b3079023ab5774ae34f9473e83f04f` |
| `android-1.0.0-6` | 1.0.0 (6), submitted for review October 22, 2026 | `b685c0eece` | `05f1a263ed1c053adca8b41c9436561d818b669328312ad6f298095984d63cdd` |
| `android-1.0.0-7` | 1.0.0 (7), submitted for review October 27, 2026 | `7b657ade53` | `c4ac2a9e2a575038e721bf85f2c43c4946ffa4ca1194b428396b7fd49cdda445` |

Both use the same Android production implementation and pinned dependencies;
version 6 adds the shared instrument-catalog and library-confirmation fixes and
increments the Android build number. Version 7 adds crash fixes in the shared engine
(FluidSynth locking, cloned-score file info), the vendored skip-ui padding patch and the
Android saved-state trim. Documentation/source packaging was added
when publishing these snapshots. The old private repository's audit history and
local notes are not imported into public Git history.

For a release checkout:

```sh
git clone https://github.com/hdi200/aria.git
cd aria
git checkout android-1.0.0-6
git lfs pull
```

Use [the Android build recipe](README.md). The root repository also includes the
shared GPL-covered engine and iOS sources referenced by Android symlinks. Git LFS
is required to retrieve the actual shared SoundFont, rather than its text pointer.

## Reproduction limits

The snapshots provide modifiable application and integration source and a documented
build recipe. They do not include signing keys, installed SDK/compiler binaries,
store metadata, private benchmark results, optional promotional media, or compiled
APKs/AABs. A separately signed rebuild is not claimed to be byte-identical to the
publisher-signed Play artifact. Exact external dependency versions/licenses remain
relevant when rebuilding or redistributing them; see THIRD_PARTY_NOTICES.md.

The in-app Open Source screen already links to this public repository. This source
publication makes the Android integration available at that location; it does not
change an app binary or trigger a Play rollout. For future Android releases, update
the versioned source snapshot together with the release record.
