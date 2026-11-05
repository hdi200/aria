package aria.skip

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.IntentCompat
import java.io.File
import java.util.zip.ZipFile

/// "Open with" and "Share" from other apps (the intent filters in AndroidManifest.xml).
/// They hand Aria a content:// link, but the shared import code (ContentView's onOpenURL ->
/// MuseReaderAppModel.handleOpenURL, which Skip calls for ACTION_VIEW intents) reads files,
/// as on iOS. So copy the score into the cache, like the document picker, and pass Skip an
/// ACTION_VIEW intent for the copy.
object AriaOpenWith {
    fun prepare(activity: Activity, intent: Intent?): Intent? {
        if (intent == null) return null
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            else -> null
        } ?: return intent
        if (uri.scheme != "content") return intent
        val folder = File(activity.cacheDir, "opened-${System.currentTimeMillis()}").apply { mkdirs() }
        val path = AriaDocumentPickerImpl.copy(activity, uri, folder) ?: return null
        return Intent(Intent.ACTION_VIEW, Uri.fromFile(File(withScoreExtension(path, intent.type))))
    }

    /// Some apps name the file without its extension; the import code goes by the extension.
    private fun withScoreExtension(path: String, mimeType: String?): String {
        val known = listOf("mscz", "mscx", "mxl", "musicxml", "xml")
        if (path.substringAfterLast('.', "").lowercase() in known) return path
        val extension = when (mimeType) {
            "application/x-musescore" -> "mscz"
            "application/x-musescore+xml" -> "mscx"
            "application/vnd.recordare.musicxml" -> "mxl"
            "application/vnd.recordare.musicxml+xml" -> "musicxml"
            else -> zippedScoreExtension(path) ?: return path
        }
        val renamed = "$path.$extension"
        return if (File(path).renameTo(File(renamed))) renamed else path
    }

    /// Files labelled zip or octet-stream: .mscz holds a .mscx, .mxl holds META-INF/container.xml.
    private fun zippedScoreExtension(path: String): String? = try {
        ZipFile(path).use { zip ->
            val names = zip.entries().asSequence().map { it.name }.toList()
            when {
                names.any { it.endsWith(".mscx", ignoreCase = true) } -> "mscz"
                "META-INF/container.xml" in names -> "mxl"
                else -> null
            }
        }
    } catch (e: Exception) {
        null
    }
}
