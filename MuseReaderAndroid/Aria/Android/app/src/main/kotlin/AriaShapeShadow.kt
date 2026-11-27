package aria.skip

import androidx.annotation.Keep
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/**
 * A drop shadow cast by a rounded-rectangle outline, drawn behind the view.
 *
 * SwiftUI's `.shadow` on Android (skip-ui `Shadowed`) composes the whole view a second
 * time, draws that copy into an offscreen layer and blurs it, again whenever anything in
 * the view changes. On the edit screen that meant about 130 GPU passes per frame. This
 * draws only the blurred shape, which Compose caches, so content changes cost nothing
 * extra. Instances are immutable and shared between views (see AndroidShapeShadow.swift).
 */
@Keep
class AriaShapeShadow(
    topLeading: Double,
    topTrailing: Double,
    bottomTrailing: Double,
    bottomLeading: Double,
    opacity: Double,
    radius: Double,
    x: Double,
    y: Double
) : skip.ui.ContentModifier {
    private val shape = RoundedCornerShape(
        topStart = topLeading.dp, topEnd = topTrailing.dp,
        bottomEnd = bottomTrailing.dp, bottomStart = bottomLeading.dp
    )
    private val shadow = Shadow(
        radius = radius.dp,
        color = Color.Black.copy(alpha = opacity.toFloat()),
        offset = DpOffset(x.dp, y.dp)
    )
    private val visible = opacity > 0.0

    override fun modify(view: skip.ui.View): skip.ui.View = view.composeModifier { modifier ->
        if (visible) modifier.dropShadow(shape, shadow) else modifier
    }
}
