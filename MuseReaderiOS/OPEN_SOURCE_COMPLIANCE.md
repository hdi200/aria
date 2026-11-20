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

## Current prepared update — November 19, 2026

- Versions: iOS **7.7.0 (17)** and Android **1.4.0 (28)**.
- November 20: ScoreScanner's history was rewritten to move its standalone app out; every tag kept the same
  ScannerCore source under a new commit ID (0.1.23 is now `d22855b`; `d14c2a2` no longer exists). Source now pins
  **0.1.24** (`c474e9659ab9bdda51775cb647e58cb441c69a43`) with notices and legal links to match. The 7.7.0 (17) and
  1.4.0 (28) binaries below were built with 0.1.23 and show 0.1.23 links; build again before shipping 0.1.24.
- Later on November 20: source pins **0.1.25** (`fcf29bc3de4508adbd42b6b6412cd5ff31d0c31b`; a voice staff stays with
  its piano on tight-cropped and curled photos), with notices and legal links to match. Build again before shipping.
- [x] Both apps pin public ScannerCore **0.1.23**, revision `d14c2a2dbbda5c1e4aad98c1ba20dc51be5b5ce0`; anonymous tag resolution verified.
- [x] Normal remote package resolution succeeds for both platforms; no local scanner override.
- [x] ScannerCore unit tests: **167 tests in 19 suites pass**.
- [x] Bundled scanner notices and legal-screen source links point to 0.1.23.
- [x] New iOS archive/IPA and Android AAB built and structurally validated; model hashes and notices match 0.1.23.
- [x] iOS 7.7.0 (17) installed over existing iPhone/iPad apps, installed version queried and launch succeeded on both.
- [ ] Device legal-screen and full scanning/editing smoke checks on the new binaries; installation/launch is not that check.
- [ ] Matching Aria source tags published before distribution.

The owner authorized local commits, release builds, installation on their iPhone/iPad,
and store metadata drafts. **No pushes, binary/screenshot uploads, review submission
or publishing** are authorized in this preparation step. Earlier versioned evidence
below is historical and does not verify these new binaries.

## ScoreScanner / ScannerCore release

Keep the app and ScannerCore package together in the existing
[hdi200/ScoreScanner](https://github.com/hdi200/ScoreScanner) repository.

- [x] Original scanner code has a GPLv3 LICENSE and third-party notices.
- [x] Scanner rest fix and synthetic tests are committed and tagged 0.1.19 locally.
- [x] Aria pins 0.1.19, revision `bdfb8cda1e604525ee139a9423ed2edc81390ecd`.
- [x] Aria's legal screen and bundled notices link to that exact scanner source tag.
- [x] Push the prepared scanner source and 0.1.19 tag after owner approval.
- [x] Existing repository is public; anonymous tag check resolves 0.1.19 to `bdfb8cda1e604525ee139a9423ed2edc81390ecd`.
- [x] Resolve Aria's normal remote package without a local override.
- [x] Build local iOS 7.6.0 (16) and Android 1.3.0 (25) candidates; bundled notices/model checks pass.
- [x] Record scanning evidence: owner-reported iPhone smoke/first use; build-24 physical cloud Moto PDF open/save/reopen; final build-25 phone/tablet emulator checks.
- [ ] Verify legal screen access on the release device; bundle checks do not establish this UI check.
- [ ] Publish the matching Aria source tag for the app version/build being distributed.

Preserve Package.swift, ScannerCore and ONNX bridge sources, model files, tests,
model export/training scripts, dependency checksums, license texts and Vendor notices
at the exact source tag. Local scan data and private benchmark outputs stay excluded.
Do not ship until the remaining release gates above are complete.

November 18 handoff: the exported iOS 7.6.0 (16) IPA has the ONNX packaging correction
but does not contain the later native editing crash fixes rebuilt into Android 25.
Matching Aria source publication remains pending. Owner-handled Play state was not
rechecked after the instruction to stop Chrome. Local detailed evidence and remaining
checks are in `promo/scan-import/RELEASE_STATUS.md` at the repository root.

Reference: [GPLv3 sections 1 and 6](https://www.gnu.org/licenses/gpl-3.0.html).
