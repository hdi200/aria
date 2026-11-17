# Open Source Release Compliance

Use this checklist for every public build of Aria.

## Source Release

- Publish the full corresponding source for the shipped binary.
- Include the exact `MuseReaderiOS` source, `sandbox/engraving`, bridge code, Xcode project, build scripts, and the MuseScore source snapshot used by the render-core build.
- For Android, also include `MuseReaderAndroid` application/integration sources, framework shims, native bridge/audio sources, Gradle/SwiftPM build inputs, dependency pins, and modified vendored packages with their licenses. See `MuseReaderAndroid/README.md` and `SOURCE_RELEASES.md` in that directory.
- Include build instructions with required Xcode, CMake, Ninja, Qt for iOS, and host Qt versions.
- Tag the source release with the same version/build number used for the public build.
- Record Android source snapshots by version code; the iOS and Android app version numbers are independent.
- Keep the GPLv3 license text and third-party notices in the release archive.

## App Bundle Notices

- Keep `Resources/Legal/GPL-3.0.txt` in the app bundle.
- Keep `Resources/Legal/THIRD_PARTY_NOTICES.md` in the app bundle.
- Keep dependency license files in `Resources/Legal`.
- Provide an in-app Open Source & Licenses screen that explains the GPLv3 status, no-warranty notice, and source availability.

## Release Hygiene

- Do not include `DerivedData`, `.DS_Store`, `xcuserdata`, or local build outputs in source releases.
- Do not move `sandbox/engraving` immediately before release; document it as the render-core source location instead.
- Verify create, edit, save, reopen, import, export, playback, and legal screen access on a device before tagging.

## ScoreScanner / ScannerCore release

Keep the app and ScannerCore package together in the existing
[hdi200/ScoreScanner](https://github.com/hdi200/ScoreScanner) repository.

- [x] Original scanner code has a GPLv3 LICENSE and third-party notices.
- [x] Scanner rest fix and synthetic tests are committed and tagged 0.1.19 locally.
- [x] Aria pins 0.1.19, revision `bdfb8cda1e604525ee139a9423ed2edc81390ecd`.
- [x] Aria's legal screen and bundled notices link to that exact scanner source tag.
- [x] Push the prepared scanner source and 0.1.19 tag after owner approval.
- [ ] Make the existing repository publicly readable and verify the tag without authentication.
- [x] Resolve Aria's normal remote package without a local override.
- [ ] Build the release and verify scanning and legal screen access on a device.
- [ ] Publish the matching Aria source tag for the app version/build being distributed.

Preserve Package.swift, ScannerCore and ONNX bridge sources, model files, tests,
model export/training scripts, dependency checksums, license texts and Vendor notices
at the exact source tag. Local scan data and private benchmark outputs stay excluded.
Do not ship until the remaining release gates above are complete.

Reference: [GPLv3 sections 1 and 6](https://www.gnu.org/licenses/gpl-3.0.html).
