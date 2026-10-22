package aria.skip

import android.content.pm.ActivityInfo
import android.view.HapticFeedbackConstants
import skip.foundation.ProcessInfo
import skip.ui.UIApplication

/// Device facts and haptics for the shared code's UIDevice, UIScreen and feedback
/// generators (Sources/AndroidShims/UIKit).
class AriaDevice {
    private val resources get() = ProcessInfo.processInfo.androidContext.resources

    fun isTablet(): Boolean = resources.configuration.smallestScreenWidthDp >= 600

    fun screenWidth(): Double = resources.configuration.screenWidthDp.toDouble()

    fun screenHeight(): Double = resources.configuration.screenHeightDp.toDouble()

    fun scale(): Double = resources.displayMetrics.density.toDouble()

    /// When the app was first installed on this device (ms since 1970).
    fun firstInstallTime(): Long {
        val context = ProcessInfo.processInfo.androidContext
        return context.packageManager.getPackageInfo(context.packageName, 0).firstInstallTime
    }

    /// 0: any orientation, 1: portrait, 2: landscape.
    fun setOrientation(kind: Int) {
        val activity = UIApplication.shared.androidActivity ?: return
        activity.requestedOrientation = when (kind) {
            1 -> ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT
            2 -> ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
            else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    /// 0: selection tick, 1: light impact, 2: strong impact.
    fun haptic(kind: Int) {
        val view = UIApplication.shared.androidActivity?.window?.decorView ?: return
        val constant = when (kind) {
            0 -> HapticFeedbackConstants.CLOCK_TICK
            1 -> HapticFeedbackConstants.KEYBOARD_TAP
            else -> HapticFeedbackConstants.CONFIRM
        }
        view.performHapticFeedback(constant)
    }
}
