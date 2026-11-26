# Handoff: Aria scanning release

## ScannerCore 0.1.26 — November 21, 2026, night

ScoreScanner tagged **0.1.26** (`28b7315`, pushed). Aria `3d4a8bbe00` pins it on iOS and Android, with the
notices, legal screen and `OPEN_SOURCE_COMPLIANCE.md` to match; the Android package resolves 0.1.26 from GitHub.
Pushed Nov 21 together with `af056d89bc` (engine move to MuseScore 4.7.7). The phone
build below predates both; rebuild from `main` to test the Matrix and "Singin' in the Bathtub" (no local override).

## Phone test build — November 21, 2026, night (not a release)

Aria 7.7.0 (17) on Jack's iPhone was built and installed from a temporary workspace (scratch only) that overrides
ScannerCore with a local copy of the ScoreScanner working tree: committed `752bf4c` (curled phone photos) and
`bb5f4cd` (chord names on guitar diagrams), plus uncommitted join and writer fixes from "Morning Has Broken". That
uncommitted state still had a Matrix regression (4 overfull bars at instruments that join later), fixed since but
not yet in the phone build: rebuild after ScoreScanner's regression passes. Aria's own files and pins are
unchanged (still 0.1.25); nothing pushed or tagged. `download.onnxruntime.ai` served a wrong-host certificate, so
the build used the checksum-verified ONNX Runtime from ScoreScanner's `.build/artifacts` through a scratch package
copy; when releasing, resolve from the real URL again.

## ScannerCore 0.1.25 — November 20, 2026, evening

- Aria `main` pins public **ScannerCore 0.1.25** (`fcf29bc3de4508adbd42b6b6412cd5ff31d0c31b`) on iOS and Android,
  with the legal screen, `ScoreScanner-NOTICE.txt` and both `THIRD_PARTY_NOTICES.md` pointing at `tree/0.1.25`.
  Commit **099d3721c4**, pushed. Both apps resolved 0.1.25 from GitHub (`swift package resolve`,
  `xcodebuild -resolvePackageDependencies`); no Aria build was run.
- 0.1.25 keeps a voice staff with its piano on tight-cropped and curled photos of piano-vocal-guitar pages; its
  regression is otherwise identical to 0.1.24. Next on those pages: guitar chord grids (ScoreScanner's
  `tools/chordfind/REMAINING_ISSUES.md`).
- The validated 7.7.0 (17) / 1.4.0 (28) artifacts still contain 0.1.23: build again from `099d3721c4` before
  submitting, then scan the hymn and a songbook page on the phone. Nothing uploaded or submitted.

## ScannerCore 0.1.24 and the ScoreScanner split — November 20, 2026

- Aria `main` now pins public **ScannerCore 0.1.24** (`c474e9659ab9bdda51775cb647e58cb441c69a43`) on iOS and
  Android, with the legal screen, `ScoreScanner-NOTICE.txt` and both `THIRD_PARTY_NOTICES.md` pointing at
  `tree/0.1.24`. Commit **bf94df5b90**, pushed to `hdi200/aria` (`ce89f6c467` and `608165232d` were already on
  `origin/main`, despite the notes below saying local only). Both apps resolved 0.1.24 from GitHub; no Aria build or
  typecheck was run for this two-string legal-screen change.
- 0.1.24 reads a hymn's deeper verses, drops staff text that repeats a lyric line, and reads "D7/4" as D7sus4.
- ScoreScanner's standalone app moved to a private repository, and `hdi200/ScoreScanner`'s history was rewritten
  without it. Every tag kept the same ScannerCore source under a new commit ID: 0.1.23 is now `d22855b`, and
  `d14c2a2` (pinned by `ce89f6c467`) no longer exists, so that older Aria commit no longer resolves from a clean clone.
- **The validated iOS 7.7.0 (17) and Android 1.4.0 (28) artifacts below contain 0.1.23** and show 0.1.23 links.
  Build again from `bf94df5b90` before submitting, then scan the hymn on the phone. If the existing artifacts are
  shipped instead, publish their source pinned to the new 0.1.23 (`d22855b`), not `bf94df5b90`.
- Nothing was uploaded or submitted to either store.

## Current prepared update — November 19, 2026

Source committed locally as **ce89f6c467**. Both apps now resolve public
**ScannerCore 0.1.23** (`d14c2a2dbbda5c1e4aad98c1ba20dc51be5b5ce0`).
**iOS 7.7.0 (17)** archive/IPA and **Android 1.4.0 (28)** AAB are built and
validated. The new iOS build includes the native editing crash fixes and the loop
highlight/beta-badge follow-ups; it was installed and launched successfully on both
the owner's iPhone and iPad, with installed version/build confirmed.

Use the [new artifact index](promo/scan-import/release/nov19/README.md) and its `RELEASE_RECORD.json` for files,
hashes, exact source, checks and remaining runtime scope. Scanner 167 tests and
reader interaction checks pass. Android new-build runtime and physical iOS
scanning/gesture checks were not performed by this agent.

App Store **7.7.0** and Play draft **22 / 28 (1.4.0)** metadata/notes are saved.
The owner explicitly authorized this draft preparation, superseding the older
stop-Chrome instruction for this step. **No pushes, binary/screenshot uploads, review
submissions or publishing.** Matching Aria source publication remains pending.

All build-25 / pin-0.1.19 / iOS-IPA-lacks-crash-fixes statements below describe
earlier artifacts; this summary supersedes them for the new November 19 update.

## November 19 iOS source follow-up — loop highlighting

Fixed the iOS simultaneous page-swipe handler consuming the loop-highlight drag at
finger release. A pending playback selection now cancels that swipe, even before
bar geometry finishes loading. Production interaction checks and full iOS typecheck
pass (0 errors, unchanged 72 warnings); physical gesture verification remains pending
in `TO_TEST.md` / BUG-031. This source change is not in the previously exported IPA
or Android artifacts below. No Xcode/native rebuild, store action, commit or push.

Updated November 18, 2026. Start here, then read [RELEASE_STATUS.md](promo/scan-import/RELEASE_STATUS.md) for the consolidated release record. This handoff contains local paths; do not commit it. The [November 15 handoff](promo/scan-import/release/handoffs/HANDOFF-SCAN-2026-11-15.md) is historical, including its old versions and pending tasks.

## Current state

- Workspace: `/Users/jackgruber/Developer/MuseScore-master`, public source `hdi200/aria`. Scanner package: `/Users/jackgruber/Developer/ScoreScanner`, public `hdi200/ScoreScanner`.
- Both platforms scan PDFs and photos. Android build **1.3.0 (25)** also has Google's multi-page document camera: capture/review/crop/rotate → one PDF → Aria's existing recognition pipeline. iOS uses VisionKit.
- Both pin ScannerCore **0.1.19**, revision `bdfb8cda1e604525ee139a9423ed2edc81390ecd`. Anonymous public tag access passed. Recognition uses the bundled copisteria and PaddleOCR models on device; Aria does not use Apple's cloud model. Google's Android camera component may need a first-use download.
- Android build 25 includes the Photo picker fix, stable beta-notice sizing using the metronome/mixer pattern, camera icon and document camera, R8 registrar constructor retention, and the two editing crash fixes below.
- Jack says Play is handled and explicitly stopped Chrome work. Do not reopen Console or upload/submit anything. Last agent action was saving draft 19, named `25 (1.3.0)`, with the exact live build-24 notes. No agent binary/screenshot upload or review submission. Subsequent owner-handled state was not independently checked.

## Files to use

All artifact paths below are relative to `promo/scan-import/`.

| Purpose | File |
| --- | --- |
| Play bundle | `release/android/Aria-1.3.0-25-camera-crash-fixes.aab` |
| Emulator test only, never upload | `release/android/Aria-1.3.0-25-camera-crash-fixes-emulator-test.apk` |
| Corrected iOS 7.6.0 (16) upload IPA | `release/ios/export-7.6.0-16-onnx-fix/Aria.ipa` |
| Exact hashes, source deltas and test evidence | `release/source-build-record.json` |
| Copied Play release notes | `release/store-pages/play-release-notes-build25.txt` |

AAB SHA-256: `6ce7bdda7552a2148f007f4ae96927bee00ce925c60559f6367a1f77c853cc7e` (345,468,044 bytes). The initial camera-25 bundle failed R8 runtime startup and was removed; use only the final bundle above. Build 24 is historical.

The corrected iOS IPA fixes Apple 90208 (ONNX framework minimum-OS plist mismatch). It **does not include the subsequent native editing crash fixes**; these shared sources reach iOS only after a native rebuild and new archive. Corrected Apple upload/processing state has not been independently rechecked.

## Fixes and verification

- Missing InteractiveProvider: return Cancel with a diagnostic instead of crashing on invalid tuplet warnings. Rejected tuplets roll back the entire command, including earlier selected items.
- Keyboard replacement: validate written/sounding MIDI range and TPC; check the returned element is a real nonempty Chord before `upNote`. Written MIDI 1 on a B-flat staff reproduced the production-offset crash before the fix. The original user's exact score is unknown. Historical build-12 `ldata` remains unattributed; build-21 bootstrap was already fixed in 22+.
- Both old native crash routes reproduced; all three focused regressions and full host **10/10** pass. Roundtrip default/direct, playback, layout and MusicXML have zero changed per-score results; layout **842/842 pixel-identical**. Evidence: `release/crash-audit/AUDIT.md`.
- Final exact-AAB derivative on the 16 KB Pixel emulator: camera shutter/review/crop/cancel/reopen; two SDK-gallery music pages → one PDF → one two-page score; playback/save/reopen. First Google component download failed once, retry succeeded. A sideways page required rotation before recognition. Physical camera quality remains untested. Evidence: `release/device-checks/ANDROID_CAMERA25_RESULTS.json`.
- Same APK on the 16 KB Medium_Tablet: four-page PDF → one score, two-page display, playback highlight, keyboard edit/Undo, playback after Undo, save/full restart/reopen. Temporary 2880×1620 capture display restored to 2560×1600/320 dpi. Last observed tablet left open with the saved score; recheck live emulator state before relying on it. Evidence: `release/device-checks/ANDROID_TABLET25_RESULTS.json`.
- Earlier build 24 on Google's physical 4 GB Moto G Play: 12-page `Scans.pdf` recognized, opened, saved and reopened without the old import crash. Recognition accuracy was not graded; sampled 895.5 MiB PSS is not a whole-run peak. Reservation and uploaded fixtures were cleaned up. Evidence: `release/device-checks/RUNTIME_RESULTS.json`.
- iOS source typecheck: 0 errors, unchanged 72 warnings. Corrected iPhone Simulator candidate passed voices, reorder/save/restart/Undo and measured screen-awake lifecycle. Owner confirmed scanning/first-use on iPhone. These do not establish physical iPad, stylus or billing checks.

## Screenshots and Reddit

- iPhone/iPad: `app-store-scanning/Aria-scanning-App-Store-iphone.zip` (12 PNGs) and `Aria-scanning-App-Store-ipad.zip` (6 PNGs, 2064×2752 and 2048×2732). Authentic earlier 7.4.1 (15)/Scanner 0.1.18 promo captures, not new release proof. README documents provenance and recognition limitations.
- Android phone: `google-play-scanning/Aria-scanning-Google-Play-phone.zip`, three styled 1080×1920 images from build-24 captures.
- Android tablets: `google-play-scanning/Aria-scanning-Google-Play-tablet-7.zip` and `...tablet-10.zip` each hold four genuine 16:9 UI images. Optional matching abstract/styled `...tablet-7-styled.zip` and `...tablet-10-styled.zip` each hold three 16:10 slides. Same tablet-emulator session, not two physical devices. See `google-play-scanning/TABLETS.md` and `TABLET_QA.md`.
- All 14 tablet PNGs and five tablet/source ZIPs passed dimension/RGB/hash/CRC checks and contact-sheet review. Editable sources and original captures are retained. No agent screenshot upload.
- Current Reddit copy: `REDDIT_POST_READY.md`. Latest requested artwork: **`Aria-reddit-4x5-app-store-background.png`**, 1080×1350 RGB; phone preview `Aria-reddit-4x5-app-store-background-preview-390px.png`. Keeps the original design with the App Store ivory/lavender background. Original wide and alternative portraits remain. See `REDDIT_MOBILE_IMAGE.md`. No agent Reddit post submitted.
- Screenshot editors can be started on loopback ports 3018 (iOS) and 3028 (Android); process availability is not guaranteed across sessions. Use each README's commands.

## Remaining work and boundaries

- Matching Aria release source commits/tags/publication remain pending; no commits or pushes performed in this follow-up. Do not imply a baseline commit alone reproduces the local release delta. Exact patches/provenance are in the release record.
- Physical Android camera quality, physical iPad/stylus, specified scanner accuracy fixtures and billing/account checks remain unrun. Keep those distinct from completed emulator/owner-reported passes. [TO_TEST.md](TO_TEST.md) retains specific cases; general scanner phone smoke passes do not prove every fixture.
- MuseScore **4.7.7** was researched only. Useful possible maintenance: split plucked double bass/acoustic bass guitar definitions and euphonium low-range correction. Nothing was imported or rebuilt. Engine remains **4.7.6 plus Aria patches**, file format 4.70; no upstream-main merge. See `sandbox/engraving/compat/ENGINE.md`.
- Read `ONBOARDING.md` and root/Android `AGENTS.md` before code changes. Do not perform routine Xcode/native builds for docs or Swift-only changes, and never clean cached native outputs. Engine changes require the documented compatibility checks.
- One Android emulator at a time; stop Gradle before starting it. Never clear/uninstall owner score libraries, especially `app.aria.skipspike`. Test only cleared/authorized music; private diagnostic captures are not marketing assets.
- Commit/push only when Jack asks. No store work after the explicit stop instruction. Support copy is first person, signed Jack.
