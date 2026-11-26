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


## Drum pad entry (November 25, branch `percussion-entry`)

Use a drum-kit score (the Rock Groove demo in `promo/percussion-entry/`, or New Score › Rock Band). Not yet on Android: the Android session needs the new engine call first.

- [ ] **iPhone, portrait and landscape:** Edit, tap a rest in the drum staff: the piano keyboard is replaced by the drum pad at the same height. A full kit shows two rows that scroll sideways, fading at the right edge.
- [ ] **iPad:** the same, with taller pads and shortcut letters; the Half step/Octave controls are gone on drum staves.
- [ ] **Entering drums:** tap Snare, Kick, Closed Hi-Hat in turn: each enters at the cursor on its own line, with the right notehead. Kick and pedal hi-hat go to voice 2 (stems down), the others to voice 1. The cursor moves on after each.
- [ ] **Cursor:** single taps move forward one beat at a time to the end of the bar and into the next; no extra bars are appended and no beat is entered twice.
- [ ] **Fast taps:** tap one pad four times quickly: four notes, one per beat.
- [ ] **Add from Select mode:** leave note input, tap a hi-hat note to select it, tap Bass Drum: the kick goes under that hi-hat on the same beat (voice 2, stem down), the hi-hat stays, note input turns on, and the next pad tap enters on the following beat.
- [ ] **Chord mode:** turn on the chord toggle, tap Closed Hi-Hat then Kick: both land on the same beat, hi-hat stem up in voice 1 and kick stem down in voice 2. One Undo removes the kick only.
- [ ] **Staff taps:** in note input, tap a drum's line on the staff: the preview shows that drum's notehead, and the note enters on that line (the chosen pad's drum if it sits on that line, otherwise the line's first drum).
- [ ] **Rests and durations:** rest entry, dots and duration changes work on the drum staff.
- [ ] **Small kits:** a snare-drum or triangle staff shows one row of tall pads instead.
- [ ] **Pitched staves are unchanged:** the piano keyboard, Half step and Octave still show and work on a treble staff in the same score.
- [ ] **Desktop MuseScore 4.7.6/4.7.7:** a score saved after drum entry opens with the same drums, voices and noteheads.
- Known gaps: pressing several pads at once isn't supported yet (use chord mode), hearing a chord plays only the voice-1 drums, and pads can't yet change an existing note's drum.

## Pencil crash (November 25, BUG-033)

- [ ] **iPad with Pencil hover (M2 or later):** hold the Pencil just above the score and switch Edit → Annotate → reading several times: no crash.
- [ ] **Pencil double tap** still works in Edit and Annotate, and does nothing while reading.

## Android launch after an update (November 25)

- [ ] **Moto (sideload release build):** install this build, open a score and play it. Then install the next build over it (any later version): the library appears and the first score opens without the usual pause, and playback sounds normal.
- [ ] **Play vitals, two weeks after the release:** slow cold starts should no longer spike on release days (was up to about 5%).

## Time signature over a tuplet (November 25, BUG-034)

- [ ] **iPhone/iPad and Android:** in 4/4, end a bar with an eighth triplet of an eighth and a quarter (F, G). Change that bar to 7/8: the G is split by the barline, in a triplet in each bar, tied. Then change it to 3/4 and back to 4/4: no freeze, and the app stays open.
- [ ] **Desktop MuseScore 4.7.6/4.7.7:** the saved 7/8 file opens with the same triplets and ties.

## Setlist rename (November 25, BUG-039)

- [ ] **iPhone and iPad:** hold a setlist › Rename Setlist, type a new name, tap Rename: the sidebar and the setlist's title show the new name. Cancel leaves it unchanged, and Rename again starts from the current name.
- [ ] **Android:** the same on the phone and tablet.

## Galaxy Tab S7 (November 25, BUG-035 to BUG-037)

Checked on the Tab S7-sized emulator; these need the real Samsung tablet (One UI).

- [ ] **Import:** Import opens Android's file picker (not only My Files). Pick an .mscz from Downloads and from Internal storage: it imports and opens.
- [ ] **My Files:** in My Files, open an .mscz with Aria, and Share › Aria: both import. If Import still opens My Files, pick a score there: it imports, or an "Import Failed" message says why (never nothing).
- [ ] **Instruments sheet, landscape and portrait:** Edit › More › Add/Remove Instrument with 8+ instruments, keyboard up (tap Search) and down, with Samsung's taskbar showing: Close and Done stay visible, the In Score list scrolls to the last Remove button, and the Remove confirmation's buttons are fully on screen.
- [ ] **Larger screen zoom** (Settings › Display › Screen zoom, highest): repeat the instruments check.
- [ ] **Library header in landscape (BUG-038):** Scan, Import and + are full width with their labels; a long setlist name truncates before the buttons.
- [ ] **Scan with Camera:** the document scanner opens. If it doesn't within 15 s, the Samsung Camera app opens instead, and the photo is scanned. Note the Google Play services version if the scanner never opens.

## Stand-in fonts (November 25, IOS-044)

- [ ] **Android:** open a score in Arial, Times New Roman or Calibri: text keeps its width and line breaks.
- [ ] **iPhone/iPad and Android:** a title in Arial Black is drawn heavy (Archivo Black), not in the thin system font. *iPhone simulator passed November 25 (Calibri, Cambria and Times New Roman stand-ins also looked right); iPad and Android still to check.*
- [ ] **Save and open on desktop MuseScore:** the original font names and look are unchanged.
- [ ] **Open Source screen** lists the Liberation, Carlito, Caladea and Archivo Black fonts. *iPhone simulator passed November 25; Android still to check.*

## Score fixes (November 25, BUG-032)

- [ ] **Desktop score with a hyphen typed into a lyric** ("glo-"): opening it shows no Review Score Fixes sheet.
- [ ] **Older Aria score with empty lyrics:** the sheet appears; tap Not Now, close and reopen: it does not appear again.
- [ ] **Fix some, skip some:** with two issues, fix one and uncheck the other; reopen: no sheet.
- [ ] **Android:** same three checks after rebuilding `libaria_engine.so`.

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
