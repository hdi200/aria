package aria.skip

import android.media.Image
import android.os.Looper
import android.os.Process
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/** Local release A/B evidence only; normal builds constant-fold every caller away. */
internal object AriaVideoAudit {
    private val threads = HashSet<String>()

    fun reset() {
        synchronized(threads) { threads.clear() }
    }

    fun thread(stage: String) {
        if (!BuildConfig.ARIA_VIDEO_AUDIT) return
        val tid = Process.myTid()
        if (synchronized(threads) { threads.add("$stage:$tid") }) {
            Log.i("AriaVideoAudit", "THREAD stage=$stage tid=$tid name=${Thread.currentThread().name} main=${Thread.currentThread() === Looper.getMainLooper().thread}")
        }
    }

    fun frame(index: Int, timeUs: Long, width: Int, height: Int, argb: IntArray, image: Image) {
        if (!BuildConfig.ARIA_VIDEO_AUDIT) return
        val started = android.os.SystemClock.elapsedRealtimeNanos()
        val pixels = ByteArray(argb.size * 4)
        ByteBuffer.wrap(pixels).order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().put(argb)
        val hashes = image.planes.mapIndexed { planeIndex, plane ->
            val w = if (planeIndex == 0) width else width / 2
            val h = if (planeIndex == 0) height else height / 2
            // Hash meaningful samples, excluding codec padding and buffer position.
            val samples = ByteArray(w * h)
            for (y in 0 until h) for (x in 0 until w) {
                samples[y * w + x] = plane.buffer.get(y * plane.rowStride + x * plane.pixelStride)
            }
            sha256(samples)
        }
        Log.i("AriaVideoAudit", "HASH frame=$index timeUs=$timeUs argb=${sha256(pixels)} y=${hashes[0]} u=${hashes[1]} v=${hashes[2]} hash_ms=${(android.os.SystemClock.elapsedRealtimeNanos() - started) / 1e6}")
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }
}
