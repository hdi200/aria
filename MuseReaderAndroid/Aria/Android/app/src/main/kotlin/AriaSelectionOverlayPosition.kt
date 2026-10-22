package aria.skip

import androidx.annotation.Keep
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import kotlin.math.roundToInt

/** One reader-owned position. No Swift callback, image or page peer is retained. */
@Keep
class AriaSelectionOverlayPosition : skip.ui.ContentModifier {
    private var point by mutableStateOf(Offset.Zero)

    fun update(x: Double, y: Double) {
        point = Offset(x.toFloat(), y.toFloat())
    }

    override fun modify(view: skip.ui.View): skip.ui.View = view.composeModifier { modifier ->
        modifier.composed {
            val density = LocalDensity.current.density
            Modifier.fillMaxSize().layout { measurable, constraints ->
                val child = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
                layout(constraints.maxWidth, constraints.maxHeight) {
                    // Read state only during placement: no Swift/Compose content rebuild.
                    val latest = point
                    child.placeRelative(
                        (latest.x * density).roundToInt() - child.width / 2,
                        (latest.y * density).roundToInt() - child.height / 2
                    )
                }
            }
        }
    }
}
