package aria.skip

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import java.io.ByteArrayOutputStream
import skip.foundation.ProcessInfo
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/// The drawing behind the Core Graphics, Core Image and Core Video stand-ins in the
/// UIKit and CoreImage shims (Sources/AndroidShims). Swift keeps handles to bitmaps,
/// drawing contexts and PDF documents held here, and sends drawing as text commands.
///
/// Coordinates follow Core Graphics: a context's user space starts with y up from the
/// bottom-left corner, as a CGBitmapContext does; Swift applies UIKit's flip itself.
object AriaGraphicsImpl {
    private val lock = Any()
    private val bitmaps = HashMap<Int, Bitmap>()
    private val contexts = HashMap<Int, DrawingContext>()
    private val documents = HashMap<Int, PdfDocument>()
    private var nextId = 1

    private fun newId(): Int = nextId++

    private fun register(bitmap: Bitmap): Int = synchronized(lock) { newId().also { bitmaps[it] = bitmap } }

    fun bitmap(id: Int): Bitmap? = synchronized(lock) { bitmaps[id] }

    // MARK: Bitmaps

    fun createBitmap(width: Int, height: Int): Int =
        register(Bitmap.createBitmap(max(1, width), max(1, height), Bitmap.Config.ARGB_8888))

    fun release(id: Int) {
        synchronized(lock) { bitmaps.remove(id) }?.recycle()
    }

    fun copy(id: Int): Int {
        val source = bitmap(id) ?: return 0
        return register(source.copy(Bitmap.Config.ARGB_8888, true))
    }

    fun decode(data: ByteArray): Int {
        val options = BitmapFactory.Options().apply {
            inMutable = true
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return 0
        return register(bitmap)
    }

    fun canDecode(data: ByteArray): Boolean {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, options)
        return options.outWidth > 0 && options.outHeight > 0
    }

    /// Decoded at most `maximumSize` pixels on its long side (0: full size), turned
    /// upright by its EXIF orientation, as ImageIO's thumbnails with transform are.
    fun decodeThumbnail(data: ByteArray, maximumSize: Int): Int {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return 0
        var sample = 1
        val longSide = max(bounds.outWidth, bounds.outHeight)
        if (maximumSize > 0) while (longSide / (sample * 2) >= maximumSize) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return 0
        val rotation = try {
            when (android.media.ExifInterface(java.io.ByteArrayInputStream(data))
                .getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)) {
                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (error: Exception) { 0f }
        val scale = if (maximumSize > 0) min(1f, maximumSize.toFloat() / max(bitmap.width, bitmap.height)) else 1f
        if (rotation != 0f || scale < 1f) {
            val matrix = Matrix()
            matrix.postScale(scale, scale)
            matrix.postRotate(rotation)
            val transformed = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (transformed !== bitmap) bitmap.recycle()
            bitmap = transformed
        }
        return register(if (bitmap.isMutable) bitmap else bitmap.copy(Bitmap.Config.ARGB_8888, true))
    }

    fun png(id: Int): ByteArray? {
        val bitmap = bitmap(id) ?: return null
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        return output.toByteArray()
    }

    fun width(id: Int): Int = bitmap(id)?.width ?: 0
    fun height(id: Int): Int = bitmap(id)?.height ?: 0

    fun clear(id: Int) {
        bitmap(id)?.eraseColor(Color.TRANSPARENT)
    }

    /// Gray: one luminance byte per pixel, as if drawn over black (Core Graphics gray
    /// contexts start black). Otherwise BGRA, premultiplied: Core Graphics'
    /// premultipliedFirst | byteOrder32Little.
    fun readPixels(id: Int, gray: Boolean): ByteArray {
        val bitmap = bitmap(id) ?: return ByteArray(0)
        val count = bitmap.width * bitmap.height
        val rgba = ByteBuffer.allocate(bitmap.rowBytes * bitmap.height)
        bitmap.copyPixelsToBuffer(rgba)
        val source = rgba.array()
        val rowBytes = bitmap.rowBytes
        val width = bitmap.width
        if (gray) {
            val output = ByteArray(count)
            for (y in 0 until bitmap.height) {
                var index = y * rowBytes
                var out = y * width
                for (x in 0 until width) {
                    val r = source[index].toInt() and 0xFF
                    val g = source[index + 1].toInt() and 0xFF
                    val b = source[index + 2].toInt() and 0xFF
                    output[out] = ((77 * r + 150 * g + 29 * b + 128) shr 8).toByte()
                    index += 4
                    out += 1
                }
            }
            return output
        }
        val output = ByteArray(count * 4)
        for (y in 0 until bitmap.height) {
            var index = y * rowBytes
            var out = y * width * 4
            for (x in 0 until width) {
                output[out] = source[index + 2]
                output[out + 1] = source[index + 1]
                output[out + 2] = source[index]
                output[out + 3] = source[index + 3]
                index += 4
                out += 4
            }
        }
        return output
    }

    fun writePixels(id: Int, data: ByteArray, gray: Boolean) {
        val bitmap = bitmap(id) ?: return
        val width = bitmap.width
        val rowBytes = bitmap.rowBytes
        val rgba = ByteArray(rowBytes * bitmap.height)
        for (y in 0 until bitmap.height) {
            var index = y * rowBytes
            for (x in 0 until width) {
                if (gray) {
                    val value = data[y * width + x]
                    rgba[index] = value
                    rgba[index + 1] = value
                    rgba[index + 2] = value
                    rgba[index + 3] = 0xFF.toByte()
                } else {
                    val source = (y * width + x) * 4
                    rgba[index] = data[source + 2]
                    rgba[index + 1] = data[source + 1]
                    rgba[index + 2] = data[source]
                    rgba[index + 3] = data[source + 3]
                }
                index += 4
            }
        }
        bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
    }

    // MARK: Drawing contexts

    fun createContext(bitmapId: Int): Int {
        val bitmap = bitmap(bitmapId) ?: return 0
        return synchronized(lock) { newId().also { contexts[it] = DrawingContext(bitmap) } }
    }

    fun releaseContext(id: Int) {
        synchronized(lock) { contexts.remove(id) }
    }

    fun run(contextId: Int, commands: String) {
        if (BuildConfig.ARIA_VIDEO_AUDIT) AriaVideoAudit.thread("canvas")
        val context = synchronized(lock) { contexts[contextId] } ?: return
        try {
            context.run(commands)
        } catch (error: Exception) {
            android.util.Log.e("Aria", "Drawing failed", error)
        }
    }

    fun drawText(contextId: Int, text: String, family: String, bold: Boolean, italic: Boolean, size: Double,
                 red: Double, green: Double, blue: Double, alpha: Double,
                 x: Double, y: Double, width: Double, mode: Int, alignment: Int) {
        val context = synchronized(lock) { contexts[contextId] } ?: return
        context.drawText(text, AriaFonts.typeface(family, bold, italic), size.toFloat(),
                         colorOf(red, green, blue, alpha), x.toFloat(), y.toFloat(), width.toFloat(), mode, alignment)
    }

    /// "width height" of the text: one line (mode 0), wrapped to `width` (1) or one line
    /// cut to `width` (2).
    fun measureText(text: String, family: String, bold: Boolean, italic: Boolean, size: Double,
                    width: Double, mode: Int): String {
        val paint = textPaint(AriaFonts.typeface(family, bold, italic), size.toFloat(), Color.BLACK)
        if (mode == 1) {
            val layout = staticLayout(text, paint, width.toFloat(), Layout.Alignment.ALIGN_NORMAL, false)
            var widest = 0f
            for (line in 0 until layout.lineCount) widest = max(widest, layout.getLineWidth(line))
            return "$widest ${layout.height}"
        }
        val metrics = paint.fontMetrics
        var lineWidth = paint.measureText(text)
        if (mode == 2) lineWidth = min(lineWidth, width.toFloat())
        return "$lineWidth ${metrics.descent - metrics.ascent}"
    }

    internal fun textPaint(typeface: Typeface, size: Float, color: Int): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            textSize = size
            this.color = color
        }

    internal fun staticLayout(text: String, paint: TextPaint, width: Float, alignment: Layout.Alignment,
                              singleLine: Boolean): StaticLayout {
        val layoutWidth = max(1, ceil(width.toDouble()).toInt())
        val builder = StaticLayout.Builder.obtain(text, 0, text.length, paint, layoutWidth)
            .setAlignment(alignment)
            .setIncludePad(false)
        if (singleLine) {
            builder.setMaxLines(1).setEllipsize(TextUtils.TruncateAt.END)
        }
        return builder.build()
    }

    internal fun colorOf(red: Double, green: Double, blue: Double, alpha: Double): Int =
        Color.argb(channel(alpha), channel(red), channel(green), channel(blue))

    private fun channel(value: Double): Int = (value.coerceIn(0.0, 1.0) * 255).roundToInt()

    // MARK: PDF documents

    fun openPdf(data: ByteArray): Int {
        val file = File.createTempFile("aria-video-page", ".pdf")
        return try {
            file.writeBytes(data)
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(descriptor)
            synchronized(lock) { newId().also { documents[it] = PdfDocument(file, descriptor, renderer) } }
        } catch (error: Exception) {
            android.util.Log.e("Aria", "Opening a PDF failed", error)
            file.delete()
            0
        }
    }

    fun closePdf(id: Int) {
        val document = synchronized(lock) { documents.remove(id) } ?: return
        synchronized(document) {
            document.renderer.close()
            document.descriptor.close()
            document.file.delete()
        }
    }

    /// "width height" of a page in points; empty when there is no such page.
    fun pdfPageSize(id: Int, index: Int): String {
        val document = synchronized(lock) { documents[id] } ?: return ""
        synchronized(document) {
            if (index < 0 || index >= document.renderer.pageCount) return ""
            document.renderer.openPage(index).use { page -> return "${page.width} ${page.height}" }
        }
    }

    internal fun renderPdf(id: Int, index: Int, bitmap: Bitmap, matrix: Matrix) {
        val document = synchronized(lock) { documents[id] } ?: return
        synchronized(document) {
            if (index < 0 || index >= document.renderer.pageCount) return
            document.renderer.openPage(index).use { page ->
                // Page space is top-left; Core Graphics draws PDF pages y up.
                val pageMatrix = Matrix()
                pageMatrix.setScale(1f, -1f)
                pageMatrix.postTranslate(0f, page.height.toFloat())
                pageMatrix.postConcat(matrix)
                page.render(bitmap, null, pageMatrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            }
        }
    }

    // MARK: Core Image

    /// Renders a Core Image recipe (see CoreImage.swift) into the bitmap, replacing it.
    fun ciRender(bitmapId: Int, recipe: String) {
        if (BuildConfig.ARIA_VIDEO_AUDIT) AriaVideoAudit.thread("ciRender")
        val bitmap = bitmap(bitmapId) ?: return
        bitmap.eraseColor(Color.TRANSPARENT)
        val canvas = Canvas(bitmap)
        AriaImageRecipe(recipe).draw(canvas, bitmap.width, bitmap.height, 0f, 0f)
    }

    /// The part of the recipe's image in the rect (Core Image coordinates, y up) as a new bitmap.
    fun ciCreate(recipe: String, x: Double, y: Double, width: Int, height: Int): Int {
        if (BuildConfig.ARIA_VIDEO_AUDIT) AriaVideoAudit.thread("ciCreate")
        val bitmap = Bitmap.createBitmap(max(1, width), max(1, height), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        AriaImageRecipe(recipe).draw(canvas, width, height, x.toFloat(), y.toFloat())
        return register(bitmap)
    }

    private class PdfDocument(val file: File, val descriptor: ParcelFileDescriptor, val renderer: PdfRenderer)
}

/// One Core Graphics context over a bitmap, with its graphics state.
internal class DrawingContext(private val bitmap: Bitmap) {
    private class State(
        var fill: Int = Color.BLACK,
        var stroke: Int = Color.BLACK,
        var lineWidth: Float = 1f,
        var cap: Paint.Cap = Paint.Cap.BUTT,
        var alpha: Float = 1f,
        var shadow: Shadow? = null
    ) {
        fun copy() = State(fill, stroke, lineWidth, cap, alpha, shadow)
    }

    private class Shadow(val dx: Float, val dy: Float, val blur: Float, val color: Int)

    /// A transparency layer: drawing goes to its own bitmap until it ends.
    private class Layer(val bitmap: Bitmap, val canvas: Canvas, val parent: Canvas, val shadow: Shadow?, val alpha: Float)

    private var canvas = Canvas(bitmap)
    private var target = bitmap
    private var state = State()
    private val states = ArrayList<State>()
    private val layers = ArrayList<Layer>()
    private var path = Path()

    init {
        // Core Graphics' bitmap contexts are y up from the bottom-left corner.
        canvas.translate(0f, bitmap.height.toFloat())
        canvas.scale(1f, -1f)
    }

    private fun paint(color: Int, style: Paint.Style): Paint {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.style = style
        paint.color = color
        paint.alpha = (Color.alpha(color) * state.alpha).roundToInt().coerceIn(0, 255)
        if (style == Paint.Style.STROKE) {
            paint.strokeWidth = state.lineWidth
            paint.strokeCap = state.cap
        }
        state.shadow?.let { shadow ->
            if (layers.isEmpty() || layers.last().shadow !== shadow) {
                paint.setShadowLayer(max(0.01f, shadow.blur * 0.75f), shadow.dx, shadow.dy, shadow.color)
            }
        }
        return paint
    }

    fun run(commands: String) {
        for (line in commands.split('\n')) {
            if (line.isEmpty()) continue
            val parts = line.split(' ')
            val f = { index: Int -> parts[index].toFloat() }
            when (parts[0]) {
                "save" -> {
                    canvas.save()
                    states.add(state.copy())
                }
                "restore" -> {
                    if (states.isNotEmpty()) {
                        canvas.restore()
                        state = states.removeAt(states.size - 1)
                    }
                }
                "ctm" -> {
                    val matrix = Matrix()
                    matrix.setValues(floatArrayOf(f(1), f(3), f(5), f(2), f(4), f(6), 0f, 0f, 1f))
                    canvas.concat(matrix)
                }
                "fillColor" -> state.fill = AriaGraphicsImpl.colorOf(parts[1].toDouble(), parts[2].toDouble(), parts[3].toDouble(), parts[4].toDouble())
                "strokeColor" -> state.stroke = AriaGraphicsImpl.colorOf(parts[1].toDouble(), parts[2].toDouble(), parts[3].toDouble(), parts[4].toDouble())
                "lineWidth" -> state.lineWidth = f(1)
                "cap" -> state.cap = when (parts[1]) { "1" -> Paint.Cap.ROUND; "2" -> Paint.Cap.SQUARE; else -> Paint.Cap.BUTT }
                "alpha" -> state.alpha = f(1).coerceIn(0f, 1f)
                "shadow" -> state.shadow = if (f(3) < 0) null else
                    Shadow(f(1), f(2), f(3), AriaGraphicsImpl.colorOf(parts[4].toDouble(), parts[5].toDouble(), parts[6].toDouble(), parts[7].toDouble()))
                "pathRect" -> path.addRect(f(1), f(2), f(1) + f(3), f(2) + f(4), Path.Direction.CW)
                "pathRound" -> {
                    val radii = floatArrayOf(f(5), f(5), f(6), f(6), f(7), f(7), f(8), f(8))
                    path.addRoundRect(RectF(f(1), f(2), f(1) + f(3), f(2) + f(4)), radii, Path.Direction.CW)
                }
                "pathEllipse" -> path.addOval(RectF(f(1), f(2), f(1) + f(3), f(2) + f(4)), Path.Direction.CW)
                "pathMove" -> path.moveTo(f(1), f(2))
                "pathLine" -> path.lineTo(f(1), f(2))
                "fillPath" -> {
                    canvas.drawPath(path, paint(state.fill, Paint.Style.FILL))
                    path = Path()
                }
                "strokePath" -> {
                    canvas.drawPath(path, paint(state.stroke, Paint.Style.STROKE))
                    path = Path()
                }
                "clipPath" -> {
                    canvas.clipPath(path)
                    path = Path()
                }
                "fillRect" -> canvas.drawRect(f(1), f(2), f(1) + f(3), f(2) + f(4), paint(state.fill, Paint.Style.FILL))
                "fillEllipse" -> canvas.drawOval(f(1), f(2), f(1) + f(3), f(2) + f(4), paint(state.fill, Paint.Style.FILL))
                "clearRect" -> {
                    val clear = Paint()
                    clear.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
                    canvas.drawRect(f(1), f(2), f(1) + f(3), f(2) + f(4), clear)
                }
                "clipRect" -> canvas.clipRect(f(1), f(2), f(1) + f(3), f(2) + f(4))
                "segments" -> {
                    val paint = paint(state.stroke, Paint.Style.STROKE)
                    var index = 1
                    while (index + 3 < parts.size) {
                        canvas.drawLine(f(index), f(index + 1), f(index + 2), f(index + 3), paint)
                        index += 4
                    }
                }
                "linear", "radial" -> drawGradient(parts)
                "image" -> {
                    // Core Graphics semantics: the image's first row at the rect's maxY.
                    val image = AriaGraphicsImpl.bitmap(parts[1].toInt()) ?: continue
                    canvas.save()
                    canvas.translate(f(2), f(3) + f(5))
                    canvas.scale(f(4) / image.width, -f(5) / image.height)
                    val paint = paint(Color.BLACK, Paint.Style.FILL)
                    paint.isFilterBitmap = parts.getOrNull(6) != "0"
                    canvas.drawBitmap(image, 0f, 0f, paint)
                    canvas.restore()
                }
                "upright" -> {
                    // UIKit semantics (UIImage.draw(in:)): first row at the rect's minY.
                    val image = AriaGraphicsImpl.bitmap(parts[1].toInt()) ?: continue
                    val paint = paint(Color.BLACK, Paint.Style.FILL)
                    paint.isFilterBitmap = true
                    canvas.drawBitmap(image, null, RectF(f(2), f(3), f(2) + f(4), f(3) + f(5)), paint)
                }
                "pdf" -> {
                    @Suppress("DEPRECATION")
                    val matrix = canvas.matrix
                    AriaGraphicsImpl.renderPdf(parts[1].toInt(), parts[2].toInt(), target, matrix)
                }
                "beginLayer" -> beginLayer()
                "endLayer" -> endLayer()
            }
        }
    }

    private fun drawGradient(parts: List<String>) {
        val radial = parts[0] == "radial"
        val first = if (radial) 4 else 5
        val count = parts[first].toInt()
        val colors = IntArray(count)
        val positions = FloatArray(count)
        for (stop in 0 until count) {
            val index = first + 1 + stop * 5
            colors[stop] = AriaGraphicsImpl.colorOf(parts[index].toDouble(), parts[index + 1].toDouble(),
                                                    parts[index + 2].toDouble(), parts[index + 3].toDouble())
            positions[stop] = parts[index + 4].toFloat()
        }
        val paint = paint(Color.BLACK, Paint.Style.FILL)
        if (radial) {
            val radius = max(0.01f, parts[3].toFloat())
            paint.shader = RadialGradient(parts[1].toFloat(), parts[2].toFloat(), radius, colors, positions, Shader.TileMode.CLAMP)
            canvas.drawCircle(parts[1].toFloat(), parts[2].toFloat(), radius, paint)
        } else {
            paint.shader = LinearGradient(parts[1].toFloat(), parts[2].toFloat(), parts[3].toFloat(), parts[4].toFloat(),
                                          colors, positions, Shader.TileMode.CLAMP)
            canvas.drawPaint(paint)
        }
    }

    private fun beginLayer() {
        val layerBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val layerCanvas = Canvas(layerBitmap)
        @Suppress("DEPRECATION")
        layerCanvas.setMatrix(canvas.matrix)
        layers.add(Layer(layerBitmap, layerCanvas, canvas, state.shadow, state.alpha))
        canvas = layerCanvas
        target = layerBitmap
    }

    private fun endLayer() {
        if (layers.isEmpty()) return
        val layer = layers.removeAt(layers.size - 1)
        canvas = layer.parent
        target = layers.lastOrNull()?.bitmap ?: bitmap
        canvas.save()
        @Suppress("DEPRECATION")
        canvas.setMatrix(Matrix())
        layer.shadow?.let { shadow ->
            // The layer's shadow: its coverage, blurred and tinted, offset below it.
            val blur = Paint()
            blur.maskFilter = BlurMaskFilter(max(0.5f, shadow.blur * 0.75f), BlurMaskFilter.Blur.NORMAL)
            val offset = IntArray(2)
            val coverage = layer.bitmap.extractAlpha(blur, offset)
            val tint = Paint(Paint.ANTI_ALIAS_FLAG)
            tint.color = shadow.color
            canvas.drawBitmap(coverage, offset[0] + shadow.dx, offset[1] + shadow.dy, tint)
            coverage.recycle()
        }
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        paint.alpha = (layer.alpha * 255).roundToInt()
        canvas.drawBitmap(layer.bitmap, 0f, 0f, paint)
        canvas.restore()
        layer.bitmap.recycle()
    }

    /// UIKit text drawing, at the user space position (y down: Swift flips UIKit contexts).
    fun drawText(text: String, typeface: Typeface, size: Float, color: Int, x: Float, y: Float, width: Float,
                 mode: Int, alignment: Int) {
        val paint = AriaGraphicsImpl.textPaint(typeface, size, color)
        paint.alpha = (Color.alpha(color) * state.alpha).roundToInt().coerceIn(0, 255)
        val align = when (alignment) {
            1 -> Layout.Alignment.ALIGN_CENTER
            2 -> Layout.Alignment.ALIGN_OPPOSITE
            else -> Layout.Alignment.ALIGN_NORMAL
        }
        canvas.save()
        canvas.translate(x, y)
        if (mode == 0) {
            canvas.drawText(text, 0f, -paint.fontMetrics.ascent, paint)
        } else {
            AriaGraphicsImpl.staticLayout(text, paint, width, align, mode == 2).draw(canvas)
        }
        canvas.restore()
    }
}

/// The fonts the iOS app bundles (assets ios/Fonts), by family, and the system's.
object AriaFonts {
    private class Face(val file: String, val bold: Boolean, val italic: Boolean)

    private val families: Map<String, List<Face>> = mapOf(
        "Edwin" to listOf(Face("Edwin-Roman", false, false), Face("Edwin-Bold", true, false),
                          Face("Edwin-Italic", false, true), Face("Edwin-BdIta", true, true)),
        "FreeSerif" to listOf(Face("FreeSerif", false, false), Face("FreeSerifBold", true, false),
                              Face("FreeSerifItalic", false, true), Face("FreeSerifBoldItalic", true, true)),
        "Bravura Text" to listOf(Face("BravuraText", false, false)),
        "Leland Text" to listOf(Face("LelandText", false, false)),
        "Petaluma Text" to listOf(Face("PetalumaText", false, false)),
        "Petaluma Script" to listOf(Face("PetalumaScript", false, false)),
        "Gootville Text" to listOf(Face("GootvilleText", false, false)),
        "MScore Text" to listOf(Face("MScoreText", false, false)),
        "MuseJazz Text" to listOf(Face("MuseJazzText", false, false)),
        "Finale Maestro Text" to listOf(Face("FinaleMaestroText-Regular", false, false)),
        "Finale Broadway Text" to listOf(Face("FinaleBroadwayText", false, false))
    )
    private val systemFamilies = listOf("sans-serif", "serif", "monospace")
    private val loaded = HashMap<String, Typeface>()

    /// Family names, like UIFont.familyNames.
    fun familyNames(): String = (families.keys + systemFamilies).joinToString("\n")

    /// "file bold italic" lines for a bundled family.
    fun faces(family: String): String {
        val match = families.entries.firstOrNull { it.key.equals(family, ignoreCase = true) } ?: return ""
        return match.value.joinToString("\n") { "${it.file} ${if (it.bold) 1 else 0} ${if (it.italic) 1 else 0}" }
    }

    fun typeface(family: String, bold: Boolean, italic: Boolean): Typeface {
        val faces = families.entries.firstOrNull { it.key.equals(family, ignoreCase = true) }?.value
            ?: families.values.firstOrNull { list -> list.any { it.file.equals(family, ignoreCase = true) } }
        val style = when {
            bold && italic -> Typeface.BOLD_ITALIC
            bold -> Typeface.BOLD
            italic -> Typeface.ITALIC
            else -> Typeface.NORMAL
        }
        if (faces != null) {
            val face = faces.firstOrNull { it.bold == bold && it.italic == italic } ?: faces.first()
            val typeface = synchronized(loaded) {
                loaded.getOrPut(face.file) {
                    try {
                        val name = if (face.file.startsWith("FreeSerif")) "${face.file}.ttf" else "${face.file}.otf"
                        Typeface.createFromAsset(ProcessInfo.processInfo.androidContext.assets, "ios/Fonts/$name")
                    } catch (error: Exception) {
                        Typeface.DEFAULT
                    }
                }
            }
            // A missing bold or italic face is synthesized, as iOS does.
            return if (face.bold == bold && face.italic == italic) typeface else Typeface.create(typeface, style)
        }
        val base = when (family.lowercase()) {
            "times", "times new roman", "georgia" -> "serif"
            "courier", "courier new", "menlo" -> "monospace"
            else -> family
        }
        return Typeface.create(Typeface.create(base, Typeface.NORMAL), style)
    }
}

/// Draws a Core Image recipe: a prefix expression written by CoreImage.swift.
///   I id w h        an image, extent (0, 0, w, h)
///   C r g b a       a color, infinite
///   K x y w h n     n cropped to the rect
///   T a b c d tx ty n   n transformed
///   A alpha n       n with its alpha scaled
///   O fg bg         fg composited over bg
///   D fg bg         fg added to bg
///   B sigma n       n blurred
///   E n             n clamped to its extent (blurs extend edges)
/// Core Image coordinates are y up; the canvas is y down.
internal class AriaImageRecipe(text: String) {
    private val tokens = text.split(' ').filter { it.isNotEmpty() }
    private var position = 0

    private sealed class Node {
        class Image(val bitmap: Bitmap?, val width: Float, val height: Float) : Node()
        class Fill(val color: Int) : Node()
        class Crop(val rect: RectF, val child: Node) : Node()
        class Transform(val matrix: Matrix, val child: Node) : Node()
        class Alpha(val alpha: Float, val child: Node) : Node()
        class Over(val top: Node, val bottom: Node) : Node()
        class Add(val top: Node, val bottom: Node) : Node()
        class Blur(val sigma: Float, val child: Node) : Node()
        class Clamp(val child: Node) : Node()
    }

    private fun next(): String = tokens[position++]
    private fun number(): Float = next().toFloat()

    private fun parse(): Node = when (next()) {
        "I" -> Node.Image(AriaGraphicsImpl.bitmap(next().toInt()), number(), number())
        "C" -> Node.Fill(AriaGraphicsImpl.colorOf(next().toDouble(), next().toDouble(), next().toDouble(), next().toDouble()))
        "K" -> {
            val x = number(); val y = number(); val w = number(); val h = number()
            Node.Crop(RectF(x, y, x + w, y + h), parse())
        }
        "T" -> {
            val a = number(); val b = number(); val c = number(); val d = number(); val tx = number(); val ty = number()
            val matrix = Matrix()
            matrix.setValues(floatArrayOf(a, c, tx, b, d, ty, 0f, 0f, 1f))
            Node.Transform(matrix, parse())
        }
        "A" -> {
            val alpha = number()
            Node.Alpha(alpha, parse())
        }
        "O" -> Node.Over(parse(), parse())
        "D" -> Node.Add(parse(), parse())
        "B" -> {
            val sigma = number()
            Node.Blur(sigma, parse())
        }
        "E" -> Node.Clamp(parse())
        else -> Node.Fill(Color.TRANSPARENT)
    }

    private val root: Node = parse()

    /// Draws the recipe's rect (originX, originY, width, height), in Core Image
    /// coordinates, over the whole canvas.
    fun draw(canvas: Canvas, width: Int, height: Int, originX: Float, originY: Float) {
        val base = Matrix()
        base.setTranslate(-originX, -originY)
        base.postScale(1f, -1f)
        base.postTranslate(0f, height.toFloat())
        draw(root, canvas, base, 1f, width, height)
    }

    private fun draw(node: Node, canvas: Canvas, matrix: Matrix, alpha: Float, width: Int, height: Int) {
        when (node) {
            is Node.Image -> {
                val bitmap = node.bitmap ?: return
                val imageMatrix = Matrix()
                // The bitmap's first row is the top of its extent.
                imageMatrix.setScale(node.width / bitmap.width, -node.height / bitmap.height)
                imageMatrix.postTranslate(0f, node.height)
                imageMatrix.postConcat(matrix)
                val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
                paint.alpha = (alpha * 255).roundToInt().coerceIn(0, 255)
                canvas.drawBitmap(bitmap, imageMatrix, paint)
            }
            is Node.Fill -> {
                val paint = Paint()
                paint.color = node.color
                paint.alpha = (Color.alpha(node.color) * alpha).roundToInt().coerceIn(0, 255)
                canvas.drawPaint(paint)
            }
            is Node.Crop -> {
                val rect = RectF(node.rect)
                matrix.mapRect(rect)
                canvas.save()
                canvas.clipRect(rect)
                draw(node.child, canvas, matrix, alpha, width, height)
                canvas.restore()
            }
            is Node.Transform -> {
                val combined = Matrix(node.matrix)
                combined.postConcat(matrix)
                draw(node.child, canvas, combined, alpha, width, height)
            }
            is Node.Alpha -> {
                if (isSimple(node.child)) {
                    draw(node.child, canvas, matrix, alpha * node.alpha, width, height)
                } else {
                    canvas.saveLayerAlpha(null, (alpha * node.alpha * 255).roundToInt().coerceIn(0, 255))
                    draw(node.child, canvas, matrix, 1f, width, height)
                    canvas.restore()
                }
            }
            is Node.Over -> group(canvas, alpha) { layerAlpha ->
                draw(node.bottom, canvas, matrix, layerAlpha, width, height)
                draw(node.top, canvas, matrix, layerAlpha, width, height)
            }
            is Node.Add -> group(canvas, alpha) { layerAlpha ->
                draw(node.bottom, canvas, matrix, layerAlpha, width, height)
                val add = Paint()
                add.xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD)
                canvas.saveLayer(null, add)
                draw(node.top, canvas, matrix, layerAlpha, width, height)
                canvas.restore()
            }
            is Node.Blur -> drawBlurred(node, canvas, matrix, alpha, width, height)
            is Node.Clamp -> draw(node.child, canvas, matrix, alpha, width, height)
        }
    }

    private fun isSimple(node: Node): Boolean = when (node) {
        is Node.Image, is Node.Fill -> true
        is Node.Crop -> isSimple(node.child)
        is Node.Transform -> isSimple(node.child)
        is Node.Clamp -> isSimple(node.child)
        else -> false
    }

    private inline fun group(canvas: Canvas, alpha: Float, body: (Float) -> Unit) {
        if (alpha >= 1f) {
            body(1f)
        } else {
            canvas.saveLayerAlpha(null, (alpha * 255).roundToInt().coerceIn(0, 255))
            body(1f)
            canvas.restore()
        }
    }

    /// The child drawn at a reduced size, blurred there and scaled back up: a glow or
    /// a background blur looks the same, at a fraction of the cost.
    private fun drawBlurred(node: Node.Blur, canvas: Canvas, matrix: Matrix, alpha: Float, width: Int, height: Int) {
        if (BuildConfig.ARIA_VIDEO_AUDIT) AriaVideoAudit.thread("blur")
        val reduction = when {
            node.sigma >= 16 -> 4f
            node.sigma >= 6 -> 2f
            else -> 1f
        }
        val smallWidth = max(1, ceil(width / reduction).toInt())
        val smallHeight = max(1, ceil(height / reduction).toInt())
        val small = Bitmap.createBitmap(smallWidth, smallHeight, Bitmap.Config.ARGB_8888)
        val smallCanvas = Canvas(small)
        val smallMatrix = Matrix(matrix)
        smallMatrix.postScale(1 / reduction, 1 / reduction)
        draw(node.child, smallCanvas, smallMatrix, 1f, smallWidth, smallHeight)
        AriaBlur.gaussian(small, node.sigma / reduction)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        paint.alpha = (alpha * 255).roundToInt().coerceIn(0, 255)
        canvas.drawBitmap(small, null, RectF(0f, 0f, smallWidth * reduction, smallHeight * reduction), paint)
        small.recycle()
    }
}

/// A Gaussian blur as three box blurs, with edges extended.
internal object AriaBlur {
    fun gaussian(bitmap: Bitmap, sigma: Float) {
        if (sigma < 0.3f) return
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val scratch = IntArray(pixels.size)
        for (size in boxSizes(sigma)) {
            val radius = (size - 1) / 2
            box(pixels, scratch, width, height, radius, true)
            box(scratch, pixels, width, height, radius, false)
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    private fun boxSizes(sigma: Float): IntArray {
        val ideal = sqrt(12.0 * sigma * sigma / 3 + 1)
        var lower = ideal.toInt()
        if (lower % 2 == 0) lower -= 1
        val upper = lower + 2
        val m = ((12.0 * sigma * sigma - 3 * lower * lower - 12 * lower - 9) / (-4 * lower - 4)).roundToInt()
        return IntArray(3) { if (it < m) lower else upper }
    }

    private fun box(source: IntArray, output: IntArray, width: Int, height: Int, radius: Int, horizontal: Boolean) {
        if (radius < 1) {
            System.arraycopy(source, 0, output, 0, source.size)
            return
        }
        val lines = if (horizontal) height else width
        val length = if (horizontal) width else height
        val step = if (horizontal) 1 else width
        val span = radius * 2 + 1
        for (line in 0 until lines) {
            val start = if (horizontal) line * width else line
            var a = 0; var r = 0; var g = 0; var b = 0
            for (offset in -radius..radius) {
                val pixel = source[start + offset.coerceIn(0, length - 1) * step]
                a += pixel ushr 24; r += (pixel shr 16) and 0xFF; g += (pixel shr 8) and 0xFF; b += pixel and 0xFF
            }
            for (index in 0 until length) {
                output[start + index * step] = ((a / span) shl 24) or ((r / span) shl 16) or ((g / span) shl 8) or (b / span)
                val leaving = source[start + (index - radius).coerceIn(0, length - 1) * step]
                val entering = source[start + (index + radius + 1).coerceIn(0, length - 1) * step]
                a += (entering ushr 24) - (leaving ushr 24)
                r += ((entering shr 16) and 0xFF) - ((leaving shr 16) and 0xFF)
                g += ((entering shr 8) and 0xFF) - ((leaving shr 8) and 0xFF)
                b += (entering and 0xFF) - (leaving and 0xFF)
            }
        }
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaGraphics {
    fun createBitmap(width: Int, height: Int): Int = AriaGraphicsImpl.createBitmap(width, height)
    fun release(id: Int) = AriaGraphicsImpl.release(id)
    fun copy(id: Int): Int = AriaGraphicsImpl.copy(id)
    fun decode(data: ByteArray): Int = AriaGraphicsImpl.decode(data)
    fun png(id: Int): ByteArray? = AriaGraphicsImpl.png(id)
    fun canDecode(data: ByteArray): Boolean = AriaGraphicsImpl.canDecode(data)
    fun decodeThumbnail(data: ByteArray, maximumSize: Int): Int = AriaGraphicsImpl.decodeThumbnail(data, maximumSize)
    fun width(id: Int): Int = AriaGraphicsImpl.width(id)
    fun height(id: Int): Int = AriaGraphicsImpl.height(id)
    fun clear(id: Int) = AriaGraphicsImpl.clear(id)
    fun readPixels(id: Int, gray: Boolean): ByteArray = AriaGraphicsImpl.readPixels(id, gray)
    fun writePixels(id: Int, data: ByteArray, gray: Boolean) = AriaGraphicsImpl.writePixels(id, data, gray)
    fun createContext(bitmapId: Int): Int = AriaGraphicsImpl.createContext(bitmapId)
    fun releaseContext(id: Int) = AriaGraphicsImpl.releaseContext(id)
    fun run(contextId: Int, commands: String) = AriaGraphicsImpl.run(contextId, commands)
    fun drawText(contextId: Int, text: String, family: String, bold: Boolean, italic: Boolean, size: Double,
                 red: Double, green: Double, blue: Double, alpha: Double,
                 x: Double, y: Double, width: Double, mode: Int, alignment: Int) =
        AriaGraphicsImpl.drawText(contextId, text, family, bold, italic, size, red, green, blue, alpha, x, y, width, mode, alignment)
    fun measureText(text: String, family: String, bold: Boolean, italic: Boolean, size: Double, width: Double, mode: Int): String =
        AriaGraphicsImpl.measureText(text, family, bold, italic, size, width, mode)
    fun familyNames(): String = AriaFonts.familyNames()
    fun faces(family: String): String = AriaFonts.faces(family)
    fun openPdf(data: ByteArray): Int = AriaGraphicsImpl.openPdf(data)
    fun closePdf(id: Int) = AriaGraphicsImpl.closePdf(id)
    fun pdfPageSize(id: Int, index: Int): String = AriaGraphicsImpl.pdfPageSize(id, index)
    fun ciRender(bitmapId: Int, recipe: String) = AriaGraphicsImpl.ciRender(bitmapId, recipe)
    fun ciCreate(recipe: String, x: Double, y: Double, width: Int, height: Int): Int =
        AriaGraphicsImpl.ciCreate(recipe, x, y, width, height)
}
