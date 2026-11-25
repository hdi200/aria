package aria.skip

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import java.io.File
import java.util.UUID
import org.json.JSONObject
import skip.ui.UIApplication

/** One camera session, polled by Swift. No camera permission is needed by Aria:
 * Play services owns capture and grants access only to the resulting document, and the
 * fallback hands capture to the device's camera app, which writes one photo for Aria. */
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
 * A cancelled/download-delayed request must not launch over a newer request.
 *
 * Play services' document scanner downloads its module on first use and needs a current
 * Play services. Where it fails or never answers (BUG-037: a Galaxy Tab S7's camera never
 * started; the request waited with no time limit), Aria opens the device's camera app
 * instead and scans the photo, like Choose Photo. */
internal object AriaDocumentCameraFlow {
    private const val SCANNER_TIMEOUT_MS = 15_000L
    private var active: AriaDocumentCamera? = null
    /** Which capture the active request handed off to: none yet, the scanner, or the camera app. */
    private var handoff: String? = null
    private var photo: File? = null

    @Synchronized private fun claim(camera: AriaDocumentCamera): Boolean {
        if (active != null) return false
        active = camera
        handoff = null
        photo = null
        return true
    }

    @Synchronized private fun isActive(camera: AriaDocumentCamera): Boolean = active === camera

    /** Claims the hand-off for `kind`; false when the request already went to the other one. */
    @Synchronized private fun handOff(camera: AriaDocumentCamera, kind: String): Boolean {
        if (active !== camera || handoff != null) return false
        handoff = kind
        return true
    }

    @Synchronized fun release(camera: AriaDocumentCamera) {
        if (active === camera) {
            active = null
            handoff = null
        }
    }

    fun start(camera: AriaDocumentCamera, activity: MainActivity): Boolean {
        if (!claim(camera)) return false
        activity.runOnUiThread {
            Handler(Looper.getMainLooper()).postDelayed({
                if (isActive(camera) && handoff == null) {
                    Log.w("Aria", "Document scanner didn’t answer in ${SCANNER_TIMEOUT_MS / 1000} s; using the camera app")
                    launchCameraApp(camera, activity)
                }
            }, SCANNER_TIMEOUT_MS)
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
                        if (activity.isFinishing || activity.isDestroyed) {
                            if (isActive(camera)) camera.complete("cancelled")
                            return@addOnSuccessListener
                        }
                        if (!handOff(camera, "scanner")) return@addOnSuccessListener
                        try {
                            activity.launchDocumentCamera(sender)
                        } catch (error: Exception) {
                            Log.w("Aria", "Document scanner couldn’t open", error)
                            synchronized(this) { handoff = null }
                            launchCameraApp(camera, activity)
                        }
                    }
                    .addOnFailureListener { error ->
                        Log.w("Aria", "Document scanner unavailable; using the camera app", error)
                        if (isActive(camera)) launchCameraApp(camera, activity)
                    }
            } catch (error: Exception) {
                Log.w("Aria", "Document scanner unavailable; using the camera app", error)
                launchCameraApp(camera, activity)
            }
        }
        return true
    }

    /** The device's camera app, through MediaStore.ACTION_IMAGE_CAPTURE: works with any
     * camera layout (rear, front only, external) and needs no camera permission. */
    private fun launchCameraApp(camera: AriaDocumentCamera, activity: MainActivity) {
        if (!handOff(camera, "camera app")) return
        if (activity.isFinishing || activity.isDestroyed) {
            camera.complete("cancelled")
            return
        }
        try {
            val folder = File(activity.cacheDir, "camera-${UUID.randomUUID()}")
            check(folder.mkdirs())
            val file = File(folder, "Camera Photo.jpg")
            val uri: Uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
            if (Intent(MediaStore.ACTION_IMAGE_CAPTURE).resolveActivity(activity.packageManager) == null) {
                folder.delete()
                camera.complete("error", message = "This device has no camera app Aria can use. Choose a photo or PDF instead.")
                return
            }
            synchronized(this) { photo = file }
            activity.launchCameraApp(uri)
        } catch (error: Exception) {
            fail(camera, error)
        }
    }

    fun handleCameraAppResult(saved: Boolean) {
        val (camera, file) = synchronized(this) { active to photo }
        if (camera == null) return
        if (file == null) return
        if (!saved || file.length() == 0L) {
            file.delete()
            file.parentFile?.delete()
            camera.complete("cancelled")
            return
        }
        Log.i("Aria", "Camera app photo ready: bytes=${file.length()}")
        camera.complete("completed", file = file, pages = 1)
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
