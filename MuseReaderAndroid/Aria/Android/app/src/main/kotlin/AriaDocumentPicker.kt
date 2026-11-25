package aria.skip

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.zip.ZipFile
import skip.ui.UIApplication

/// Android's document picker, for the shared code's fileImporter (iOS: the Files picker).
/// Picked documents are copied into the app's cache, as iOS hands the app a file it may
/// read; the shared import code then moves them into the library.
object AriaDocumentPickerImpl {
    private const val REQUEST_CODE = 0xA1A
    private val lock = Any()
    private var result: String? = null
    private var failure: String? = null

    /// Android's own picker (DocumentsUI; Google's build on Play devices, AOSP's elsewhere).
    /// Some phone makers make their own file manager the default for ACTION_OPEN_DOCUMENT
    /// (Samsung My Files on Galaxy tablets). Those may hand back links Aria isn't allowed to
    /// read, so Aria asks for Android's picker by name when it is installed (BUG-035).
    private val systemPickerPackages = listOf("com.google.android.documentsui", "com.android.documentsui")

    fun pick(mimeTypes: String, multiple: Boolean): Boolean {
        val activity = UIApplication.shared.androidActivity ?: return false
        synchronized(lock) { result = null; failure = null }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            val types = mimeTypes.split('\n').filter { it.isNotEmpty() }
            type = types.singleOrNull() ?: "*/*"
            if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
        }
        systemPicker(activity, intent)?.let { intent.setPackage(it) }
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            if (intent.`package` == null) {
                android.util.Log.e("Aria", "No document picker", error)
                synchronized(lock) {
                    failure = "No app on this device can pick files. Install or turn on the Files app, then try again."
                    result = ""
                }
                return true
            }
            intent.setPackage(null)
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_CODE)
        }
        return true
    }

    /// The system picker's package, when the device's default handler is another app.
    private fun systemPicker(context: Context, intent: Intent): String? = try {
        val packages = context.packageManager
        val default = packages.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        if (default in systemPickerPackages) {
            null
        } else {
            val handlers = packages.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }
            android.util.Log.i("Aria", "Document picker default=$default handlers=$handlers")
            systemPickerPackages.firstOrNull { it in handlers }
        }
    } catch (error: Exception) {
        null
    }

    /// null while the picker is open; "" when cancelled or nothing could be read;
    /// otherwise newline-separated paths.
    fun takeResult(): String? = synchronized(lock) {
        val value = result
        if (value != null) result = null
        value
    }

    /// Why picked documents couldn't be read, one line per document; read after takeResult.
    fun takeFailure(): String? = synchronized(lock) {
        failure.also { failure = null }
    }

    fun handleResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE) return
        if (resultCode != Activity.RESULT_OK) {
            synchronized(lock) { result = "" }
            return
        }
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { uris.add(it) } }
        data?.data?.let { if (it !in uris) uris.add(it) }
        android.util.Log.i("Aria", "Document picker returned ${uris.size} document(s): ${uris.map { it.scheme + "://" + it.authority }}")
        if (uris.isEmpty()) {
            synchronized(lock) {
                failure = "The file picker didn’t return a file. Try again, or open the score from your file manager with Share › Aria."
                result = ""
            }
            return
        }
        // Copy off the main thread; big scores take a moment.
        Thread {
            val folder = File(activity.cacheDir, "picked-${System.currentTimeMillis()}").apply { mkdirs() }
            val copies = uris.map { uri -> copyDocument(activity, uri, folder) }
            synchronized(lock) {
                failure = copies.mapNotNull { it.error }.joinToString("\n").ifEmpty { null }
                result = copies.mapNotNull { it.path }.joinToString("\n")
            }
        }.start()
    }

    class Copy(val path: String?, val error: String?)

    /// Copies a picked or shared document into `folder`. Scores labelled octet-stream or zip,
    /// or named without an extension, get the extension the import code goes by.
    fun copyDocument(context: Context, uri: Uri, folder: File, mimeType: String? = null): Copy {
        val name = displayName(context, uri)
        val destination = File(folder, name)
        try {
            openInput(context, uri).use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (error: SecurityException) {
            android.util.Log.e("Aria", "No permission to read picked document $uri", error)
            destination.delete()
            return Copy(null, "The app that picked “$name” didn’t give Aria permission to read it. Pick it from Android’s Files picker instead, or open it in your file manager and use Share › Aria.")
        } catch (error: Exception) {
            android.util.Log.e("Aria", "Could not copy picked document $uri", error)
            destination.delete()
            return Copy(null, "Aria couldn’t read “$name”. Try picking it again, or open it in your file manager and use Share › Aria.")
        }
        if (destination.length() == 0L) {
            destination.delete()
            return Copy(null, "“$name” is empty.")
        }
        val type = mimeType ?: try { context.contentResolver.getType(uri) } catch (error: Exception) { null }
        return Copy(withScoreExtension(destination.path, type), null)
    }

    /// The old form, for callers that only need the path.
    fun copy(activity: Activity, uri: Uri, folder: File): String? = copyDocument(activity, uri, folder).path

    private fun openInput(context: Context, uri: Uri): InputStream =
        if (uri.scheme == "file") {
            // Some file managers still return file:// paths. Android lets Aria read one
            // only where it may read the folder; otherwise this throws, and we report it.
            FileInputStream(uri.path ?: throw IllegalArgumentException("Empty file path"))
        } else {
            context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("No input stream for $uri")
        }

    private fun displayName(context: Context, uri: Uri): String {
        val queried = if (uri.scheme == "content") try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
        } catch (error: Exception) {
            // Some providers refuse the query but still open the file.
            android.util.Log.w("Aria", "Document name query failed for $uri", error)
            null
        } else null
        val name = queried?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "Score"
        return name.replace('/', '_').replace('\u0000', '_')
    }

    /// Some apps name the file without its extension; the import code goes by the extension.
    fun withScoreExtension(path: String, mimeType: String?): String {
        val known = listOf("mscz", "mscx", "mxl", "musicxml", "xml")
        if (path.substringAfterLast('/').substringAfterLast('.', "").lowercase() in known) return path
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

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaDocumentPicker {
    fun pick(mimeTypes: String, multiple: Boolean): Boolean = AriaDocumentPickerImpl.pick(mimeTypes, multiple)
    fun takeResult(): String? = AriaDocumentPickerImpl.takeResult()
    fun takeFailure(): String? = AriaDocumentPickerImpl.takeFailure()
}
