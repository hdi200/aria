// Share the Android plugin classpath with the app and install-time asset pack.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
}
