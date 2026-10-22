package aria.skip

import android.util.Log
import androidx.annotation.Keep
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import kotlin.math.abs

/** One page-local recognizer owns the complete pointer lifecycle. No polling or global owner.
 * Swift owns score semantics; this class only arbitrates taps, held drags, pans and pinch.
 * Event coordinates are viewport-local dp, matching SwiftUI's page geometry.
 */
@Keep
class AriaPageGestures(
    private val editing: Boolean,
    private val readingHold: Boolean,
    private val annotating: Boolean,
    private val canPan: Boolean,
    private val event: (Int, Double, Double, Double, Double) -> Int
) : skip.ui.ContentModifier {
    override fun modify(view: skip.ui.View): skip.ui.View = view.composeModifier { modifier ->
        modifier.composed {
            // Recomposition updates closures without cancelling a gesture or keeping old page values.
            val latest = rememberUpdatedState(this@AriaPageGestures)
            val density = LocalDensity.current.density
            Modifier.pointerInput(editing, annotating) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    val start = down.position
                    var last = start
                    var owned = false
                    var held = false
                    var delegated = false
                    var finished = false
                    var pinching = false
                    var pinchStart = Offset.Zero
                    var pinchSpan = 1f
                    fun emit(code: Int, point: Offset, a: Double = start.x.toDouble() / density,
                             b: Double = start.y.toDouble() / density): Int {
                        val result = latest.value.event(code, point.x.toDouble() / density,
                            point.y.toDouble() / density, a, b)
                        if (Log.isLoggable("AriaGesture", Log.DEBUG) && code != 2 && code != 6 && code != 9 && code != 12) {
                            Log.d("AriaGesture", "event=$code x=${point.x / density} y=${point.y / density} result=$result")
                        }
                        return result
                    }
                    val immediate = latest.value.annotating || emit(12, start) != 0
                    val holdMs = when {
                        latest.value.annotating -> 0L
                        latest.value.editing -> 120L
                        latest.value.readingHold -> 450L
                        else -> Long.MAX_VALUE
                    }
                    if (immediate) down.consume()
                    if (latest.value.annotating) {
                        owned = true
                        emit(1, start, 0.0, 0.0)
                    }
                    try {
                        while (true) {
                            val remaining = holdMs - (currentEvent.changes.first().uptimeMillis - down.uptimeMillis)
                            val next = if (!owned && !delegated && !pinching && holdMs != Long.MAX_VALUE) {
                                withTimeoutOrNull(maxOf(remaining, 1L)) {
                                    awaitPointerEvent(PointerEventPass.Initial)
                                }
                            } else awaitPointerEvent(PointerEventPass.Initial)
                            if (next == null) {
                                held = true
                                owned = true
                                emit(if (latest.value.editing) 1 else 5, start, 1.0, 0.0)
                                continue
                            }
                            val pressed = next.changes.filter { it.pressed }
                            if (pressed.size >= 2) {
                                val center = (pressed[0].position + pressed[1].position) / 2f
                                val span = (pressed[0].position - pressed[1].position).getDistance().coerceAtLeast(1f)
                                if (!pinching) {
                                    if (owned) emit(4, last)
                                    pinching = true
                                    pinchStart = center
                                    pinchSpan = span
                                    emit(8, center)
                                }
                                emit(9, pinchStart, (span / pinchSpan).toDouble(), 0.0)
                                next.changes.forEach { it.consume() }
                                continue
                            }
                            if (pinching) {
                                // After one finger lifts, consume the rest without turning it into a tap/drag.
                                next.changes.forEach { it.consume() }
                                if (pressed.isEmpty()) {
                                    emit(10, pinchStart)
                                    finished = true
                                    break
                                }
                                continue
                            }
                            val change = next.changes.firstOrNull { it.id == down.id }
                            // Compose synthesizes a consumed release for ACTION_CANCEL.
                            // Check consumption even after claiming the stream: treating that
                            // release as a normal up would commit an interrupted score drop.
                            if (change == null || change.isConsumed) break
                            last = change.position
                            if (change.changedToUpIgnoreConsumed()) {
                                if (owned) {
                                    emit(if (held && !latest.value.editing) 7 else 3, last)
                                    change.consume()
                                } else if (!delegated) {
                                    emit(0, last)
                                    change.consume()
                                }
                                finished = true
                                break
                            }
                            val delta = last - start
                            if (!owned && !delegated && delta.getDistance() >= viewConfiguration.touchSlop) {
                                // Leave ordinary vertical page scrolling to the enclosing ScrollView.
                                if (!immediate && !latest.value.canPan && abs(delta.y) > abs(delta.x)) {
                                    delegated = true
                                } else {
                                    owned = true
                                    emit(1, start, 0.0, 0.0)
                                }
                            }
                            if (owned) {
                                emit(if (held && !latest.value.editing) 6 else 2, last)
                                change.consume()
                            }
                        }
                    } finally {
                        if (!finished) {
                            // Pointer cancellation/disposal never becomes a successful score drop.
                            if (pinching) emit(10, pinchStart)
                            emit(4, last)
                        }
                    }
                }
            }
        }
    }
}

@Keep
object AriaGestureDiagnostics {
    @JvmStatic fun enabled(): Boolean = Log.isLoggable("AriaGesture", Log.DEBUG)
    @JvmStatic fun record(message: String) {
        if (enabled()) Log.d("AriaGesture", message)
    }
}
