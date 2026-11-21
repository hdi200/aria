# To test

Remaining device checks. Remove an item once it passes. Confirmed failures are tracked in
[MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md](MuseReaderiOS/FEATURE_REQUESTS_AND_BUGS.md).

November 18 release handoff: [current results](promo/scan-import/RELEASE_STATUS.md).
Both platforms pin ScannerCore 0.1.19. Version labels below identify when a fixture
was added, not the current pin. Owner-reported general iPhone scanning/first use,
iPhone Simulator editing/playback, build-24 cloud 12-page open/save/reopen and
build-25 phone/tablet emulator tests passed. Those passes do not establish every
individual fixture below. Physical Android camera quality, physical iPad/stylus,
release legal-screen access and billing/account checks remain unverified.


## MuseScore 4.7.7 engine (November 21)

- [ ] **New Score → Big Band** (and Jazz Combo, Bluegrass Band): enter bass notes and play.
  The bass is a plucked double bass, not silent and not a piano.
- [ ] **Add instrument:** Double Bass (plucked) and Acoustic Bass Guitar are in the list and play.
- [ ] **Euphonium:** B♭1 is not marked out of range.
- [ ] **Save** a score and open it in desktop MuseScore 4.7.6: no warning.
- [ ] **Android:** launch the build with the new `libaria_engine.so`, open a score, play and save.

Host checks against desktop 4.7.6 are unchanged on every score (IOS_CHANGES #134).

## iOS loop-highlight release (November 19, BUG-031)

Owner confirmed the fix on iPad (November 21). One check remains:

- [ ] On iPhone, in View mode, hold a bar at a page edge, drag across bars and lift off:
  the page doesn't turn, and normal page swipes still work after dismissing the selection.

## Scanned tuplets (ScannerCore 0.1.17)

- [ ] **Fresh scan of Indian Summer:** bars 4 and 18 retain their triplets; a missed note's time is an invisible rest.
- [ ] **Fresh scan of sheet026:** bar 28 stays plain eighths E E.
- [ ] **Fresh scan of Chopin Fantaisie-Impromptu:** playback improves without missing recognised notes. Desktop validation: 17 to 5 stretched bars out of 70; five problem bars remain.
- [ ] **Open and play another scanned lead sheet:** no new import or playback regression.

Historical 0.1.17 validation: 116 tests passed; 720 outputs compared, no notes/bars lost and no file worse on stretched bars. Release 0.1.19 later passed 157 unit tests. Bridge's misread duplets remain unresolved. These specific phone fixtures are still pending.

## Share to Aria and ScoreScanner (needs a device build)

- [ ] **Photos → Share → Aria** with a picture of a lead sheet: Aria opens on its own and scans it.
  If it only says "Saved. Open Aria to scan it.", open Aria: the scan starts. (Passed in the
  simulator.)
- [ ] **Files → a PDF → Share → Aria**, and **Mail/Safari PDF → Share → Aria**: the PDF is scanned.
- [ ] **Files → a PDF → Open in Aria** (long-press → Share, or the app row): scanned, not "Unsupported
  File". Score files (.mscz, .musicxml) still import as before.
- [ ] **Score open in Aria, then share a page:** the score closes and the scan starts.
- [ ] **Free library full:** sharing shows the paywall; after unlocking, the shared file is scanned.
- [ ] **iPad drag:** drag a PDF or picture from Files onto the library: it scans.
- [ ] **ScoreScanner:** Photos → Share → ScoreScanner opens its New Scan sheet with the page; a PDF
  from Files does the same. (Picture passed in the simulator.)

## Lyrics and "DM" chords (ScannerCore 0.1.9)

- [ ] **Scan a song with lyrics** (one verse and two verses): each syllable under its note, hyphens and extender
  lines as printed. (Checked on Smiles, "Let It Be" and Real Book ballads with the scanner on the Mac.)
- [ ] **Scan an instrumental lead sheet:** no lyrics appear.
- [ ] **A chart with "DM" or "DM6"** plays them as major chords.

## Slash bars (ScannerCore 0.1.8)

- [ ] **Scan a lead sheet with a slash-filled solo section** and press Play: the bars show as slashes, silent,
  chords still play. (Checked on a MuseScore lead sheet's solo section, bars 44-57.)
- [ ] **Scan a lead sheet with melody on the middle line (repeated B's)**: the notes stay notes.

## Scanned parts play with their instruments (ScannerCore 0.1.7)

- [ ] **Scan a string quartet or choir page and press Play:** each part sounds like its instrument or voice, not
  piano. (Instruments checked in the simulator.)
- [ ] **A page with "Clarinet in B♭" or "Horn in F":** plays at the right concert pitch.

## Scanned part names and lead-sheet clean-ups (ScannerCore 0.1.6)

- [ ] **Scan a string quartet, choir or voice-and-piano page:** the printed part names appear beside the first
  line and the short names ("Vln. I") on later lines. (Passed in the simulator with a generated quartet.)
- [ ] **Scan a lead sheet:** no part name shows, no "pp"/"p" appears under chord names, and no line plays an
  octave low.

## Scanned 1st/2nd endings (ScannerCore 0.1.5)

- [ ] **Scan a lead sheet with 1st and 2nd endings** and play it: the 1st ending plays once, it
  jumps back, and the second time through it goes to the 2nd ending. The brackets cover the same
  bars as on the page. (Passed in the simulator with "Smiles".)

## Scan progress sheet (iOS 27+)

- [ ] **One image.** Library → Scan → a photo of a lead sheet: the sheet shows one page segment
  and three stages (in plain words) that tick through in order, a running timer, and Cancel.
  The finished score opens in View mode.
- [ ] **Multi-page PDF.** Scan a 4-page PDF from Files: four page segments fill one by one, and
  progress never steps backwards while the next page's notes are read during this page's
  chords. A long PDF shows a single bar instead of segments.
- [ ] **Local recognition failure.** An unreadable/blank image gives a useful error;
  dismissing it releases the free-library slot and another scan can start. Aria uses
  bundled local readers; the former Apple cloud-throttling scenario is obsolete.
- [ ] **Cancel** mid-scan returns to the library with nothing added and the slot freed.

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
