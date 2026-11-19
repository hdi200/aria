package aria.skip

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import java.io.File
import java.util.UUID
import org.json.JSONObject
import skip.ui.UIApplication

/** One camera session, polled by Swift. No camera permission is needed by Aria:
 * Play services owns capture and grants access only to the resulting document. */
class AriaDocumentCamera {
    private val lock = Any()
    private var result: String? = null
    private var cancelled = false

    fun start(): Boolean {
        val activity = UIApplication.shared.androidActivity as? MainActivity
        if (activity == null) {
            complete("error", message = "Camera scanning couldn’t start. Please try again, or choose a photo or PDF.")
            return true
        }
        return AriaDocumentCameraFlow.start(this, activity)
    }

    fun takeResult(): String? = synchronized(lock) {
        result.also { result = null }
    }

    fun cancel(): Boolean {
        synchronized(lock) { cancelled = true; result = null }
        AriaDocumentCameraFlow.release(this)
        return true
    }

    internal fun complete(status: String, file: File? = null, pages: Int = 0, message: String? = null) {
        synchronized(lock) {
            if (cancelled) {
                file?.delete()
            } else {
                result = JSONObject().put("status", status).apply {
                    if (file != null) put("path", file.absolutePath)
                    if (pages > 0) put("pages", pages)
                    if (message != null) put("message", message)
                }.toString()
            }
        }
        AriaDocumentCameraFlow.release(this)
    }
}

/** Keeps the activity-result callback associated with its original Swift request.
 * A cancelled/download-delayed request must not launch over a newer request. */
internal object AriaDocumentCameraFlow {
    private var active: AriaDocumentCamera? = null

    @Synchronized private fun claim(camera: AriaDocumentCamera): Boolean {
        if (active != null) return false
        active = camera
        return true
    }

    @Synchronized private fun isActive(camera: AriaDocumentCamera): Boolean = active === camera

    @Synchronized fun release(camera: AriaDocumentCamera) {
        if (active === camera) active = null
    }

    fun start(camera: AriaDocumentCamera, activity: MainActivity): Boolean {
        if (!claim(camera)) return false
        activity.runOnUiThread {
            try {
                // Crop/rotate/reorder without ML stain removal, which could erase musical marks.
                val options = GmsDocumentScannerOptions.Builder()
                    .setGalleryImportAllowed(true)
                    .setPageLimit(100)
                    .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
                    .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)
                    .build()
                GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                    .addOnSuccessListener { sender ->
                        if (!isActive(camera)) return@addOnSuccessListener
                        try {
                            if (activity.isFinishing || activity.isDestroyed) {
                                camera.complete("cancelled")
                            } else {
                                activity.launchDocumentCamera(sender)
                            }
                        } catch (error: Exception) {
                            fail(camera, error)
                        }
                    }
                    .addOnFailureListener { error -> if (isActive(camera)) fail(camera, error) }
            } catch (error: Exception) {
                fail(camera, error)
            }
        }
        return true
    }

    fun handleResult(activity: Activity, resultCode: Int, data: Intent?) {
        val camera = synchronized(this) { active } ?: return
        if (resultCode != Activity.RESULT_OK) {
            camera.complete("cancelled")
            return
        }
        val pdf = try {
            GmsDocumentScanningResult.fromActivityResultIntent(data)?.pdf
        } catch (error: Exception) {
            fail(camera, error)
            return
        }
        if (pdf == null || pdf.pageCount < 1) {
            camera.complete("error", message = "The camera didn’t return a document. Please try again, or choose a photo or PDF.")
            return
        }
        // Copy the complete PDF off the UI thread; the reader then draws one page at a time.
        Thread {
            val folder = File(activity.cacheDir, "camera-${UUID.randomUUID()}")
            val file = File(folder, "Camera Scan.pdf")
            try {
                check(folder.mkdirs())
                val input = activity.contentResolver.openInputStream(pdf.uri)
                    ?: throw IllegalStateException("Camera PDF could not be opened")
                input.use { source -> file.outputStream().use { source.copyTo(it) } }
                check(file.length() > 0)
                Log.i("Aria", "Document camera PDF ready: pages=${pdf.pageCount} bytes=${file.length()}")
                camera.complete("completed", file = file, pages = pdf.pageCount)
            } catch (error: Exception) {
                file.delete()
                folder.delete()
                fail(camera, error)
            }
        }.start()
    }

    private fun fail(camera: AriaDocumentCamera, error: Exception) {
        Log.w("Aria", "Document camera unavailable", error)
        camera.complete("error", message = "Camera scanning couldn’t start. Check Google Play services and try again, or choose a photo or PDF.")
    }
}
