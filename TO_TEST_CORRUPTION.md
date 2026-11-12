# To test: scores with problems ("Open anyway")

Checks for the November 11 change that makes Aria open, play, edit and save scores with
problems the way desktop MuseScore 4.7 does after "Open anyway". Nothing below has been
built or run yet. Remove an item once it passes; log failures in
[MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md](MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md).

## What changed

- **Engine** (`sandbox/engraving`):
  - Incomplete measures and over-long voices no longer block playback, count-in, MIDI
    export or saving. Only a measure repeat group missing its repeat element still blocks
    playback (`blockDelayedSubsystemIfCorrupted` in `score_render_runtime.cpp`).
  - Saving is never blocked (`score_render_open_save.cpp`).
  - MuseScore 1.x files before 1.14 and 3.0-beta files open anyway, like MuseScore 5
    files already did (`loadScoreForRenderCore`).
- **Reader** (shared Swift, iOS and Android):
  - Scores with problems open with editing available, not locked in View mode.
  - The red "Fix score corruption" bar is now a notice: "This score has N problems", with
    the same menu (go to a problem, clear a bar) and an × to hide it.
  - The problem list refreshes after each edit.
  - Before Aria first writes over a score that opened with problems, the untouched
    original is copied to Aria Backups (once per open).
- **Import:** MusicXML with irregular bars now imports, because its conversion save is no
  longer blocked. The imported MusicXML file is copied to Aria Backups in that case.

## Builds first

- [ ] Rebuild the render core for iOS and Android (engine sources changed), then the apps.
- [ ] Run the compatibility checks in `sandbox/engraving/compat/README.md` (host build in
  `build-aria-475-host`) and compare the reports with the previous run, per AGENTS.md.

## Engine and files

- [ ] **Bad-file corpus.** Collect in `sandbox/engraving/compat/`: MusicXML that Aria
  used to refuse (Finale, Sibelius, Dorico, website exports), `.mscz` with an incomplete
  measure, a voice too long, a broken measure repeat, a MuseScore 1.x file before 1.14,
  and a 3.0-beta file.
- [ ] **Sweep.** For each file: opens, plays 10 seconds, loops a range, count-in plays,
  saves, reopens with the same problem list. The saved file loads in the desktop 4.7.6
  engine (host build) with the same problems.
- [ ] **Playback on broken bars.** Native tests that play, loop, count in and run a Tempo
  Ramp over each problem kind: no crash, hang or stuck playhead.
- [ ] **Broken measure repeat** still shows "Repair the broken measure repeat before …"
  for playback, and "Clear" in the menu fixes it.

## Reader (iPad, iPhone, Android)

- [ ] A score with problems opens normally; Edit works; the notice shows the count.
- [ ] × hides the notice for the rest of that open; reopening shows it again.
- [ ] Go to First Problem and each listed problem select the right bar.
- [ ] Fixing a bar by editing (adding the missing rest) shrinks the count; the notice
  disappears at zero.
- [ ] Opening and playing alone never writes the file (check its modification date).
- [ ] The first edit's autosave puts one untouched copy in Aria Backups; later saves add
  no more copies. The backup opens in desktop MuseScore and matches the original.
- [ ] Importing a refused MusicXML file now works; the imported file is in Aria Backups.
- [ ] A very old file (1.x before 1.14, or 3.0 beta) opens and saves as 4.70.

## Repairs that keep the music

The problems menu lists each problem ("Bar too long · Measure 14 · Staff 2") with Go to Bar
and its repairs. Engine: `fillLinkedTrackWithRests`, `trimLinkedTrackToMeasure` and
`fitMeasureTimeSignatureToContent` in `score_render_runtime.cpp`; command
`repairCorruptionIssue` (action 0 Clear, 1 Fill with Rests, 2 Trim to Fit, 3 Change Time
Signature). Like Clear, these write the bar directly and are not undoable.

- [ ] Problems are labelled "Bar too short" / "Bar too long" (voice 1), "Voice too long"
  (voices 2–4) and "Broken measure repeat".
- [ ] **Change Time Signature, bar too long** (5 beats in 4/4): the bar gets 5/4, the next
  bar shows 4/4 again, every note is kept, other staves get rests to fill 5/4, and parts
  show the same. Bars after it keep their positions; playback and the bar highlight stay
  in time. If the next bar already had a time signature, no extra 4/4 is added. If the
  original was common time, the restated one is common time.
- [ ] **Change Time Signature, bar too short** (3 beats in 4/4): the bar becomes 3/4, then
  4/4 is restated.
- [ ] **Change Time Signature, length not writable** (a triplet leftover such as 4/3):
  shows "This bar's length can't be written as a time signature…" and changes nothing.
- [ ] **Fill with Rests:** a short bar gets rests to the barline; the notes stay.
- [ ] **Trim to Fit, voice 1 and voices 2–4:** notes past the barline are removed; a note
  that crosses the barline becomes rests up to it; earlier notes stay. Ties and slurs into
  removed notes don't crash.
- [ ] After each repair the problem count drops, and the saved file opens in desktop
  MuseScore 4.7.6 without a corruption warning for that bar.
- [ ] Linked parts: repairing in the full score fixes the same bar in each part.
- [ ] The nested problem menus open on Android (Skip) as well as iOS.

## Not done yet (from the full plan)

- Fix all, and rebuilding a broken tuplet.
- Salvaging unreadable files (damaged zip, broken XML).
- A one-time notice at the first save; the backup note in the banner covers it for now.
