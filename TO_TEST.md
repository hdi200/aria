# To test

Remaining device checks. Remove an item once it passes. Confirmed failures are tracked in
[MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md](MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md).

## Playback & Practice

- [ ] **Listen at 50% and 150%.** Pitch should sound unchanged. The render-core test
  already verifies identical sounding MIDI pitches and scaled timing across a tempo change.
- [ ] **Metronome at 70%.** Listen for clicks aligned with the slower beat.
- [ ] **Tempo Ramp every 2 repeats.** Set 70% to 100% with +5% every 2 repeats.
  Check that the sheet shows loop 13 and an estimated time. Listen for two passes at
  each speed before the inincrease, with loop 13 starting at 100%.
