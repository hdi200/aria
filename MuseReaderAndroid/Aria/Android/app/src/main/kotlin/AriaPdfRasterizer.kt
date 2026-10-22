package aria.skip

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.File
import skip.ui.UIImage

// No collector in a normal app. The standalone TEST source set installs this hook.
internal object AriaRasterTiming {
    @Volatile var record: ((String, Int) -> Unit)? = null
}

/// Draws the first page of a PDF into a bitmap: Android's counterpart to the CGPDFDocument
/// drawing in ScorePage.rasterizedImage(). Called from Swift (AndroidPDFPageRenderer), which
/// gets the bitmap back as a UIImage through UIImageBitmapHandoff: no PNG encode and decode.
object AriaPdfRasterizerImpl {
    /// The crop (normalized page coordinates) is the part of the page drawn into the
    /// bitmap; 0, 0, 1, 1 is the whole page. Returns the handoff key for
    /// UIImage(contentsOfFile:).
    fun bitmapKey(pdf: ByteArray, width: Int, height: Int, opaque: Boolean,
                  cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double): String? {
        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke(if (opaque) "page_raster_start" else "overlay_raster_start", width * height)
        // PdfRenderer needs a seekable file descriptor.
        val file = File.createTempFile("aria-page", ".pdf")
        try {
            if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_temp_write_begin", 0)
            file.writeBytes(pdf)
            if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_temp_write_end", 0)
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_document_opened", 0)
                    if (renderer.pageCount < 1) return null
                    renderer.openPage(0).use { page ->
                        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_page_opened", 0)
                        val targetWidth = if (width > 0) width else page.width
                        val targetHeight = if (height > 0) height else page.height
                        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("bitmap_allocate_begin", 0)
                        val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("bitmap_allocate_end", 0)
                        // Pages sit on white; overlays (selections, previews) stay transparent.
                        bitmap.eraseColor(if (opaque) Color.WHITE else Color.TRANSPARENT)
                        // Fit the cropped part of the page, centered, like the iOS drawing.
                        val cropW = (page.width * cropWidth).toFloat()
                        val cropH = (page.height * cropHeight).toFloat()
                        val scale = minOf(targetWidth / cropW, targetHeight / cropH)
                        val matrix = android.graphics.Matrix()
                        matrix.setScale(scale, scale)
                        matrix.postTranslate(
                            (targetWidth - cropW * scale) / 2f - (page.width * cropX).toFloat() * scale,
                            (targetHeight - cropH * scale) / 2f - (page.height * cropY).toFloat() * scale
                        )
                        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_paint_begin", 0)
                        page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke("pdf_paint_end", 0)
                        return UIImage.UIImageBitmapHandoff.put(bitmap)
                    }
                }
            }
        } catch (error: Exception) {
            android.util.Log.e("Aria", "PDF page rasterizing failed", error)
            return null
        } finally {
            file.delete()
            if (BuildConfig.ARIA_PHONE_AUDIT) AriaRasterTiming.record?.invoke(if (opaque) "page_raster_end" else "overlay_raster_end", width * height)
        }
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaPdfRasterizer {
    fun bitmapKey(pdf: ByteArray, width: Int, height: Int, opaque: Boolean,
                  cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double): String? =
        AriaPdfRasterizerImpl.bitmapKey(pdf, width, height, opaque, cropX, cropY, cropWidth, cropHeight)
}
