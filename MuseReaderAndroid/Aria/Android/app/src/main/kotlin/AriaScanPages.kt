package aria.skip

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import skip.foundation.ProcessInfo

/// The pages of a PDF or a picture for the score reader (ScoreScanService on Android): ScannerCore
/// reads binary PPM images there, since Android has no Core Graphics or ImageIO. Pages are drawn
/// one at a time, when the reader asks, so a long PDF never sits in memory whole.
///
/// PDF pages are drawn 2480 pixels wide on white, as ScannerCore's PDFScanner draws them on iOS.
/// Pictures keep their size and are turned upright by their EXIF orientation, as ImageIO does.
class AriaScanPages {
    /// Pages in the file: a PDF's page count, 1 for a picture Android can decode, 0 otherwise.
    fun pageCount(path: String): Int {
        val file = File(path)
        if (isPdf(file)) {
            return try {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { it.pageCount }
                }
            } catch (error: Exception) { 0 }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return 0
        // ScannerCore's limit: 80 megapixels.
        return if (bounds.outWidth.toLong() * bounds.outHeight <= 80_000_000L) 1 else 0
    }

    /// When this build of the app was installed, so models copied out of it are refreshed after an update.
    fun installStamp(): Long = try {
        val context = ProcessInfo.processInfo.androidContext
        context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    } catch (error: Exception) { 0L }

    /// ScannerCore's models unpacked from the app's assets (assets/ScannerModels) into a folder
    /// ONNX Runtime can open by path; again after each update of the app. The folder's path, or
    /// null when the models are missing.
    fun unpackModels(): String? = try {
        val context = ProcessInfo.processInfo.androidContext
        val target = File(context.filesDir, "ScannerModels")
        val marker = File(target, ".installed")
        val stamp = installStamp().toString()
        if (!(marker.isFile && marker.readText() == stamp)) {
            target.deleteRecursively()
            target.mkdirs()
            val names = context.assets.list("ScannerModels").orEmpty()
            if (names.isEmpty()) throw IllegalStateException("no models in the app")
            for (name in names) {
                context.assets.open("ScannerModels/$name").use { input ->
                    File(target, name).outputStream().use { input.copyTo(it) }
                }
            }
            marker.writeText(stamp)
        }
        target.absolutePath
    } catch (error: Exception) { null }

    /// The zero-based page as a binary PPM, or null when it can't be drawn.
    fun page(path: String, index: Int): ByteArray? {
        val file = File(path)
        val bitmap = (if (isPdf(file)) pdfPage(file, index) else picture(path)) ?: return null
        try {
            return ppm(bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    private fun isPdf(file: File): Boolean = try {
        file.inputStream().use { stream ->
            val head = ByteArray(4)
            stream.read(head) == 4 && String(head, Charsets.US_ASCII) == "%PDF"
        }
    } catch (error: Exception) { false }

    private fun pdfPage(file: File, index: Int): Bitmap? = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                if (index < 0 || index >= renderer.pageCount) return null
                renderer.openPage(index).use { page ->
                    val width = RENDER_WIDTH
                    val height = Math.round(width.toDouble() * page.height / page.width).toInt()
                    if (page.width <= 0 || height < 1 || height > 16000) return null
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.WHITE)
                    val scale = width.toFloat() / page.width
                    val matrix = Matrix().apply { setScale(scale, scale) }
                    page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    bitmap
                }
            }
        }
    } catch (error: Exception) { null }

    private fun picture(path: String): Bitmap? {
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val decoded = BitmapFactory.decodeFile(path, options) ?: return null
        val rotation = try {
            when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (error: Exception) { 0f }
        val upright = if (rotation != 0f) {
            val matrix = Matrix().apply { postRotate(rotation) }
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true).also {
                if (it !== decoded) decoded.recycle()
            }
        } else decoded
        if (!upright.hasAlpha()) return upright
        // Transparent pixels read as white paper, as ImageIO's drawing over white does on iOS.
        val flat = Bitmap.createBitmap(upright.width, upright.height, Bitmap.Config.ARGB_8888)
        flat.eraseColor(Color.WHITE)
        Canvas(flat).drawBitmap(upright, 0f, 0f, Paint())
        upright.recycle()
        return flat
    }

    /// The bitmap as a binary PPM (P6): RGB, 8 bits per sample. ScannerCore turns it grey.
    private fun ppm(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val header = "P6\n$width $height\n255\n".toByteArray(Charsets.US_ASCII)
        val output = ByteArray(header.size + width * height * 3)
        System.arraycopy(header, 0, output, 0, header.size)
        val row = IntArray(width)
        var offset = header.size
        for (y in 0 until height) {
            bitmap.getPixels(row, 0, width, 0, y, width, 1)
            for (pixel in row) {
                output[offset] = (pixel shr 16 and 0xFF).toByte()
                output[offset + 1] = (pixel shr 8 and 0xFF).toByte()
                output[offset + 2] = (pixel and 0xFF).toByte()
                offset += 3
            }
        }
        return output
    }

    companion object {
        /// ScannerCore's PDFScanner.renderWidth: about 300 dpi for A4 and letter.
        const val RENDER_WIDTH = 2480
    }
}
