// The reader's hardware keyboard shortcuts on Android (iOS:
// Views/ScoreReaderKeyboardShortcuts.swift, UIKeyCommand). While enabled, the reader's window
// passes key presses to AriaKeyboard.kt; they are read here and mapped by the shared
// ScoreReaderKeyboardShortcut.resolve. Ctrl or Meta stand for Command.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SkipFuse
import SwiftUI

struct ScoreReaderKeyboardShortcutView: View {
    var isEnabled: Bool
    var action: (ScoreReaderKeyboardShortcut) -> Void

    var body: some View {
        ZStack {
            #if os(Android)
            // Hooks the key presses of the window the reader is in (AriaKeyCapture).
            if let capture = try? AnyDynamicObject(className: "aria.skip.AriaKeyCapture") {
                ComposeView { capture }
            }
            #endif
            Color.clear
        }
        .task(id: isEnabled) {
            guard isEnabled, let keyboard = try? AnyDynamicObject(className: "aria.skip.AriaKeyboard") else { return }
            try? keyboard.setEnabled(true) as Void?
            while !Task.isCancelled {
                let events: String = (try? keyboard.takeEvents()) ?? ""
                for event in events.split(separator: "\n") {
                    if let shortcut = Self.shortcut(String(event)) {
                        action(shortcut)
                    }
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try? keyboard.setEnabled(false) as Void?
        }
    }

    /// "key modifiers" from AriaKeyboard.kt.
    static func shortcut(_ event: String) -> ScoreReaderKeyboardShortcut? {
        let parts = event.split(separator: " ")
        guard parts.count == 2, let flags = Int(parts[1]) else { return nil }
        let key: ScoreReaderShortcutKey
        switch parts[0] {
        case "space": key = .character(" ")
        case "delete": key = .delete
        case "escape": key = .escape
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "pageup": key = .pageUp
        case "pagedown": key = .pageDown
        default: key = .character(String(parts[0]))
        }
        return ScoreReaderKeyboardShortcut.resolve(key, modifiers: ScoreReaderShortcutModifiers(rawValue: flags))
    }
}
