# Playback MIDI comparison

This compares Aria's playback MIDI export API with MIDI exported by MuseScore
Studio 4.7.5 from the same score. Aria's in-app playback renders audio through
a separate path, so this does **not** compare what users hear or the soundfonts.
By default both programs receive a score first saved by
4.7.5, keeping older file-reader differences out of the playback result.

Build `score_render_playback_export` from the host engraving build, then run a
focused check:

```sh
python3 sandbox/engraving/compat/playback_sweep.py \
  vtest/scores/tempoText-1.mscz vtest/scores/dynamics-11.mscz \
  vtest/scores/volta-1.mscz --out /tmp/aria-playback-focused
```

For the normal 892-score corpus, omit the score paths and choose a new output
directory. `--direct` compares exports of the original files, including older
MuseScore formats. `--jobs 4` controls both MuseScore and Aria worker counts.
The output directory must not exist; it contains both MIDI files, `results.json`,
and `report.md`.

The comparator parses Standard MIDI Files without external Python packages. It
compares note pitch and count, note starts and durations in beats and in elapsed
microseconds (2 ms tolerance), tempo events, note velocities, instrument program
changes, controllers, pitch bends, and the grouping of notes into tracks. It
ignores track names, track numbering, MIDI channel numbering, and raw event
packing. Separate difference categories help distinguish wrong tempo from wrong
notes and wrong loudness.

MuseScore's command-line MIDI exporter currently emits a standard five-message
RPN pitch-bend-range setup when its “Export RPNs” setting is enabled. Aria's
playback export calls the engine with that option disabled. The comparison
records this exact sequence as an `export-rpn-option` warning and checks all
other controllers normally. It does not suppress other RPN or data-entry
messages. If either MIDI file contains pitch bends, the missing setup becomes
an `rpn-bend-risk` difference because a synthesizer may bend those notes by a
different interval.

Current limits: only PPQ time division and MIDI formats 0 and 1 are supported.
Unmatched note-on or note-off events are compared separately; these can occur
in MuseScore's own MIDI for some glissando scores. MuseScore also emits
nonstandard five-byte delta times in two guitar-bend fixtures; the parser
accepts and flags them.
The comparison does not interpret the audio produced by a synthesizer, and a
MIDI match does not prove identical timbre or balance on the iPad.
