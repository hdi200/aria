package aria.skip

import android.app.Activity
import android.content.ContextWrapper
import android.view.KeyEvent
import android.view.Window
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider

/// Hardware keyboard shortcuts for the reader (iOS: UIKeyCommand in
/// ScoreReaderKeyboardShortcuts.swift). While the reader enables them, the reader's window
/// (AriaKeyCapture) hands key presses here; the shortcut keys are queued for Swift
/// (ScoreReaderKeyboardShortcutView in AndroidKeyboardShortcuts.swift), which maps them
/// with the shared ScoreReaderKeyboardShortcut.resolve.
object AriaKeyboardImpl {
    @Volatile var enabled = false
    private val lock = Any()
    private val queue = ArrayList<String>()
    private val pressed = HashSet<Int>()

    /// True when the press was a shortcut key and is taken.
    fun handle(event: KeyEvent): Boolean {
        if (!enabled) return false
        val key = keyName(event) ?: return false
        // A press counts on key down, or on key up when its down went elsewhere (as it can
        // while a dialog window takes focus).
        val counts = synchronized(lock) {
            when (event.action) {
                KeyEvent.ACTION_DOWN -> { pressed.add(event.keyCode); event.repeatCount == 0 }
                KeyEvent.ACTION_UP -> !pressed.remove(event.keyCode)
                else -> false
            }
        }
        if (counts) {
            var modifiers = 0
            if (event.isCtrlPressed || event.isMetaPressed) modifiers = modifiers or 1
            if (event.isShiftPressed) modifiers = modifiers or 2
            if (event.isAltPressed) modifiers = modifiers or 4
            synchronized(lock) { queue.add("$key $modifiers") }
        }
        return true
    }

    /// "a"..."z", "0"..."9", "space", ".", "+", "=", or a named key.
    private fun keyName(event: KeyEvent): String? = when (val code = event.keyCode) {
        in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> ('a' + (code - KeyEvent.KEYCODE_A)).toString()
        in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> ('0' + (code - KeyEvent.KEYCODE_0)).toString()
        in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> ('0' + (code - KeyEvent.KEYCODE_NUMPAD_0)).toString()
        KeyEvent.KEYCODE_SPACE -> "space"
        KeyEvent.KEYCODE_PERIOD, KeyEvent.KEYCODE_NUMPAD_DOT -> "."
        KeyEvent.KEYCODE_PLUS, KeyEvent.KEYCODE_NUMPAD_ADD -> "+"
        KeyEvent.KEYCODE_EQUALS -> "="
        KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> "delete"
        KeyEvent.KEYCODE_ESCAPE -> "escape"
        KeyEvent.KEYCODE_DPAD_LEFT -> "left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
        KeyEvent.KEYCODE_DPAD_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "down"
        // Page-turn pedals send Page Up/Down or the arrow keys.
        KeyEvent.KEYCODE_PAGE_UP -> "pageup"
        KeyEvent.KEYCODE_PAGE_DOWN -> "pagedown"
        else -> null
    }

    /// Queued presses, one "key modifiers" per line.
    fun takeEvents(): String = synchronized(lock) {
        val events = queue.joinToString("\n")
        queue.clear()
        events
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaKeyboard {
    fun setEnabled(enabled: Boolean) {
        AriaKeyboardImpl.enabled = enabled
        if (!enabled) AriaKeyboardImpl.takeEvents()
    }

    fun takeEvents(): String = AriaKeyboardImpl.takeEvents()
}

/// Composed inside the reader (ScoreReaderKeyboardShortcutView): routes the key presses of
/// the window it is in through AriaKeyboardImpl first. The reader is presented full
/// screen, which Skip shows in a dialog window with its own key dispatch.
class AriaKeyCapture : skip.ui.ContentComposer {
    @Composable
    override fun Compose(context: skip.ui.ComposeContext) {
        val view = LocalView.current
        // Navigation keys (arrows, Page Up/Down) take the window out of touch mode before the
        // callback below sees them, and Android then focuses the first button (the reader's
        // Back), which Compose draws with a focus ring. Shortcut keys move focus here instead.
        val keyFocus = remember { FocusRequester() }
        Box(Modifier.size(1.dp).focusRequester(keyFocus).focusable())
        DisposableEffect(view) {
            val window = windowOf(view)
            val original = window?.callback
            if (window == null || original == null) {
                onDispose {}
            } else {
                val wrapped = object : Window.Callback by original {
                    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                        if (!AriaKeyboardImpl.handle(event)) return original.dispatchKeyEvent(event)
                        view.post { runCatching { keyFocus.requestFocus() } }
                        return true
                    }
                }
                window.callback = wrapped
                onDispose {
                    if (window.callback === wrapped) window.callback = original
                    AriaKeyboardImpl.enabled = false
                }
            }
        }
    }

    private fun windowOf(view: android.view.View): Window? {
        (view as? DialogWindowProvider)?.let { return it.window }
        (view.parent as? DialogWindowProvider)?.let { return it.window }
        var context = view.context
        while (context is ContextWrapper) {
            if (context is Activity) return context.window
            context = context.baseContext
        }
        return null
    }
}
