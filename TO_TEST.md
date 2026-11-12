# To test

Remaining device checks. Remove an item once it passes. Confirmed failures are tracked in
[MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md](MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md).

## Time signatures

- [ ] **Same time signature again.** In a 4/4 score, select a later bar and add 4/4: it
  is added (a restatement). Add common time after 4/4, and 4/4 after common time: both
  are added. The file opens the same in desktop MuseScore.

## Tempo as BPM

- [ ] **Playback & Practice:** under the percentage, the BPM shows the written tempo ×
  speed (120 BPM score at 70% → 84 BPM) and follows the slider while dragging. With a loop
  it uses the loop's first bar; otherwise the bar at the playback position. After editing
  a tempo marking, reopening the panel shows the new BPM. Scores with no tempo marking show
  desktop's default (120 BPM).
- [ ] **100% snap (device only, the simulator has no haptics):** dragging the Practice speed
  slider near 100% (96–104%) snaps to 100% with one firm tap; dragging through again taps
  again; other values still move in 5% steps. Android too.
- [ ] **Tempo Ramp:** the summary reads "84 → 120 BPM over about 1 min 14 sec" (start
  and target BPM); with no known tempo it falls back to "Reaches 100% in about …".
- [ ] **Android ramp summary arrow:** the arrow between the two BPM numbers sits centred on
  the text, not low (drawn as the arrow.right icon on Android).
- [ ] **Android:** both sheets keep a steady height with the extra line.

## Tempo Ramp

- [ ] **No gap between speeds (iOS and Android).** Start a ramp, for example 70% to 100%,
  +5% every loop. Each new pass should follow straight on at the new speed, with no stop,
  pause or cut-off. The pill's loop number and speed, and the bar highlight, should change
  as the new pass starts. Also try a short loop of about one bar.
- [ ] **Pause, Stop and seek during a gap-free ramp.** Pause just before the loop end and
  resume. Stop, then Play. Scrub inside the loop. The speed should continue from the pass
  you heard, and the highlight should stay on the right bar.
- [ ] **Ordinary loops and playback unchanged.** Plain looping with no ramp, and normal
  playback, should sound and highlight as before.
- [ ] **Restart timeout.** Force a playback action to stay busy for at least 10 seconds
  during a ramp restart. The ramp should end, restore the previous speed and allow count-in
  on the next Play. Normal Start Ramp after Play and count-in after Stop passed on iPad.
- [ ] **Seek inside the loop.** On iPhone Duo, scrub backwards within a running ramp.
  The loop count should stay the same.
- [ ] **Practice speed 110%:** open Tempo Ramp: Start Ramp is enabled (target 115%).
- [ ] **Scrub near the end.** On iPhone Duo, scrub from the loop's last bar to its first,
  then seek to the last quarter while looping. The loop count should stay the same.
  The second case failed in a focused Swift check (BUG-018).

## Playback & Practice

- [ ] **Listen at 50% and 150%.** Pitch should sound unchanged. The render-core test
  already verifies identical sounding MIDI pitches and scaled timing across a tempo change.
- [ ] **Metronome at 70%.** Listen for clicks aligned with the slower beat.
- [ ] **Tempo Ramp every 2 repeats.** Set 70% to 100% with +5% every 2 repeats.
  Check that the sheet shows the estimated time to reach 100%. Listen for two passes
  at each speed before the increase, with loop 13 starting at 100%.
