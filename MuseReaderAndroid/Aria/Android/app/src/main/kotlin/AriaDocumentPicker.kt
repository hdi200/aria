package aria.skip

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import skip.ui.UIApplication

/// Android's document picker, for the shared code's fileImporter (iOS: the Files picker).
/// Picked documents are copied into the app's cache, as iOS hands the app a file it may
/// read; the shared import code then moves them into the library.
object AriaDocumentPickerImpl {
    private const val REQUEST_CODE = 0xA1A
    private val lock = Any()
    private var result: String? = null

    fun pick(mimeTypes: String, multiple: Boolean): Boolean {
        val activity = UIApplication.shared.androidActivity ?: return false
        synchronized(lock) { result = null }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            val types = mimeTypes.split('\n').filter { it.isNotEmpty() }
            type = types.singleOrNull() ?: "*/*"
            if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
        }
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_CODE)
        return true
    }

    /// null while the picker is open; "" when cancelled; otherwise newline-separated paths.
    fun takeResult(): String? = synchronized(lock) {
        val value = result
        if (value != null) result = null
        value
    }

    fun handleResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            synchronized(lock) { result = "" }
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip -> for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        // Copy off the main thread; big scores take a moment.
        Thread {
            val folder = File(activity.cacheDir, "picked-${System.currentTimeMillis()}").apply { mkdirs() }
            val paths = uris.mapNotNull { uri -> copy(activity, uri, folder) }
            synchronized(lock) { result = paths.joinToString("\n") }
        }.start()
    }

    private fun copy(activity: Activity, uri: Uri, folder: File): String? = try {
        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "Score"
        val destination = File(folder, name.replace('/', '_'))
        activity.contentResolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        destination.path
    } catch (error: Exception) {
        android.util.Log.e("Aria", "Could not copy picked document", error)
        null
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaDocumentPicker {
    fun pick(mimeTypes: String, multiple: Boolean): Boolean = AriaDocumentPickerImpl.pick(mimeTypes, multiple)
    fun takeResult(): String? = AriaDocumentPickerImpl.takeResult()
}
