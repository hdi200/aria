package aria.skip

import android.os.Debug
import org.json.JSONObject

/** TEST-only. Coarse Skip callbacks only; global Compose tracing was too intrusive on Moto.
 * Allocation snapshots are process-wide approximate counters at coarse loop boundaries.
 * Balanced on/off actions within the same APK expose gross instrumentation distortion.
 */
internal object AriaFocusedAudit {
    private var unbalanced = 0
    private var active = false
    private var bodyDepth = 0
    private val modes = linkedMapOf<Int, Boolean>()
    private var allocationReadWallNs = 0L
    private var allocationReadCpuNs = 0L
    fun install() {
        active=false; bodyDepth=0; unbalanced=0; modes.clear()
        val w=System.nanoTime(); val c=Debug.threadCpuTimeNanos()
        repeat(1000) { Debug.getRuntimeStat("art.gc.bytes-allocated")?.toLongOrNull() }
        allocationReadWallNs=(System.nanoTime()-w)/1000
        allocationReadCpuNs=(Debug.threadCpuTimeNanos()-c)/1000
        skip.ui.AriaComposeAudit.record = { name, value ->
            if (active) {
                var collect=true
                if(name=="compose_body_begin") { bodyDepth++; collect=bodyDepth==1 }
                if(name=="compose_body_end") { collect=bodyDepth==1; bodyDepth--; if(bodyDepth<0){unbalanced++;bodyDepth=0} }
                if(collect) AriaPhoneAuditState.scopeMark(name, value)
            }
        }
    }
    fun mode(token: Int, enabled: Boolean) {
        modes[token]=enabled; active=enabled
        AriaPhoneAuditState.mark("focused_mode", if(enabled) token else -token)
    }
    fun finished() { active=false }
    fun json(): JSONObject = JSONObject().put("tokenModes",JSONObject(modes.mapKeys { it.key.toString() }))
        .put("tracerEnabled",false).put("tracerDisabledReason","TEST 06 gross observer penalty; coarse scopes retained")
        .put("compositionCallbacks",0).put("recordedDepth",0)
        .put("unbalanced",unbalanced).put("remainingBodyDepth",bodyDepth).put("remainingDepth",0)
        .put("allocationReadMeanWallNs",allocationReadWallNs).put("allocationReadMeanCpuNs",allocationReadCpuNs)
        .put("allocationScope","approximate process-wide ART bytes; includes concurrent work and counter overhead")
}
