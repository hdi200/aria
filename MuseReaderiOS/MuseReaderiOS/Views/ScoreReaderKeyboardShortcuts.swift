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
            command(UIKeyCommand.inputLeftArrow, title: "Previous Element"),
            command(UIKeyCommand.inputUpArrow, title: "Previous Element"),
            command(UIKeyCommand.inputRightArrow, title: "Next Element"),
            command(UIKeyCommand.inputDownArrow, title: "Next Element")
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
        case (UIKeyCommand.inputLeftArrow, []), (UIKeyCommand.inputUpArrow, []):
            return .selectPrevious
        case (UIKeyCommand.inputRightArrow, []), (UIKeyCommand.inputDownArrow, []):
            return .selectNext
        default:
            return nil
        }
    }

    private func shortcut(for press: UIPress) -> ScoreReaderKeyboardShortcut? {
        guard let key = press.key else {
            return nil
        }

        let normalizedModifiers = key.modifierFlags.intersection([.command, .shift, .alternate, .control])
        guard normalizedModifiers.isEmpty else {
            return nil
        }

        switch key.keyCode {
        case .keyboardLeftArrow, .keyboardUpArrow:
            return .selectPrevious
        case .keyboardRightArrow, .keyboardDownArrow:
            return .selectNext
        default:
            return nil
        }
    }
}
