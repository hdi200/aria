#!/usr/bin/env python3
"""Run the reader's real input, screen-awake, and drop policies without an Xcode build."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / 'MuseReaderiOS'

def declaration(path, kind, name):
    source = (root / path).read_text()
    start = source.index(f'{kind} {name}')
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

sources = [declaration('Models/ScoreReaderStateEditing.swift', kind, name) for kind, name in [
    ('enum', 'ScorePageTapInputKind'), ('enum', 'ScoreReaderToolCategory'),
    ('struct', 'ScoreReaderToolModePolicy'), ('struct', 'ScoreInstrumentMove')]]
sources += [declaration('Models/ScoreReaderStatePlayback.swift', 'struct', 'ScoreScreenAwakeRequests'),
            declaration('Views/ScoreReaderView.swift', 'enum', 'ScoreReaderSequenceDirection'),
            declaration('Views/ScoreReaderView.swift', 'struct', 'ScoreReaderPageSwipePolicy'),
            declaration('Views/CreateNewScoreView.swift', 'struct', 'InstrumentReorderDropDelegate'),
            declaration('Views/ScoreReaderMoreEditors.swift', 'struct', 'ScorePartLayoutDropDelegate')]
# Minimal data records let the production delegates run against test bindings.
stubs = '''import Foundation
import SwiftUI
import UIKit
enum ScoreSelectedElementKind { case note, rest, bar, measure }
struct NewScoreInstrument: Identifiable { let id: String }
struct ScorePart: Identifiable { let id: String }
'''
checks = r'''
@main struct Checks {
    @MainActor static func main() {
        // A held range drag can cross the page-swipe threshold before lift-off.
        // The pending selection claims it even before measure geometry arrives.
        for width in [CGFloat(-300), -48, 48, 300] {
            let drag = CGSize(width: width, height: 8)
            assert(ScoreReaderPageSwipePolicy.direction(for: drag, hasPlaybackSelection: true) == nil)
            assert(ScoreReaderPageSwipePolicy.direction(for: drag, hasPlaybackSelection: false)
                == (width < 0 ? .next : .previous))
        }
        for drag in [CGSize(width: 47, height: 0), CGSize(width: 90, height: 120),
                     CGSize(width: -90, height: -90)] {
            assert(ScoreReaderPageSwipePolicy.direction(for: drag, hasPlaybackSelection: false) == nil)
        }
        for enabled in [false, true] {
            for explicit in [false, true] {
                assert(ScoreReaderToolModePolicy.insertsNoteAtPoint(enabled: enabled, inputKind: .direct,
                    acceptsDirectTaps: explicit) == (enabled && explicit))
                assert(ScoreReaderToolModePolicy.insertsNoteAtPoint(enabled: enabled, inputKind: .pencil,
                    acceptsDirectTaps: explicit) == enabled)
            }
        }
        var awake = ScoreScreenAwakeRequests()
        let reader = UUID(), otherReader = UUID()
        awake.setRequested(true, owner: reader)
        awake.setRequested(true, owner: otherReader)
        awake.setRequested(false, owner: reader)
        assert(awake.isRequested)
        awake.setRequested(false, owner: otherReader)
        assert(!awake.isRequested)
        for visible in [false, true] {
            for foreground in [false, true] {
                assert(ScoreScreenAwakeRequests.needsScreen(playbackIsPlaying: true, isCountingIn: false,
                    isExportingVideo: false, isVisible: visible, isForeground: foreground) == (visible && foreground))
                assert(ScoreScreenAwakeRequests.needsScreen(playbackIsPlaying: false, isCountingIn: true,
                    isExportingVideo: false, isVisible: visible, isForeground: foreground) == (visible && foreground))
                assert(ScoreScreenAwakeRequests.needsScreen(playbackIsPlaying: false, isCountingIn: false,
                    isExportingVideo: true, isVisible: visible, isForeground: foreground) == (visible && foreground))
                assert(!ScoreScreenAwakeRequests.needsScreen(playbackIsPlaying: false, isCountingIn: false,
                    isExportingVideo: false, isVisible: visible, isForeground: foreground))
            }
        }
        let move = ScoreInstrumentMove(partIDs: ["a", "b", "c"], sourceIndex: 0, destinationIndex: 3)!
        assert(move.indices(in: ["b", "a", "c"])!.source == 1)
        assert(move.indices(in: ["b", "c"]) == nil)
        let upward = ScoreInstrumentMove(partIDs: ["a", "b", "c"], sourceIndex: 2, destinationIndex: 0)!
        assert(upward.indices(in: ["b", "a", "c"])!.destination == 1)
        assert(upward.indices(in: ["b", "c"]) == nil)

        var instruments = ["a", "b", "c"].map { NewScoreInstrument(id: $0) }
        var dragged: String? = "a", original: Int? = 0
        var callbacks: [ScoreInstrumentMove] = []
        let binding = Binding(get: { instruments }, set: { instruments = $0 })
        let dragBinding = Binding(get: { dragged }, set: { dragged = $0 })
        let originalBinding = Binding(get: { original }, set: { original = $0 })
        let live = InstrumentReorderDropDelegate(instrument: instruments[2], instruments: binding,
            draggedInstrumentID: dragBinding, draggedOriginalIndex: originalBinding,
            didDrop: { callbacks.append($0) })
        assert(instruments.map(\.id) == ["a", "b", "c"] && callbacks.isEmpty)
        assert(live.commitMove())
        assert(callbacks.count == 1 && callbacks[0].partID == "a" && callbacks[0].beforePartID == nil)
        assert(instruments.map(\.id) == ["a", "b", "c"]) // Await the engine's accepted order.
        assert(dragged == nil && original == nil)
        // A new-score draft has no engine; an accepted drop changes only that draft.
        dragged = "c"; original = 2
        let draft = InstrumentReorderDropDelegate(instrument: instruments[0], instruments: binding,
            draggedInstrumentID: dragBinding, draggedOriginalIndex: originalBinding, didDrop: nil)
        assert(draft.commitMove() && instruments.map(\.id) == ["c", "a", "b"])
        dragged = "removed"; original = 0
        assert(!draft.commitMove() && instruments.map(\.id) == ["c", "a", "b"])
        var parts = ["a", "b", "c"].map { ScorePart(id: $0) }
        dragged = "c"; original = 2
        let layout = ScorePartLayoutDropDelegate(part: parts[0],
            parts: Binding(get: { parts }, set: { parts = $0 }), draggedPartID: dragBinding,
            draggedOriginalIndex: originalBinding, didDrop: { callbacks.append($0) })
        assert(layout.commitMove() && callbacks.last!.partID == "c" && callbacks.last!.beforePartID == "a")
        assert(parts.map(\.id) == ["a", "b", "c"])
        print("PASS page-swipe selection priority, reader input, screen-awake ownership, queued reorders, and drop delegates")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='aria-reader-checks-') as temporary:
    work = Path(temporary)
    swift = work / 'Checks.swift'
    swift.write_text(stubs + '\n'.join(sources) + checks)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    support = Path(sdk) / 'System/iOSSupport'
    binary = work / 'reader-checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-target', 'arm64-apple-ios17.0-macabi', '-sdk', sdk,
                    '-F', str(support / 'System/Library/Frameworks'),
                    '-module-cache-path', str(work / 'modules'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
