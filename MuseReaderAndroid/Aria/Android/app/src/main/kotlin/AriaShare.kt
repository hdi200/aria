package aria.skip

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import skip.ui.UIApplication

/// Android's share chooser, for the shared code's share sheets (iOS: UIActivityViewController).
/// Files are offered through the app's FileProvider (res/xml/aria_file_paths.xml).
class AriaShare {
    /// `paths` and `texts` are newline separated.
    fun share(paths: String, texts: String) {
        val activity = UIApplication.shared.androidActivity ?: return
        val uris = paths.split('\n').filter { it.isNotEmpty() }.map { path ->
            FileProvider.getUriForFile(activity, "${activity.packageName}.files", File(path))
        }
        val text = texts.ifEmpty { null }
        val intent = when {
            uris.size > 1 -> Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
                type = mimeType(paths.split('\n'))
            }
            uris.size == 1 -> Intent(Intent.ACTION_SEND).apply {
                putExtra(Intent.EXTRA_STREAM, uris[0])
                type = mimeType(listOf(paths))
                clipData = ClipData.newRawUri(null, uris[0])
            }
            else -> Intent(Intent.ACTION_SEND).apply { type = "text/plain" }
        }
        text?.let { intent.putExtra(Intent.EXTRA_TEXT, it) }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(intent, null))
    }

    private fun mimeType(paths: List<String>): String {
        val types = paths.filter { it.isNotEmpty() }.map { path ->
            when (path.substringAfterLast('.', "").lowercase()) {
                "pdf" -> "application/pdf"
                "png" -> "image/png"
                "jpg", "jpeg" -> "image/jpeg"
                "mp4" -> "video/mp4"
                "wav" -> "audio/wav"
                "mid", "midi" -> "audio/midi"
                "musicxml", "xml" -> "application/vnd.recordare.musicxml+xml"
                "mxl" -> "application/vnd.recordare.musicxml"
                else -> "application/octet-stream"
            }
        }.distinct()
        return types.singleOrNull() ?: "*/*"
    }
}
