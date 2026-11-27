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

    /** Samsung report (November 2026): the blue selection is drawn above the black note.
     * Makes a new piano score, enters notes with the piano keys (no score taps involved) and
     * saves screenshots; each entered note is selected, so blue and black can be compared. */
    @Test fun selectionOverlay() {
        writeDeviceInfo()
        val rasterLog = File(directory, "raster-calls.txt").apply { writeText("") }
        val count = java.util.concurrent.atomic.AtomicInteger()
        val misshapen = java.util.concurrent.CopyOnWriteArrayList<String>()
        AriaRasterCapture.record = { pdf, opaque, pageWidth, pageHeight, width, height, crop ->
            val n = count.incrementAndGet()
            // A whole-page bitmap must have the page's shape, or the page draws off its
            // selections and taps (Samsung, November 2026).
            if (opaque && width > 0 && height > 0) {
                val wanted = pageHeight.toDouble() / pageWidth
                val asked = height.toDouble() / width
                if (kotlin.math.abs(asked / wanted - 1) > 0.01) misshapen += "#$n ${width}x$height for ${pageWidth}x$pageHeight pt"
            }
            val kind = if (opaque) "page" else "overlay"
            if (n <= 40) File(directory, "raster-%02d-$kind.pdf".format(n)).writeBytes(pdf)
            synchronized(rasterLog) {
                rasterLog.appendText("$n $kind pdfPoints=${pageWidth}x$pageHeight pixels=${width}x$height crop=${crop.joinToString()}\n")
            }
        }
        val intent = inst.targetContext.packageManager.getLaunchIntentForPackage(inst.targetContext.packageName)!!
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        inst.targetContext.startActivity(intent)
        settle(4000)
        dismissPrompts()
        shot("overlay-00-library")
        click("New Score")
        settle(1500)
        click("Create Score")
        settle(6000)
        find("Skip")?.let { tapNode(it); settle(1500) }
        dismissPrompts()
        shot("overlay-01-editor")
        click("Quarter")
        // The keyboard needs a staff position first: tap the treble staff's middle line,
        // found in the screenshot (long dark rows; a rest is too short to pass).
        val screen = ui.takeScreenshot()!!
        val x = (screen.width * 0.6f).toInt()
        fun dark(px: Int, py: Int) = android.graphics.Color.red(screen.getPixel(px, py)) < 90
        val rows = (screen.height / 8 until screen.height * 6 / 10).filter { y ->
            dark(x, y) && dark(x - 30, y) && dark(x + 30, y)
        }
        val lines = rows.filterIndexed { i, y -> i == 0 || y - rows[i - 1] > 2 }
        screen.recycle()
        File(directory, "staff-lines.txt").writeText("x=$x lines=$lines\n")
        // Five evenly spaced lines; skips title text the column happens to cross.
        val staff = (0..lines.size - 5).firstOrNull { i ->
            val gaps = (i until i + 4).map { lines[it + 1] - lines[it] }
            gaps.max() - gaps.min() <= 2 && gaps.min() > 4
        }
        assertNotNull("No treble staff found: $lines", staff)
        tap(x.toFloat(), lines[staff!! + 2].toFloat())
        settle(2500)
        shot("overlay-02-note-1")
        for (index in 2..3) {
            val key = find(args.getString("key", "C3")) ?: break
            tapNode(key)
            settle(2500)
            shot("overlay-0${index + 1}-note-$index")
        }
        AriaRasterCapture.record = null
        assertTrue("Page bitmaps not shaped like the page: $misshapen", misshapen.isEmpty())
    }

    /** The same rasterizer the app uses: a whole page, then a crop of it, as the selection
     * overlay is drawn. On a correct PdfRenderer the box lands at the same page position. */
    @Test fun pdfCropAlignment() {
        writeDeviceInfo()
        val document = android.graphics.pdf.PdfDocument()
        val pageWidth = 595; val pageHeight = 842
        val page = document.startPage(android.graphics.pdf.PdfDocument.PageInfo.Builder(pageWidth, pageHeight, 1).create())
        val box = android.graphics.RectF(300f, 400f, 320f, 410f)
        page.canvas.drawRect(box, android.graphics.Paint().apply { color = android.graphics.Color.BLACK })
        document.finishPage(page)
        val pdf = java.io.ByteArrayOutputStream().also { document.writeTo(it) }.toByteArray()
        document.close()

        val width = 1080
        val height = (width * pageHeight.toDouble() / pageWidth).toInt()
        val lines = ArrayList<String>()
        fun found(bitmap: android.graphics.Bitmap): android.graphics.RectF? {
            var minX = Int.MAX_VALUE; var minY = Int.MAX_VALUE; var maxX = -1; var maxY = -1
            for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                val p = bitmap.getPixel(x, y)
                if (android.graphics.Color.alpha(p) > 128 && android.graphics.Color.red(p) < 100) {
                    minX = minOf(minX, x); maxX = maxOf(maxX, x); minY = minOf(minY, y); maxY = maxOf(maxY, y)
                }
            }
            return if (maxX < 0) null else android.graphics.RectF(minX.toFloat(), minY.toFloat(), maxX + 1f, maxY + 1f)
        }
        val full = AriaPdfRasterizerImpl.renderBitmap(pdf, width, height, true, 0.0, 0.0, 1.0, 1.0)!!
        val fullBox = found(full)!!
        lines += "expected px: ${box.left / pageWidth * width},${box.top / pageHeight * height} - ${box.right / pageWidth * width},${box.bottom / pageHeight * height}"
        lines += "full page px: $fullBox"
        val crops = listOf(doubleArrayOf(0.4, 0.4, 0.2, 0.1), doubleArrayOf(0.45, 0.45, 0.1, 0.05), doubleArrayOf(0.0, 0.3, 1.0, 0.3))
        for (crop in crops) {
            val cw = (width * crop[2]).toInt(); val ch = (height * crop[3]).toInt()
            val bitmap = AriaPdfRasterizerImpl.renderBitmap(pdf, cw, ch, false, crop[0], crop[1], crop[2], crop[3])!!
            val b = found(bitmap)
            // Back to whole-page pixels, as AndroidPageRect places the crop.
            val mapped = b?.let {
                android.graphics.RectF((crop[0] * width + it.left * crop[2] * width / cw).toFloat(),
                    (crop[1] * height + it.top * crop[3] * height / ch).toFloat(),
                    (crop[0] * width + it.right * crop[2] * width / cw).toFloat(),
                    (crop[1] * height + it.bottom * crop[3] * height / ch).toFloat())
            }
            lines += "crop ${crop.joinToString()} (${cw}x$ch): in-crop $b -> page $mapped" +
                (mapped?.let { "  dx=${it.left - fullBox.left} dy=${it.top - fullBox.top}" } ?: "  MISSING")
        }
        File(directory, "pdf-crop-alignment.txt").writeText(lines.joinToString("\n") + "\n")
    }

    private fun writeDeviceInfo() {
        val metrics = inst.targetContext.resources.displayMetrics
        val b = android.os.Build.VERSION.SDK_INT
        val ext = if (b >= 30) android.os.ext.SdkExtensions.getExtensionVersion(30) else -1
        File(directory, "device.txt").writeText(
            "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} (${android.os.Build.DEVICE}) " +
            "sdk=$b ext=$ext fingerprint=${android.os.Build.FINGERPRINT}\n" +
            "display ${metrics.widthPixels}x${metrics.heightPixels} density=${metrics.density} dpi=${metrics.densityDpi}\n")
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
