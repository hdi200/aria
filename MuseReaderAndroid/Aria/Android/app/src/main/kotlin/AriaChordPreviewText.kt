package aria.skip

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import skip.ui.ComposeContext
import skip.ui.ContentComposer

class AriaChordPreviewText(initialText: String, fontSize: Double) : ContentComposer {
    private var text by mutableStateOf(initialText)
    private val style = TextStyle(
        color = Color.Black.copy(alpha = 0.86f),
        fontSize = fontSize.sp,
        fontWeight = FontWeight.SemiBold,
    )

    fun updateText(text: String) {
        this.text = text
    }

    @Composable
    override fun Compose(context: ComposeContext) {
        BasicText(
            text = text,
            modifier = context.modifier,
            style = style,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
