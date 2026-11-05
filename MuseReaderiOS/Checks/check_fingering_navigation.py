#!/usr/bin/env python3
"""Exercise the real fingering-entry action with volatile selection render payloads.

No app/native build: compile the production action against a small session double.
An endpoint returns the same rest with freshly rendered bytes, as the live bridge does.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def function(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


action = function((ROOT / "MuseReaderiOS/Models/ScoreReaderStateEditing.swift").read_text(),
                  "func setFingering(_ finger: Int)")
selection_source = (ROOT / "MuseReaderiOS/Models/ScoreSession.swift").read_text()
signature = "func hasSameNavigationPosition(as other: Self) -> Bool"
identity = function(selection_source, signature) if signature in selection_source else ""

source = r'''
import Foundation
import CoreGraphics
import Darwin
struct Rect: Equatable { let center: CGPoint }
struct Selection: Equatable {
    enum Kind { case note, rest }
    let kind: Kind
    let pageIndex = 0
    let partID: String? = "piano"
    let measureIndex: Int?
    let tick: Int64?
    let normalizedRect: Rect
    // Deliberately changes for the same selected element on every bridge read.
    let overlayPDFData = UUID().uuidString
    var canEditFingering: Bool { kind == .note }
    IDENTITY
}
struct State { let selection: Selection? }
enum NavigationFailure: Error { case didNotTerminate }
@MainActor final class Session {
    let kinds: [Selection.Kind]
    var index = 0
    var calls = 0
    var edits: [(Int, Int)] = []
    init(_ kinds: [Selection.Kind]) { self.kinds = kinds }
    var state: State {
        State(selection: Selection(kind: kinds[index], measureIndex: index / 4,
            tick: Int64(index / 4 * 1920),
            normalizedRect: Rect(center: CGPoint(x: CGFloat(index), y: 0))))
    }
    func setFingering(_ finger: Int) async throws -> State {
        calls = 0; edits.append((index, finger)); return state
    }
    func selectAdjacentElement(next: Bool) async throws -> State {
        calls += 1
        guard calls <= kinds.count + 2 else { throw NavigationFailure.didNotTerminate }
        index = max(0, min(index + (next ? 1 : -1), kinds.count - 1))
        return state
    }
    func selectElement(pageIndex: Int, normalizedPoint: CGPoint) async throws -> State {
        index = Int(normalizedPoint.x); return state
    }
}
@MainActor final class Reader {
    let session: Session
    var editingState: State
    var task: Task<Void, Error>?
    init(_ kinds: [Selection.Kind], index: Int = 0) {
        session = Session(kinds); session.index = index; editingState = session.state
    }
    func performEditingAction(mutatesScore: Bool, revealActiveNotation: Bool,
                             action: @escaping (Session) async throws -> State) {
        task = Task { editingState = try await action(session) }
    }
    ACTION
}
@main struct Check {
    @MainActor static func main() async {
        do {
            let notes = Reader([.note, .note, .note, .note] + Array(repeating: .rest, count: 20))
            for finger in 1...4 {
                notes.setFingering(finger); try await notes.task!.value
                precondition(notes.session.index == min(finger, 3))
            }
            // Replacing the last digit must finish as well, leaving controls usable.
            notes.setFingering(5); try await notes.task!.value
            precondition(notes.session.index == 3 && notes.session.edits.count == 5)
            let skip = Reader([.note, .rest, .rest, .note])
            skip.setFingering(2); try await skip.task!.value
            precondition(skip.session.index == 3)
            skip.setFingering(0); try await skip.task!.value
            precondition(skip.session.index == 0 && skip.session.edits.last!.0 == 3)
            let first = Reader([.rest, .rest, .note], index: 2)
            first.setFingering(0); try await first.task!.value
            precondition(first.session.index == 2)
            let only = Reader([.note])
            only.setFingering(1); try await only.task!.value
            only.setFingering(0); try await only.task!.value
            precondition(only.session.index == 0)
            let invalid = Reader([.rest])
            invalid.setFingering(3)
            precondition(invalid.task == nil)
            print("PASS four-note entry, trailing rests with changing render data, last-note replacement, skipped rests, erase/back, leading rests, single note and non-note guard")
        } catch {
            print("FAIL fingering navigation: \(error)"); exit(1)
        }
    }
}
'''.replace("IDENTITY", identity).replace("ACTION", action)

with tempfile.TemporaryDirectory(prefix="aria-fingering-navigation-") as temp:
    swift = Path(temp) / "check.swift"
    executable = Path(temp) / "check"
    swift.write_text(source)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                    str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
