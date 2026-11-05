# Lightweight source checks

Run `python3 MuseReaderiOS/Checks/check_fingering_navigation.py` to exercise the actual
fingering-entry action against a session double that regenerates selection render
data on every read. It checks four-note entry followed by empty bars, both score
boundaries, rest skipping, last-note replacement and erase/back navigation. It
compiles standalone Swift without Xcode or the native engine.

## Video export

Run `python3 MuseReaderiOS/Checks/check_video_export.py` from the repository root
to typecheck the production exporter against the iOS SDK. This does not invoke
Xcode, CMake, or the render-core build phase.

On an Apple Silicon Mac, add `--run` to compile a standalone Catalyst executable
and run a four-second synthetic export. It checks 1080p/30 fps, both A/V tracks,
duration, one audio request at a time, bounded prefetch, mix-only requests,
failure propagation, partial-file cleanup, cancellation, and layout restoration.
Metal/IOSurface and video encoder access are required. This is a correctness
check, not a performance benchmark. All generated outputs are temporary.

`--run` also checks the Piano style: MIDI note reading and timing, the keyboard
range, and a short export. Add `--piano-midi file.mid --piano-output dir` to draw
stills and a (silent) MP4 from a real score's playback MIDI, e.g. one written by
`build-aria-475-host/score_render_playback_export score.mscz out.mid`.

The stubs isolate the Swift writer/prefetch pipeline. Native PCM equivalence is
covered separately by `sandbox/engraving/tests/score_render_audio_mix_tests.cpp`,
which compares actual FluidSynth output with stems enabled and disabled.

Device UI and timing should be checked in Aria from Xcode on the intended iPad.
