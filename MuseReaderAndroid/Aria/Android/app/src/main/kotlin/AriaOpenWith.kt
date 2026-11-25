package aria.skip

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.core.content.IntentCompat
import java.io.File

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
        val copy = AriaDocumentPickerImpl.copyDocument(activity, uri, folder, intent.type)
        val path = copy.path
        if (path == null) {
            // Say why, rather than handing Skip a link the import code can't read (BUG-035).
            Toast.makeText(activity, copy.error ?: "Aria couldn’t read that file.", Toast.LENGTH_LONG).show()
            return Intent(Intent.ACTION_MAIN)
        }
        return Intent(Intent.ACTION_VIEW, Uri.fromFile(File(path)))
    }
}
