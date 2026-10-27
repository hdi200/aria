# Aria's patches to skip-ui

A copy of skip-ui 1.63.0 (revision fa339f6001bde88f02fbfd76417b805acd73b0aa) with the
changes below, used through `.package(path:)` in `Aria/Package.swift`. Each change is
marked `ARIA PATCH` in the source.

## Sheets (`Sources/SkipUI/SkipUI/Layout/Presentation.swift`, `SheetPresentation`)

- Tapping above a sheet dismisses it, unless `interactiveDismissDisabled`. Skip draws
  that area inside the ModalBottomSheet and clips it away with the sheet's shape, so
  taps there reached neither the sheet's content nor the scrim; on a phone, where a
  sheet has no side gutters, tapping outside never worked. A tap detector on the sheet's
  outer modifier (outside the clip) dismisses on taps above the card.
- The drag handle shows only for `presentationDragIndicator(.visible)`. It draws above
  the sheet's card, floating over the scrim or the toolbar.

## Alerts (same file, `AlertPresentation`)

- An alert whose only button has the cancel role (`Button("OK", role: .cancel)`) shows
  that one button. Skip also added its own "OK" confirm button, so these alerts showed
  two OKs.

## Confirmation dialogs (same file, `ConfirmationDialogPresentation`)

- The action sheet is drawn on the opaque surface colour instead of 90% surface, which
  let the bottom panel show through (Change Clef).
- The action sheet is at most 440 wide (was the 640 sheet width), with body-size
  buttons and 12 vertical padding (was title3 and 16): it looked oversized on tablets.

## Text (`Sources/SkipUI/SkipUI/Text/Text.swift`)

- A text with a line limit and no truncation mode is cut with an ellipsis (SwiftUI's
  default, `.tail`); Skip clipped it. Skip Fuse has no `truncationMode` modifier, so no
  text in Aria sets one.
  With an ellipsis, a one-line text that wrapped at a word ("New String Quartet.mscz"
  showed as "New String") is cut at a character instead ("New String Quartet.m…").
  (Turning soft wrap off instead let one-line text grow wider than its frame.)

## Images (`Sources/SkipUI/SkipUI/Components/Image.swift`, `RenderSystem`)

- A symbol variant that doesn't exist (`symbolVariant(.fill)` on a symbol with no
  ".fill") falls back to the plain symbol, as on iOS. Skip showed a warning triangle
  (the selected Full Score row in the Parts panel).

## Bitmap handoff (`Sources/SkipUI/SkipUI/UIKit/UIImage.swift`)

- `UIImage.UIImageBitmapHandoff` lets app Kotlin give Swift a ready `Bitmap`: Kotlin
  calls `put(bitmap)` and passes the returned `aria-bitmap:` key to Swift, which opens it
  with `UIImage(contentsOfFile:)`. Before, score pages crossed as PNG data, and PNG
  encoding cost 240–300 ms per Edit-mode page on the emulator (drawing took 8 ms).
  Bitmaps put but never taken are dropped, oldest first, after 8.

## Animated stack ownership (`HStack`, `VStack`, `ZStack`)

- A managed heap capture linked image-bearing native value boxes (through
  `StateSupport.valueHolder`) to `ComposeStateSaver.state`, obsolete renderable
  lists in `AnimatedContentTransitionScopeImpl.targetSizeMap`, and old transition
  snapshot records. Three image slots still held their initial page bitmaps over
  530 seconds later, when the reader was on page 16. This is an observed retaining
  path; it does not establish an hourly leak rate.
- The stacks now pass immutable identity lists as `AnimatedContent.targetState`.
  `Skip/AnimatedRenderableContent.kt` stores the latest renderables separately in
  composition-local observable slots, replacing content for unchanged identities.
  This preserves bridged updates even during a transition. Outgoing content stays
  available until Compose disposes it; a rapid return to the current identity does
  not discard that identity's new content. Animation history no longer owns full
  native view graphs through its state keys.
- No bitmap is explicitly released or recycled by this patch. Page raster size and
  viewport publication are unchanged.
- Optimized release validation: ten minutes of playback, same-process loaded-page
  replay, and five minutes of paced editing on Pixel and the actual 3 GB budget AVD;
  Pixel editing was extended another three minutes to check its memory envelope.
  Globals and page-state counts remain bounded; shared page-value slots stay at 16
  during editing on both devices. Budget playback's final five minute PSS medians
  stay at 615–617 MiB. Pixel editing's extension repeats the earlier GC range, with
  a peak only about 3.7 MiB above its first phase. All 236 Pixel and 134 budget
  edit/undo actions reached the engine. Cursor, selection, controls and changed
  notation update. See the Android repository's
  `measurements/2026-10-17-step1.json` and `PERFORMANCE_AUDIT_FINDINGS.md` for before/
  after counts, frame denominators and memory limits. No forced GC or profiler ran
  in those gate phases.

## Gesture cancellation (`Sources/SkipUI/SkipUI/System/Gesture.swift`)

- `ARIA PATCH`: normal and simultaneous drag detectors reset their accumulated
  translation on cancellation without invoking `onEnded`. Previously a cancelled
  pointer stream took the same path as a completed drop, which can commit native
  score changes for clients using `onEnded`.
- Aria's Android page now owns explicit begin/move/end/cancel events in
  `AriaPageGestures.kt`, with a per-gesture anchor and no global callback owner.
  It clears visual/range previews on cancellation, and commits only on an actual
  pointer up. Other Skip gesture clients retain their normal completion callbacks.
- Native iOS gesture code is unchanged. Exact runtime results and limitations are
  recorded in the Android repository's `GESTURE_FIX_LOG.md`.

## Saved state keys (`Sources/SkipUI/SkipUI/Compose/ComposeStateSaver.swift`)

- `ARIA PATCH`: `ComposeStateSaver.Key` carries its saved value in memory, and
  `restore` falls back to it when the saver's own map has no entry. An `.id()` view
  gets a fresh `ComposeStateSaver` when its id changes, and presentations make theirs
  with plain `remember`; a saver re-created since the save returned nil, Compose
  wrapped it in a `MutableState`, and the bridged `@State` crashed on the null
  `StateSupport` (`StateSupport_Bridge.swift:11`, and the SwiftJNI trap in
  `ScoreReaderPageSurface` sync on Play). Reproduced on the emulator by editing every
  Score Setup field except Subtitle and saving. The value is never parceled, so
  nothing is retained beyond the key Compose already holds.

## Lazy stack padding (`Sources/SkipUI/SkipUI/View/AdditionalViewModifiers.swift`)

- `ARIA PATCH`: `PaddingModifier` clamps the content padding it hands a lazy stack or
  grid to zero or more. Compose's `PaddingValues` throws "Padding must be non-negative",
  and Skip animates padding, so an inset animating to 0 could dip just below it and
  crash (Play Console, version 6: `EdgeInsets.asPaddingValues`, three crashes on a
  Fairphone 5, reported as hdi200/aria#6). Padding laid out by `PaddingLayout` is
  unchanged.

## Local TEST-only focused UI audit

`ARIA_PHONE_AUDIT=1` adds coarse callbacks around the default View body/Evaluate
path, non-lazy ForEach evaluation and GeometryReader content/traversal. The TEST
application records buffered CPU/wall boundaries and approximate process-wide ART
allocation deltas; ordinary builds compile these callbacks out. The callbacks do
not wrap views or change hierarchy, inputs, identities, layout or drawing. Native
Swift construction/conversion spans live in the sibling skip-fuse-ui patch. See
`FOCUSED_UI_AUDIT.md` in the Android repository for measurement qualifications.

## Retired context-construction trial

The isolated four-field constructor hunk from upstream PR #575 was measured in
release TEST 10 and removed after physical Pixel 8a comparisons showed no
practical benefit. No active constructor branch or selector remains. The pinned
1.63.0 dependency and ordinary implementation stay unchanged; no framework
upgrade or unrelated upstream List/state-saver patch was taken. Archived diff
and results: `measurements/2026-10-20-final-ui-context.patch` and
`FINAL_UI_RELEASE_ROUND.md` in the Android repository.

## Updating skip-ui

Copy the new release's checkout here (without `.git`), re-apply the `ARIA PATCH`
changes, update the version above, and check the patched behaviour still applies.

The vendored skip-fuse-ui manifest points at this sibling copy. Keep that path
dependency when rebasing so transitive URL dependencies do not introduce a second
skip-ui identity.
