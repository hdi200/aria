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

- Component: `MuseScore_General.sf2` (MuseScore_General v0.2).
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

## ScoreScanner / ScannerCore

- Component: ScoreScanner's ScannerCore Swift package, version 0.1.24, used for sheet-music scanning.
- Source and exact release: https://github.com/hdi200/ScoreScanner/tree/0.1.24
- License: GNU General Public License version 3 for original code, copyright 2026 Jack Gruber. Third-party code and model assets retain their original licenses below.
- Source release includes the Swift reader, ONNX model assets, tests, package manifest, model training/export scripts and vendor provenance. Keep the tag publicly available for the shipped build.
- Bundled notice: `Resources/Legal/ScoreScanner-NOTICE.txt`; license text: `Resources/Legal/GPL-3.0.txt`.

## copisteria and copista-2m (score scanning)

- Component: KobiMusic's copisteria optical music reader and its copista-2m models, ported to Swift in the ScoreScanner package (`ScannerCore`), used by Aria's Scan.
- Source: https://github.com/kobimusic/copisteria
- License: Apache License 2.0. Copyright 2026 KobiMusic.
- Bundled files: `Resources/Legal/copisteria-Apache-2.0.txt` and `Resources/Legal/copisteria-NOTICE.txt` (the NOTICE asks that KobiMusic be credited and the repository linked).

## PaddleOCR PP-OCRv6 (score scanning, chord names and page text)

- Component: PaddleOCR's PP-OCRv6 small text recognition model, fine-tuned on chord symbols and exported to ONNX in the ScoreScanner package (`ScannerCore`, `chord_rec.onnx`), used by Aria's Scan to read chord names.
- Source: https://github.com/PaddlePaddle/PaddleOCR
- Component, text: the same model as released (unmodified weights), exported to ONNX (`text_rec.onnx`), reads the title, composer, tempo and staff text.
- License: Apache License 2.0. Copyright PaddlePaddle Authors. The chord reader's weights are a modified version (trained further on synthetic chord-symbol images).
- Bundled files: `Resources/Legal/copisteria-Apache-2.0.txt` (the Apache License 2.0 text) and `Resources/Legal/PaddleOCR-NOTICE.txt`.

## ONNX Runtime (score scanning)

- Component: ONNX Runtime 1.27.0 (Microsoft's official iOS binary and Objective-C bindings), which runs the copista-2m models and the chord reader.
- Source: https://github.com/microsoft/onnxruntime
- License: MIT License. Copyright (c) Microsoft Corporation.
- Bundled file: `Resources/Legal/ONNXRuntime-MIT.txt`.

