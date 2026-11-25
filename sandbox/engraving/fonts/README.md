# Stand-in text fonts

Desktop MuseScore draws text in any font installed on the computer. Phones lack many of
those (Android has no Arial or Times New Roman; iOS has no Arial Black or Calibri), so Aria
bundles open-licensed fonts drawn to the same measurements and asks Qt to use them only when
the score's font is not on the device (`registerStandInFonts` in `score_render_runtime.cpp`).
The font name saved in the score never changes, so desktop still shows the original.

| Stand-in | Used for | Version and source | License |
| --- | --- | --- | --- |
| Liberation Sans, Serif, Mono | Arial / Helvetica, Times New Roman / Times, Courier New / Courier | 2.1.5, `liberation-fonts-ttf-2.1.5.tar.gz` from github.com/liberationfonts/liberation-fonts | SIL OFL 1.1 (`liberation/LICENSE`) |
| Carlito | Calibri | google/fonts `ofl/carlito`, November 2026 | SIL OFL 1.1 (`carlito/OFL.txt`) |
| Caladea | Cambria | google/fonts `ofl/caladea`, November 2026 | SIL OFL 1.1 (`caladea/OFL.txt`) |
| Archivo Black | Arial Black (similar look, not identical measurements) | google/fonts `ofl/archivoblack`, November 2026 | SIL OFL 1.1 (`archivoblack/OFL.txt`) |

The files are unmodified; `SHA256SUMS` records them. Keep each license with its font and list
every font in the third-party notices of both apps.
