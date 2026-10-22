-keeppackagenames **
-keep class skip.** { *; }
-keep class tools.skip.** { *; }
-keep class kotlin.jvm.functions.** {*;}
-keep interface kotlinx.coroutines.Job { void cancel(java.util.concurrent.CancellationException); }
-keep class com.sun.jna.** { *; }
-dontwarn java.awt.**
-keep class * implements com.sun.jna.** { *; }
-keep class * implements skip.bridge.** { *; }
-keep class **._ModuleBundleAccessor_* { *; }
-keep class aria.skip.** { *; }

# Aria: Kotlin helpers Swift calls through reflection (AnyDynamicObject).
-keep class aria.skip.Aria** { *; }

# Qt Core JNI_OnLoad and native plugin calls resolve these names/members directly.
-keep class org.qtproject.qt.android.** { *; }
