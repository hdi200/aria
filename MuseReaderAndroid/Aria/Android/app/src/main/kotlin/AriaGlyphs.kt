package aria.skip

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.core.content.res.ResourcesCompat
import java.io.ByteArrayOutputStream
import skip.foundation.ProcessInfo

/// Notation-font glyphs drawn into square PNGs, centred, in black (used as templates):
/// iOS draws them with UIKit (ScoreReaderClefImage).
class AriaGlyphs {
    fun png(text: String, fontSize: Double, canvasSize: Int): ByteArray? {
        val context = ProcessInfo.processInfo.androidContext
        val typeface = ResourcesCompat.getFont(context, R.font.bravuratext) ?: return null
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            textSize = fontSize.toFloat()
            color = Color.BLACK
        }
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        val bitmap = Bitmap.createBitmap(canvasSize, canvasSize, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawText(
            text,
            (canvasSize - bounds.width()) / 2f - bounds.left,
            (canvasSize - bounds.height()) / 2f - bounds.top,
            paint
        )
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        bitmap.recycle()
        return output.toByteArray()
    }
}
