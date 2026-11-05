package aria.skip

import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test

/** Opt-in screenshot audit of the real shared editing panels. No library reset.
 * Run with -e stage inspect first; choose noteX/noteY from that device's score image.
 * Test edits are undone before leaving the score. Screenshots go to external files.
 */
class EditingPanelsScreenshotTest {
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val args = InstrumentationRegistry.getArguments()
    private val ui = inst.uiAutomation
    private val directory by lazy {
        File(inst.targetContext.getExternalFilesDir(null), "editing-panel-audit").apply { mkdirs() }
    }

    @Test fun editingPanels() {
        ui.serviceInfo = ui.serviceInfo.apply {
            flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val intent = inst.targetContext.packageManager.getLaunchIntentForPackage(inst.targetContext.packageName)!!
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        inst.targetContext.startActivity(intent)
        settle(3000)
        dismissPrompts()
        shot("00-current")
        if (args.getString("stage", "inspect") == "inspect") return

        if (find("Edit score") == null && find("Done editing") == null) {
            clickContains(args.getString("score", "Wiegenlied"))
            waitFor("Edit score", 60000)
        }
        if (find("Edit score") != null) click("Edit score")
        settle(2000)
        shot("01-editor")
        if (args.getString("stage") == "reader") return

        val x = args.getString("noteX")?.toFloat()
        val y = args.getString("noteY")?.toFloat()
        if (x != null && y != null) { tap(x, y); settle(1500) }
        click("Text")
        shot("02-text-tools")
        if (args.getString("stage") != "entry") {
        click("Tempo")
        shot("03-tempo")
        waitFor("Tempo text")
        val field = nodes().first { it.className?.toString() == "android.widget.EditText" }
        field.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        tapNode(field)
        field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,
            Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "Allegro") })
        settle(1500)
        shot("04-tempo-keyboard")
        assertTempoFieldAboveKeyboard()
        // Return to the number pad without closing the editor.
        key(KeyEvent.KEYCODE_BACK)
        settle(1000)
        shot("05-tempo-after-keyboard")
        click("Cancel")
        settle(800)
        if (args.getString("stage") == "tempo") return
        }

        click("Fingering")
        for (finger in 1..5) assertInsideScreen(waitFor("Fingering $finger"))
        assertInsideScreen(waitFor("Remove fingering"))
        shot("06-fingering")
        // Merely opening the panel must leave the score untouched.
        click("Text")
        clickContains("Chord Text")
        val chordKeys = listOf(
            "C", "B", "Chord flat", "Chord sharp", "9", "11", "13", "/",
            "Erase chord character", "Enter chord and advance"
        )
        for (label in chordKeys) {
            assertInsideScreen(waitFor(label))
        }
        shot("07-chord-entry")
        click("C")
        click("min")
        click("7")
        shot("08-chord-draft")
        // Back to Text cancels the draft.
        click("Back to Text")
        shot("09-text-restored")
    }

    /** A real touch drag on an existing fingering, followed by Undo. Coordinate arguments
     * come from the reader capture for this device; the fixture is separate from user scores. */
    @Test fun fingeringPlacement() {
        val intent = inst.targetContext.packageManager.getLaunchIntentForPackage(inst.targetContext.packageName)!!
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        inst.targetContext.startActivity(intent)
        settle(3000)
        dismissPrompts()
        if (find("Edit score") == null && find("Done editing") == null) {
            clickContains("Fingering Placement QA")
            waitFor("Edit score", 60000)
        }
        if (find("Edit score") != null) click("Edit score")
        settle(2000)
        shot("finger-01-reader")
        val x = args.getString("fingerX")?.toFloat() ?: return
        val y = args.getString("fingerY")?.toFloat() ?: return
        tap(x, y)
        settle(1200)
        shot("finger-02-selected")
        assertNotNull("Coordinate did not select the fingering text action strip", find("Edit"))
        assertFalse("Fixture has prior test edits", waitFor("Undo").isEnabled)
        val density = inst.targetContext.resources.displayMetrics.density
        val now = SystemClock.uptimeMillis()
        fun touch(action: Int, time: Long, px: Float, py: Float) {
            val event = MotionEvent.obtain(now, time, action, px, py, 0)
            event.source = InputDevice.SOURCE_TOUCHSCREEN
            ui.injectInputEvent(event, true); event.recycle()
        }
        touch(MotionEvent.ACTION_DOWN, now, x, y)
        SystemClock.sleep(180)
        val dx = 12f * density
        val dy = -12f * density
        for (i in 1..10) {
            touch(MotionEvent.ACTION_MOVE, SystemClock.uptimeMillis(), x + dx * i / 10, y + dy * i / 10)
            SystemClock.sleep(30)
        }
        shot("finger-03-drag-guide")
        touch(MotionEvent.ACTION_UP, SystemClock.uptimeMillis(), x + dx, y + dy)
        settle(2000)
        shot("finger-04-moved")
        assertTrue("Touch drag did not reach the engine", waitFor("Undo").isEnabled)
        click("Undo")
        settle(3000)
        shot("finger-05-undone")
        assertFalse("Fingering drag created more than one undo command", waitFor("Undo").isEnabled)
    }

    private fun dismissPrompts() {
        repeat(5) {
            val node = listOf("Not Now", "Got it", "Close").firstNotNullOfOrNull { find(it) }
                ?: return
            tapNode(node); settle(600)
        }
    }
    private fun nodes(): List<AccessibilityNodeInfo> {
        ui.clearCache()
        val result = ArrayList<AccessibilityNodeInfo>()
        fun visit(node: AccessibilityNodeInfo) {
            result.add(node)
            for (i in 0 until node.childCount) node.getChild(i)?.let { visit(it) }
        }
        ui.windows.filter { it.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION }
            .maxByOrNull { it.layer }?.root?.let { visit(it) }
        if (result.isEmpty()) ui.rootInActiveWindow?.let { visit(it) }
        return result
    }
    private fun label(node: AccessibilityNodeInfo) = listOfNotNull(node.text, node.contentDescription).joinToString(" | ")
    private fun find(text: String) = nodes().firstOrNull {
        it.isVisibleToUser && (it.text?.toString() == text || it.contentDescription?.toString() == text)
    }
    private fun waitFor(text: String, timeout: Long = 12000): AccessibilityNodeInfo {
        val end = SystemClock.uptimeMillis() + timeout
        while (SystemClock.uptimeMillis() < end) {
            find(text)?.let { return it }
            SystemClock.sleep(200)
        }
        shot("failure-${text.replace(' ', '-')}")
        error("Missing $text; see screenshot and accessibility dump")
    }
    private fun click(text: String) {
        // The phone's text tools deliberately scroll horizontally.
        if (find(text) == null && text in listOf("Tempo", "Fingering", "Chord Text")) {
            repeat(3) {
                if (find(text) != null) return@repeat
                val row = nodes().lastOrNull {
                    it.className?.toString() == "android.widget.HorizontalScrollView" &&
                        Rect().also { r -> it.getBoundsInScreen(r) }.height() > 80
                }
                row?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                settle(400)
            }
        }
        tapNode(waitFor(text)); settle(700)
    }
    private fun clickContains(text: String) {
        val end = SystemClock.uptimeMillis() + 12000
        while (SystemClock.uptimeMillis() < end) {
            val node = nodes().firstOrNull { it.isVisibleToUser && label(it).contains(text, ignoreCase = true) }
            if (node != null) { tapNode(node); settle(800); return }
            SystemClock.sleep(200)
        }
        shot("failure-contains"); error("Missing label containing $text")
    }
    private fun tapNode(node: AccessibilityNodeInfo) {
        assertTrue("Disabled: ${label(node)}", node.isEnabled)
        val bounds = Rect(); node.getBoundsInScreen(bounds)
        tap(bounds.exactCenterX(), bounds.exactCenterY())
    }
    private fun assertInsideScreen(node: AccessibilityNodeInfo) {
        val bounds = Rect(); node.getBoundsInScreen(bounds)
        val display = inst.targetContext.resources.displayMetrics
        assertTrue("Clipped control: ${label(node)} $bounds", bounds.left >= 0 && bounds.top >= 0 &&
            bounds.right <= display.widthPixels && bounds.bottom <= display.heightPixels && !bounds.isEmpty)
    }
    private fun assertTempoFieldAboveKeyboard() {
        val field = nodes().first { it.className?.toString() == "android.widget.EditText" }
        val bounds = Rect(); field.getBoundsInScreen(bounds)
        val density = inst.targetContext.resources.displayMetrics.density
        val keyboard = ui.windows.firstOrNull {
            it.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD
        } ?: error("Software keyboard must be visible for this regression check")
        val keyboardBounds = Rect(); keyboard.getBoundsInScreen(keyboardBounds)
        assertTrue("Tempo field is clipped: $bounds", field.isVisibleToUser && bounds.height() >= 40 * density)
        assertTrue("Keyboard obscures tempo text: field=$bounds keyboard=$keyboardBounds",
            bounds.bottom <= keyboardBounds.top)
        assertEquals("Tempo text input did not reach the field", "Allegro", field.text?.toString())
    }
    private fun tap(x: Float, y: Float) {
        val now = SystemClock.uptimeMillis()
        for ((action, delta) in listOf(MotionEvent.ACTION_DOWN to 0L, MotionEvent.ACTION_UP to 60L)) {
            val event = MotionEvent.obtain(now, now + delta, action, x, y, 0)
            event.source = InputDevice.SOURCE_TOUCHSCREEN
            ui.injectInputEvent(event, true); event.recycle()
        }
    }
    private fun key(code: Int) {
        ui.injectInputEvent(KeyEvent(KeyEvent.ACTION_DOWN, code), true)
        ui.injectInputEvent(KeyEvent(KeyEvent.ACTION_UP, code), true)
    }
    private fun settle(ms: Long = 600) { SystemClock.sleep(ms); inst.waitForIdleSync() }
    private fun shot(name: String) {
        settle(400)
        ui.takeScreenshot()!!.also { bitmap ->
            File(directory, "$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
        File(directory, "$name.txt").writeText(nodes().joinToString("\n") {
            val bounds = Rect(); it.getBoundsInScreen(bounds)
            "${it.className} enabled=${it.isEnabled} clickable=${it.isClickable} $bounds ${label(it)}"
        })
    }
}
