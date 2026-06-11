# Open Source Release Compliance

Use this checklist for every public build of Aria.

## Source Release

- Publish the full corresponding source for the shipped binary.
- Include the exact `MuseReaderiOS` source, `sandbox/engraving`, bridge code, Xcode project, build scripts, and the MuseScore source snapshot used by the render-core build.
- Include build instructions with required Xcode, CMake, Ninja, Qt for iOS, and host Qt versions.
- Tag the source release with the same version/build number used for the public build.
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
