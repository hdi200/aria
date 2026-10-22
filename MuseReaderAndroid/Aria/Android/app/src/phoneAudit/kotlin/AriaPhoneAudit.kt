package aria.skip

import android.content.ContentValues
import android.os.*
import android.provider.MediaStore
import android.view.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.draw.drawWithContent
import org.json.JSONArray
import org.json.JSONObject
import skip.foundation.ProcessInfo
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/** Local TEST APK only. No instrumentation permissions, network or other-app input.
 * Input is dispatched exclusively to the captured reader window in our own process.
 * Frame durations are Window FrameMetrics, not touch-to-photon measurements.
 */
internal object AriaPhoneAuditState {
    private val lock = Any()
    private var view = WeakReference<android.view.View>(null)
    private var window = WeakReference<Window>(null)
    private val handler = Handler(Looper.getMainLooper())
    private val metricsThread by lazy { HandlerThread("AriaTestFrames").apply { start() } }
    private val writer by lazy { Executors.newSingleThreadExecutor() }
    private data class Event(val name: String, val value: Int, val ns: Long,
        val cpuNs: Long, val tid: Int, val details: String? = null, val allocatedBytes: Long = -1) {
        fun json(): JSONObject = JSONObject().put("name", name).put("value", value)
            .put("ns", ns).put("cpuNs", cpuNs).put("tid", tid).also {
                if (details != null) it.put("details", JSONObject(details))
                if (allocatedBytes >= 0) it.put("allocatedBytes", allocatedBytes)
            }
    }
    private val events = ArrayList<Event>(65536)
    private var droppedEvents = 0
    private var nativeTimeline = "{}"
    private var markerWallNs = 0L
    private var markerCpuNs = 0L
    fun nativeTimeline(json: String) { synchronized(lock) { nativeTimeline = json } }
    private val frames = ArrayList<JSONObject>()
    private val phases = ArrayList<JSONObject>()
    private var visualSequence = 0
    private var visualKind = ""
    private var visualReady = false
    private var visualPending = false
    private var visualCompleted = 0
    fun armVisual(kind: String): Int = synchronized(lock) {
        check(kind == "note" || kind == "selection")
        visualSequence++; visualKind = kind; visualReady = false; visualPending = false
        visualSequence
    }
    fun visualToken(kind: String): Int = synchronized(lock) {
        if (visualKind == kind && visualReady && visualCompleted != visualSequence) visualSequence else 0
    }
    fun visualDone(token: Int): Boolean = synchronized(lock) { visualCompleted == token }
    fun visualDraw(kind: String, token: Int, surface: android.view.View) {
        if (token <= 0 || !surface.isHardwareAccelerated || !surface.viewTreeObserver.isAlive) return
        synchronized(lock) {
            if (kind != visualKind || token != visualSequence || !visualReady || visualPending || visualCompleted == token) return
            visualPending = true
            mark("visual_draw_" + kind, token)
        }
        // Registered from this bitmap's draw pass, not from its publication.
        // Submission is observable here; display scan-out is not.
        surface.viewTreeObserver.registerFrameCommitCallback {
            synchronized(lock) {
                if (token == visualSequence && kind == visualKind) {
                    mark("visual_commit_" + kind, token)
                    visualCompleted = token
                    AriaFocusedAudit.finished()
                }
            }
        }
    }
    private var phase: JSONObject? = null
    private var generation = 0
    private var inputSerial = 0
    private var downTime = 0L
    private var pointerCount = 0
    @Volatile var busy = false
    @Volatile var saveStatus = ""
    private var sessionName = ""
    private var droppedCallbacks = 0
    private var listening: Window? = null
    private val listener = Window.OnFrameMetricsAvailableListener { _, metrics, dropped ->
        synchronized(lock) {
            droppedCallbacks += dropped
            if (phase != null) frames.add(JSONObject()
                .put("vsyncNs", metrics.getMetric(FrameMetrics.INTENDED_VSYNC_TIMESTAMP))
                .put("totalNs", metrics.getMetric(FrameMetrics.TOTAL_DURATION))
                .put("firstDraw", metrics.getMetric(FrameMetrics.FIRST_DRAW_FRAME) == 1L)
                .put("layoutMeasureNs",metrics.getMetric(FrameMetrics.LAYOUT_MEASURE_DURATION))
                .put("drawNs",metrics.getMetric(FrameMetrics.DRAW_DURATION))
                .put("syncNs",metrics.getMetric(FrameMetrics.SYNC_DURATION))
                .put("commandNs",metrics.getMetric(FrameMetrics.COMMAND_ISSUE_DURATION))
                .put("swapNs",metrics.getMetric(FrameMetrics.SWAP_BUFFERS_DURATION))
                .put("inputNs",metrics.getMetric(FrameMetrics.INPUT_HANDLING_DURATION))
                .put("animationNs",metrics.getMetric(FrameMetrics.ANIMATION_DURATION))
                .put("unknownDelayNs",metrics.getMetric(FrameMetrics.UNKNOWN_DELAY_DURATION)))
        }
    }
    fun attach(v: android.view.View) {
        if (!BuildConfig.ARIA_PHONE_AUDIT) return
        // LocalView can be inside Skip's dialog; use its window, not the Activity's.
        var parent: android.view.ViewParent? = v.parent
        var w: Window? = (v as? androidx.compose.ui.window.DialogWindowProvider)?.window
        while (w == null && parent != null) {
            w = (parent as? androidx.compose.ui.window.DialogWindowProvider)?.window
            parent = parent.parent
        }
        w = w ?: skip.ui.UIApplication.shared.androidActivity?.window
        check(w != null) { "No reader window" }
        view = WeakReference(v); window = WeakReference(w)
        if (listening !== w) {
            listening?.removeOnFrameMetricsAvailableListener(listener)
            w.addOnFrameMetricsAvailableListener(listener, Handler(metricsThread.looper))
            listening = w
        }
        w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    fun detach() {
        cancel()
        listening?.removeOnFrameMetricsAvailableListener(listener)
        listening?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        listening = null; view.clear(); window.clear()
    }
    fun mark(name: String, value: Int) {
        if (!BuildConfig.ARIA_PHONE_AUDIT) return
        synchronized(lock) {
            val row = Event(name, value, System.nanoTime(), Debug.threadCpuTimeNanos(), android.os.Process.myTid())
            if ((name == "mutation_applied" && visualKind == "note") ||
                (name == "select_worker_end" && visualKind == "selection")) visualReady = true
            if (events.size < 65536) events.add(row) else droppedEvents++
        }
    }
    fun scopeMark(name: String, value: Int) {
        val allocated = Debug.getRuntimeStat("art.gc.bytes-allocated")?.toLongOrNull() ?: -1
        synchronized(lock) {
            val row=Event(name,value,System.nanoTime(),Debug.threadCpuTimeNanos(),android.os.Process.myTid(),allocatedBytes=allocated)
            if(events.size<65536) events.add(row) else droppedEvents++
        }
    }
    fun trace(name: String, details: String) {
        if (!BuildConfig.ARIA_PHONE_AUDIT) return
        synchronized(lock) {
            val row = Event(name, 0, System.nanoTime(), Debug.threadCpuTimeNanos(), android.os.Process.myTid(), details)
            if (events.size < 65536) events.add(row) else droppedEvents++
        }
    }
    fun memory(): JSONObject {
        val m = Debug.MemoryInfo(); Debug.getMemoryInfo(m)
        val r = Runtime.getRuntime()
        return JSONObject().put("pssKiB", m.totalPss)
            .put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize())
            .put("javaHeapBytes", r.totalMemory() - r.freeMemory())
            .put("runtimeStats", JSONObject(Debug.getRuntimeStats()))
    }
    fun reset() {
        check(BuildConfig.ARIA_PHONE_AUDIT)
        AriaRasterTiming.record = ::mark
        cancel()
        synchronized(lock) { visualSequence++; visualKind = ""; visualReady = false; visualPending = false; visualCompleted = 0 }
        synchronized(lock) { events.clear(); frames.clear(); phases.clear(); phase=null; droppedCallbacks=0; droppedEvents=0; nativeTimeline="{}" }
        val wallStart = System.nanoTime(); val cpuStart = Debug.threadCpuTimeNanos()
        repeat(1000) { mark("calibration", 0) }
        markerWallNs = (System.nanoTime() - wallStart) / 1000
        markerCpuNs = (Debug.threadCpuTimeNanos() - cpuStart) / 1000
        synchronized(lock) { events.clear() }
        AriaFocusedAudit.install()
        inputSerial = 0
        sessionName="Aria-Performance-TEST-${System.currentTimeMillis()}"
        saveStatus=""
    }
    fun begin(name: String) {
        check(BuildConfig.ARIA_PHONE_AUDIT)
        val mem = memory()
        synchronized(lock) {
            check(phase == null) { "Overlapping measurement phases" }
            phase=JSONObject().put("name",name).put("memoryBefore",mem)
                .put("startNs",System.nanoTime()).put("cpuStartNs",Debug.threadCpuTimeNanos())
                .put("startTid",android.os.Process.myTid())
        }
    }
    fun end(details: String) {
        val now=System.nanoTime(); val cpu=Debug.threadCpuTimeNanos()
        val row=synchronized(lock) {
            val p=phase ?: return
            p.put("endNs",now).put("mainCpuNs",cpu-p.getLong("cpuStartNs"))
                .put("endTid",android.os.Process.myTid()).put("details",JSONObject(details))
            phase=null; phases.add(p); p
        }
        row.put("memoryAfter",memory())
    }
    fun startInput(kind: String, x1: Double, y1: Double, x2: Double, y2: Double, duration: Int) {
        check(BuildConfig.ARIA_PHONE_AUDIT && !busy)
        val v=view.get() ?: error("Reader surface unavailable")
        val w=window.get() ?: error("Reader window unavailable")
        check(v.hasWindowFocus()) { "Benchmark paused: reader lost focus" }
        val density=v.resources.displayMetrics.density
        val location=IntArray(2); v.getLocationInWindow(location)
        // GeometryProxy .global is Compose root coordinates in dp.
        fun px(x: Double)=x.toFloat()*density+location[0]
        fun py(y: Double)=y.toFloat()*density+location[1]
        val ax=px(x1); val ay=py(y1); val bx=px(x2); val by=py(y2)
        val inputID=++inputSerial
        mark("input_begin_" + kind, inputID)
        val token=++generation; busy=true; downTime=SystemClock.uptimeMillis()
        val steps=if(kind=="tap") 1 else 24
        val length=if(kind=="tap") 30 else duration.coerceAtLeast(100)
        fun send(action: Int, fraction: Float, count: Int) {
            val props=Array(count) { i -> MotionEvent.PointerProperties().apply { id=i; toolType=MotionEvent.TOOL_TYPE_FINGER } }
            val coords=Array(count) { i -> MotionEvent.PointerCoords().apply {
                pressure=1f; size=1f
                if(kind=="pinch") {
                    val radius=(bx-ax)*(0.22f+fraction*0.28f)
                    x=(ax+bx)/2+if(i==0) -radius else radius; y=(ay+by)/2
                } else { x=ax+(bx-ax)*fraction; y=ay+(by-ay)*fraction }
            } }
            val e=MotionEvent.obtain(downTime,SystemClock.uptimeMillis(),action,count,props,coords,
                0,0,1f,1f,0,0,InputDevice.SOURCE_TOUCHSCREEN,0)
            try { w.decorView.dispatchTouchEvent(e) } finally { e.recycle() }
            pointerCount=if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL) 0 else count
        }
        if (kind == "tap") synchronized(lock) {
            if (visualKind.isNotEmpty() && visualCompleted != visualSequence) mark("visual_down_" + visualKind, visualSequence)
        }
        send(MotionEvent.ACTION_DOWN,0f,1)
        if(kind=="pinch") send(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),0f,2)
        for(i in 1..steps) handler.postAtTime({
            if(token!=generation) return@postAtTime
            if(!v.hasWindowFocus()) { mark("input_focus_lost",0); cancel(); return@postAtTime }
            val f=i.toFloat()/steps
            if(kind!="tap") { send(MotionEvent.ACTION_MOVE,f,if(kind=="pinch") 2 else 1); mark("injected_move",i) }
            if(i==steps) {
                if(kind=="pinch") send(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),f,2)
                send(MotionEvent.ACTION_UP,f,1); busy=false; mark("injected_up",length)
                mark("input_end_" + kind, inputID)
            }
        }, downTime+length*i/steps)
    }
    fun cancel() {
        generation++
        if(pointerCount>0) {
            val e=MotionEvent.obtain(downTime,SystemClock.uptimeMillis(),MotionEvent.ACTION_CANCEL,0f,0f,0)
            try { window.get()?.decorView?.dispatchTouchEvent(e) } finally { e.recycle() }
        }
        pointerCount=0; busy=false
    }
    fun save(extra: String) {
        check(BuildConfig.ARIA_PHONE_AUDIT)
        val context=ProcessInfo.processInfo.androidContext
        val root=synchronized(lock) {
            check(phase==null)
            JSONObject().put("schema",1).put("testOnly",true).put("renderer","current-full-page")
                .put("model",Build.MODEL).put("manufacturer",Build.MANUFACTURER)
                .put("sdk",Build.VERSION.SDK_INT).put("abi",Build.SUPPORTED_ABIS.firstOrNull())
                .put("package",context.packageName).put("version",BuildConfig.VERSION_NAME)
                .put("display",JSONObject().put("density",context.resources.displayMetrics.density)
                    .put("widthPx",context.resources.displayMetrics.widthPixels).put("heightPx",context.resources.displayMetrics.heightPixels))
                .put("extra",JSONObject(extra)).put("phases",JSONArray(phases))
                .put("events",JSONArray(events.map { it.json() }))
                .put("nativeTimeline",JSONObject(nativeTimeline)).put("droppedEvents",droppedEvents)
                .put("focusedAudit",AriaFocusedAudit.json())
                .put("kotlinMarkerCalibration", JSONObject().put("iterations",1000)
                    .put("meanWallNsPerMarker",markerWallNs).put("meanCpuNsPerMarker",markerCpuNs)).put("frames",JSONArray(frames)).put("droppedFrameCallbacks",droppedCallbacks)
                .put("limitations","Synthetic in-process touch; frame metrics are not touch-to-photon or acoustic latency. Short run is not a leak soak.")
        }
        val refresh=window.get()?.decorView?.display?.refreshRate ?: 60f
        root.put("refreshRateHz",refresh)
        val allFrames=root.getJSONArray("frames")
        for(i in phases.indices) {
            val p=root.getJSONArray("phases").getJSONObject(i)
            val durations=(0 until allFrames.length()).map { allFrames.getJSONObject(it) }
                .filter { it.getLong("vsyncNs") in p.getLong("startNs")..p.getLong("endNs") && !it.getBoolean("firstDraw") }
                .map { it.getLong("totalNs")/1e6 }.sorted()
            p.put("frameCount",durations.size)
            if(durations.isNotEmpty()) {
                p.put("frameP95Ms",durations[(kotlin.math.ceil(durations.size*.95).toInt()-1).coerceAtLeast(0)])
                p.put("framesOverRefreshBudget",durations.count { it>1000.0/refresh })
            }
        }
        saveStatus="Saving results…"
        writer.execute {
            try {
                val resolver=context.contentResolver
                val values=ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME,"$sessionName.json")
                    put(MediaStore.Downloads.MIME_TYPE,"application/json")
                    put(MediaStore.Downloads.RELATIVE_PATH,"Download/Aria Performance TEST")
                    put(MediaStore.Downloads.IS_PENDING,1)
                }
                val uri=checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values))
                try {
                    checkNotNull(resolver.openOutputStream(uri)).bufferedWriter().use { it.write(root.toString(2)) }
                    resolver.update(uri,ContentValues().apply { put(MediaStore.Downloads.IS_PENDING,0) },null,null)
                } catch(e: Exception) { resolver.delete(uri,null,null); throw e }
                saveStatus="Saved: Downloads/Aria Performance TEST/$sessionName.json"
                android.util.Log.i("AriaPhoneAudit",saveStatus)
            } catch(e: Exception) { saveStatus="Save failed: ${e.message}" }
        }
    }
}

/** Reflective Swift entry points, enabled only in the standalone audit APK. */
class AriaPhoneAudit {
    // Read once on the landing screen, outside all measurement windows.
    fun experiment(): String = skip.ui.UIApplication.shared.androidActivity?.intent
        ?.getStringExtra("ariaTestVariant") ?: "control"
    fun focusedMode(token: Int, enabled: Boolean)=AriaFocusedAudit.mode(token,enabled)
    fun armVisual(kind: String): Int=AriaPhoneAuditState.armVisual(kind)
    fun visualToken(kind: String): Int=AriaPhoneAuditState.visualToken(kind)
    fun visualDone(token: Int): Boolean=AriaPhoneAuditState.visualDone(token)
    fun nativeTimeline(json: String)=AriaPhoneAuditState.nativeTimeline(json)
    fun reset()=AriaPhoneAuditState.reset()
    fun mark(name: String,value: Int)=AriaPhoneAuditState.mark(name,value)
    fun trace(name: String,details: String)=AriaPhoneAuditState.trace(name,details)
    fun begin(name: String)=AriaPhoneAuditState.begin(name)
    fun end(details: String)=AriaPhoneAuditState.end(details)
    fun startInput(kind: String,x: Double,y: Double,tx: Double,ty: Double,duration: Int)=AriaPhoneAuditState.startInput(kind,x,y,tx,ty,duration)
    fun busy(): Boolean=AriaPhoneAuditState.busy
    fun cancel()=AriaPhoneAuditState.cancel()
    fun save(extra: String)=AriaPhoneAuditState.save(extra)
    fun saveStatus(): String=AriaPhoneAuditState.saveStatus
}

class AriaPhoneAuditCapture : skip.ui.ContentComposer {
    @Composable override fun Compose(context: skip.ui.ComposeContext) {
        val v=LocalView.current
        DisposableEffect(v) {
            AriaPhoneAuditState.attach(v)
            onDispose { AriaPhoneAuditState.detach() }
        }
    }
}

/** A transparent background drawn in the same pass as the tagged page/selection bitmap. */
class AriaPhoneAuditVisualProbe(private val kind: String, private val token: Int) : skip.ui.ContentComposer {
    @Composable override fun Compose(context: skip.ui.ComposeContext) {
        val surface = LocalView.current
        AriaPhoneAuditState.mark("probe_compose_" + kind, token)
        androidx.compose.runtime.SideEffect { AriaPhoneAuditState.mark("probe_side_effect_" + kind, token) }
        Box(modifier = context.modifier.fillMaxSize().drawWithContent {
            drawContent()
            AriaPhoneAuditState.visualDraw(kind, token, surface)
        })
    }
}
