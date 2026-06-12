# Third-Party Notices

Aria includes code and assets from the MuseScore Studio source tree and several third-party projects. This file is a release-facing notice summary; keep the original license files with the source release and in the app bundle.

## MuseScore Studio

- Component: MuseScore Studio notation, engraving, MusicXML, playback, and render-core-derived code.
- Location: parent MuseScore source tree, `sandbox/engraving`, and the iOS bridge.
- License: GNU General Public License version 3.
- Copyright: MuseScore Limited and contributors.
- Notice: Aria includes GPLv3-covered MuseScore-derived code. Preserve the GPLv3 license text, notices, and corresponding source availability for public builds.

## FluidSynth

- Component: SoundFont synthesis code used by the render core.
- Location: `src/framework/audio/thirdparty/fluidsynth`.
- License: GNU Lesser General Public License version 2.1.

## FreeType

- Component: Font rendering.
- Location: `src/framework/draw/thirdparty/freetype`.
- License: FreeType License or GPL-compatible option, as described in `FreeType-LICENSE.txt`.

## Opus

- Component: Audio codec support present in the MuseScore audio third-party tree.
- Location: `src/framework/audio/thirdparty/opus`.
- License: BSD-style Opus license.

## Bravura

- Component: BravuraText notation font.
- Location: `MuseReaderiOS/MuseReaderiOS/Resources/Fonts/BravuraText.otf`.
- License: SIL Open Font License 1.1.
- Reserved font name: Bravura.

## MuseScore General SoundFonts

- Components: `MuseScore_General.sf2`, `MuseScore_General.sf3`, and `MS Basic.sf3`.
- Location: `MuseReaderiOS/MuseReaderiOS/Resources`.
- Notice embedded in the SoundFont metadata: MuseScore General is by Frank Wen, Michael Cowgill, and S. Christian Collins and is released under the MIT license.
- Bundled license files: `MuseScore_General-License.md` and `MuseScore_General_HQ-License.md`.

## Score Templates

- Component: bundled MuseScore score templates and template settings.
- Location: `MuseReaderiOS/MuseReaderiOS/Resources/ScoreTemplates.bundle`.
- License: distributed as part of the MuseScore Studio GPLv3 source tree unless a more specific upstream license applies to an individual file.

## Qt

- Component: Qt libraries and tools used to build and run the render core.
- License: depends on the Qt license used for the release build.
- Release requirement: preserve and publish the applicable Qt license/commercial notices for the exact Qt distribution used to build the app.
