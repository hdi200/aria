//
//  ScoreReaderKeyboardShortcuts.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

enum ScoreReaderKeyboardShortcut {
    case undo
    case redo
    case copy
    case cut
    case paste
    case selectAll
    case delete
    case togglePlayback
    case clearSelection
    case selectPrevious
    case selectNext
    case toggleNoteInput
    case enterPitch(Int)
    case applyDuration(ScoreNoteDuration)
    case enterRest
    case toggleDot
    case toggleTie
    case addSlur
    case movePitch(up: Bool)
    case shiftOctave(Int)
    case shiftSemitone(Int)
}

struct ScoreReaderKeyboardShortcutView: UIViewRepresentable {
    var isEnabled: Bool
    var action: (ScoreReaderKeyboardShortcut) -> Void

    func makeUIView(context: Context) -> KeyboardShortcutHostingView {
        let view = KeyboardShortcutHostingView()
        view.isEnabled = isEnabled
        view.action = action
        return view
    }

    func updateUIView(_ uiView: KeyboardShortcutHostingView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.action = action
        uiView.refreshFirstResponder()
    }
}

final class KeyboardShortcutHostingView: UIView {
    var isEnabled = true {
        didSet {
            refreshFirstResponder()
        }
    }
    var action: ((ScoreReaderKeyboardShortcut) -> Void)?

    override var canBecomeFirstResponder: Bool {
        isEnabled
    }

    override var keyCommands: [UIKeyCommand]? {
        guard isEnabled else {
            return nil
        }

        return [
            command("z", modifiers: .command, title: "Undo"),
            command("z", modifiers: [.command, .shift], title: "Redo"),
            command("y", modifiers: .command, title: "Redo"),
            command("c", modifiers: .command, title: "Copy"),
            command("x", modifiers: .command, title: "Cut"),
            command("v", modifiers: .command, title: "Paste"),
            command("a", modifiers: .command, title: "Select All"),
            command(UIKeyCommand.inputDelete, title: "Delete"),
            command(" ", title: "Play/Pause"),
            command(UIKeyCommand.inputEscape, title: "Clear Selection"),
            command("n", title: "Toggle Note Input"),
            command("a", title: "Enter A"),
            command("b", title: "Enter B"),
            command("c", title: "Enter C"),
            command("d", title: "Enter D"),
            command("e", title: "Enter E"),
            command("f", title: "Enter F"),
            command("g", title: "Enter G"),
            command("0", title: "Enter Rest"),
            command("3", title: "Sixteenth Note"),
            command("4", title: "Eighth Note"),
            command("5", title: "Quarter Note"),
            command("6", title: "Half Note"),
            command("7", title: "Whole Note"),
            command(".", title: "Toggle Dot"),
            command("+", title: "Tie"),
            command("=", modifiers: .shift, title: "Tie"),
            command("s", title: "Slur"),
            command(UIKeyCommand.inputLeftArrow, title: "Previous Element"),
            command(UIKeyCommand.inputUpArrow, title: "Move Pitch Up"),
            command(UIKeyCommand.inputRightArrow, title: "Next Element"),
            command(UIKeyCommand.inputDownArrow, title: "Move Pitch Down"),
            command(UIKeyCommand.inputUpArrow, modifiers: .alternate, title: "Octave Up"),
            command(UIKeyCommand.inputDownArrow, modifiers: .alternate, title: "Octave Down"),
            command(UIKeyCommand.inputUpArrow, modifiers: .command, title: "Half Step Up"),
            command(UIKeyCommand.inputDownArrow, modifiers: .command, title: "Half Step Down"),
            command(UIKeyCommand.inputUpArrow, modifiers: .shift, title: "Half Step Up"),
            command(UIKeyCommand.inputDownArrow, modifiers: .shift, title: "Half Step Down")
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshFirstResponder()
    }

    func refreshFirstResponder() {
        guard window != nil else {
            return
        }

        if isEnabled {
            DispatchQueue.main.async { [weak self] in
                _ = self?.becomeFirstResponder()
            }
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    @objc private func performShortcut(_ sender: UIKeyCommand) {
        guard let shortcut = shortcut(input: sender.input ?? "", modifiers: sender.modifierFlags)
        else {
            return
        }

        action?(shortcut)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isEnabled else {
            super.pressesBegan(presses, with: event)
            return
        }

        let shortcuts = presses.compactMap(shortcut(for:))
        guard !shortcuts.isEmpty else {
            super.pressesBegan(presses, with: event)
            return
        }

        shortcuts.forEach { action?($0) }
    }

    private func command(
        _ input: String,
        modifiers: UIKeyModifierFlags = [],
        title: String
    ) -> UIKeyCommand {
        UIKeyCommand(
            input: input,
            modifierFlags: modifiers,
            action: #selector(performShortcut(_:)),
            discoverabilityTitle: title
        )
    }

    private func shortcut(input: String, modifiers: UIKeyModifierFlags) -> ScoreReaderKeyboardShortcut? {
        let normalizedModifiers = modifiers.intersection([.command, .shift, .alternate, .control])
        switch (input, normalizedModifiers) {
        case ("z", .command):
            return .undo
        case ("z", [.command, .shift]), ("y", .command):
            return .redo
        case ("c", .command):
            return .copy
        case ("x", .command):
            return .cut
        case ("v", .command):
            return .paste
        case ("a", .command):
            return .selectAll
        case (UIKeyCommand.inputDelete, []):
            return .delete
        case (" ", []):
            return .togglePlayback
        case (UIKeyCommand.inputEscape, []):
            return .clearSelection
        case ("n", []):
            return .toggleNoteInput
        case ("a", []):
            return .enterPitch(9)
        case ("b", []):
            return .enterPitch(11)
        case ("c", []):
            return .enterPitch(0)
        case ("d", []):
            return .enterPitch(2)
        case ("e", []):
            return .enterPitch(4)
        case ("f", []):
            return .enterPitch(5)
        case ("g", []):
            return .enterPitch(7)
        case ("0", []):
            return .enterRest
        case ("3", []):
            return .applyDuration(.sixteenth)
        case ("4", []):
            return .applyDuration(.eighth)
        case ("5", []):
            return .applyDuration(.quarter)
        case ("6", []):
            return .applyDuration(.half)
        case ("7", []):
            return .applyDuration(.whole)
        case (".", []):
            return .toggleDot
        case ("+", []), ("=", .shift):
            return .toggleTie
        case ("s", []):
            return .addSlur
        case (UIKeyCommand.inputLeftArrow, []):
            return .selectPrevious
        case (UIKeyCommand.inputRightArrow, []):
            return .selectNext
        case (UIKeyCommand.inputUpArrow, []):
            return .movePitch(up: true)
        case (UIKeyCommand.inputDownArrow, []):
            return .movePitch(up: false)
        case (UIKeyCommand.inputUpArrow, .alternate):
            return .shiftOctave(1)
        case (UIKeyCommand.inputDownArrow, .alternate):
            return .shiftOctave(-1)
        case (UIKeyCommand.inputUpArrow, .command), (UIKeyCommand.inputUpArrow, .shift):
            return .shiftSemitone(1)
        case (UIKeyCommand.inputDownArrow, .command), (UIKeyCommand.inputDownArrow, .shift):
            return .shiftSemitone(-1)
        default:
            return nil
        }
    }

    private func shortcut(for press: UIPress) -> ScoreReaderKeyboardShortcut? {
        guard let key = press.key else {
            return nil
        }

        let normalizedModifiers = key.modifierFlags.intersection([.command, .shift, .alternate, .control])
        switch (key.keyCode, normalizedModifiers) {
        case (.keyboardLeftArrow, []):
            return .selectPrevious
        case (.keyboardRightArrow, []):
            return .selectNext
        case (.keyboardUpArrow, []):
            return .movePitch(up: true)
        case (.keyboardDownArrow, []):
            return .movePitch(up: false)
        case (.keyboardUpArrow, .alternate):
            return .shiftOctave(1)
        case (.keyboardDownArrow, .alternate):
            return .shiftOctave(-1)
        case (.keyboardUpArrow, .command), (.keyboardUpArrow, .shift):
            return .shiftSemitone(1)
        case (.keyboardDownArrow, .command), (.keyboardDownArrow, .shift):
            return .shiftSemitone(-1)
        default:
            return nil
        }
    }
}
