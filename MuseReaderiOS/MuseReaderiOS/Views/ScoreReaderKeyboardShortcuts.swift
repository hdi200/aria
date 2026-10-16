//
//  ScoreReaderKeyboardShortcuts.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

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
            command("1", modifiers: .command, title: "Voice 1"),
            command("2", modifiers: .command, title: "Voice 2"),
            command("3", modifiers: .command, title: "Voice 3"),
            command("4", modifiers: .command, title: "Voice 4"),
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
        guard let shortcut = Self.resolveShortcut(input: sender.input ?? "", modifiers: sender.modifierFlags)
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

    static func resolveShortcut(input: String, modifiers: UIKeyModifierFlags) -> ScoreReaderKeyboardShortcut? {
        let key: ScoreReaderShortcutKey
        switch input {
        case UIKeyCommand.inputDelete: key = .delete
        case UIKeyCommand.inputEscape: key = .escape
        case UIKeyCommand.inputLeftArrow: key = .leftArrow
        case UIKeyCommand.inputRightArrow: key = .rightArrow
        case UIKeyCommand.inputUpArrow: key = .upArrow
        case UIKeyCommand.inputDownArrow: key = .downArrow
        default: key = .character(input)
        }
        return ScoreReaderKeyboardShortcut.resolve(key, modifiers: Self.modifiers(modifiers))
    }

    private static func modifiers(_ flags: UIKeyModifierFlags) -> ScoreReaderShortcutModifiers {
        var modifiers: ScoreReaderShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.alternate) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// Keys whose presses arrive outside key commands: Command-1...4 and the arrows.
    private func shortcut(for press: UIPress) -> ScoreReaderKeyboardShortcut? {
        guard let key = press.key else {
            return nil
        }

        let shortcutKey: ScoreReaderShortcutKey
        switch key.keyCode {
        case .keyboard1: shortcutKey = .character("1")
        case .keyboard2: shortcutKey = .character("2")
        case .keyboard3: shortcutKey = .character("3")
        case .keyboard4: shortcutKey = .character("4")
        case .keyboardLeftArrow: shortcutKey = .leftArrow
        case .keyboardRightArrow: shortcutKey = .rightArrow
        case .keyboardUpArrow: shortcutKey = .upArrow
        case .keyboardDownArrow: shortcutKey = .downArrow
        default: return nil
        }
        let modifiers = Self.modifiers(key.modifierFlags)
        // Digits only with Command (voices); plain digits are durations, sent as key commands.
        if case .character = shortcutKey, modifiers != .command {
            return nil
        }
        return ScoreReaderKeyboardShortcut.resolve(shortcutKey, modifiers: modifiers)
    }
}
