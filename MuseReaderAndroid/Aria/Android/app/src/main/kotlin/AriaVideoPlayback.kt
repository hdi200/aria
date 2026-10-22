package aria.skip

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import skip.ui.UIApplication

/// The finished videos in the export sheet: their first frame, their length, and opening
/// one in a video app (AVPlayer and AVURLAsset in the AVFoundation shim).
class AriaVideoPlayback {
    /// Seconds; 0 when the file can't be read.
    fun duration(path: String): Double = retrieve(path) { retriever ->
        (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull() ?: 0.0) / 1000.0
    } ?: 0.0

    /// The first frame as PNG, at most `maximumSize` pixels on its long side.
    fun frame(path: String, maximumSize: Int): ByteArray? = retrieve(path) { retriever ->
        val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return@retrieve null
        val scale = minOf(1.0, maximumSize.toDouble() / maxOf(frame.width, frame.height))
        val scaled = if (scale < 1.0) {
            Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt(), (frame.height * scale).toInt(), true)
        } else frame
        val output = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.PNG, 100, output)
        output.toByteArray()
    }

    /// Opens the video in the chosen video app.
    fun open(path: String): Boolean {
        val activity = UIApplication.shared.androidActivity ?: return false
        return try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", File(path))
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/mp4")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(intent, null))
            true
        } catch (error: Exception) {
            android.util.Log.e("Aria", "Opening the video failed", error)
            false
        }
    }

    private fun <T> retrieve(path: String, body: (MediaMetadataRetriever) -> T?): T? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            body(retriever)
        } catch (error: Exception) {
            null
        } finally {
            retriever.release()
        }
    }
}
