package aria.skip

import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import androidx.annotation.Keep

@Keep
object AriaViewportFrameClock {
    private val main = Handler(Looper.getMainLooper())

    @JvmStatic
    fun post(callback: () -> Unit) {
        val schedule = {
            Choreographer.getInstance().postFrameCallback { frameNanos ->
                if (BuildConfig.ARIA_VIDEO_AUDIT) {
                    android.util.Log.i("Aria", "ARIA_VIEWPORT_FRAME nanos=$frameNanos")
                }
                callback()
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) schedule()
        else main.post { schedule() }
    }
}
