package aria.skip

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable

/// The system Back gesture for panels that aren't presentations (the tablet mixer, an
/// overlay): while AriaBackCapture is composed it takes Back, and the presses are read by
/// Swift (androidBackAction in AndroidSwiftUIShims.swift).
object AriaBackImpl {
    @Volatile var presses = 0
}

class AriaBack {
    fun takePresses(): Int {
        val count = AriaBackImpl.presses
        AriaBackImpl.presses = 0
        return count
    }
}

class AriaBackCapture : skip.ui.ContentComposer {
    @Composable
    override fun Compose(context: skip.ui.ComposeContext) {
        BackHandler(enabled = true) { AriaBackImpl.presses += 1 }
    }
}
