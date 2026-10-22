package aria.skip

import android.content.Context
import java.io.File
import skip.foundation.ProcessInfo

/// The iOS app's bundled files, packaged as assets under ios/ (see build.gradle.kts).
/// The shared code asks for them through AppResources (AndroidResourceFiles.swift); each
/// is copied to app storage on first use because the engine and FileManager need file
/// paths. Copies are refreshed when the app is updated.
object AriaAssetsImpl {
    private const val ROOT = "ios"
    private val lock = Any()
    private var files: List<String>? = null

    private val context: Context
        get() = ProcessInfo.processInfo.androidContext

    /// Copies the resource (a file, or a folder such as ScoreTemplates.bundle) out of the
    /// base APK or install-time soundbank pack and returns its path, or null when there is none. Finds it like Bundle.url:
    /// in `subdirectory`, else at the top, else anywhere (Xcode flattens folders).
    fun path(name: String, subdirectory: String?): String? = synchronized(lock) {
        val assetPath = locate(name, subdirectory) ?: return null
        refreshIfUpdated()
        val target = File(storageRoot(), assetPath)
        val assetFiles = allFiles().filter { it == assetPath || it.startsWith("$assetPath/") }
        for (file in assetFiles) {
            val destination = File(storageRoot(), file)
            if (destination.exists()) continue
            destination.parentFile?.mkdirs()
            val partial = File(destination.path + ".partial")
            context.assets.open("$ROOT/$file").use { input ->
                partial.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
            }
            check(partial.renameTo(destination)) { "Could not finish extracting $file" }
        }
        target.path
    }

    private fun locate(name: String, subdirectory: String?): String? {
        val all = allFiles()
        fun exists(path: String) = all.any { it == path || it.startsWith("$path/") }
        if (!subdirectory.isNullOrEmpty()) {
            val path = "${subdirectory.trimEnd('/')}/$name"
            return if (exists(path)) path else null
        }
        if (exists(name)) return name
        all.firstOrNull { it.endsWith("/$name") }?.let { return it }
        return all.firstOrNull { it.contains("/$name/") }?.let { it.substring(0, it.indexOf("/$name/") + name.length + 1) }
    }

    private fun allFiles(): List<String> {
        files?.let { return it }
        val result = mutableListOf<String>()
        fun walk(path: String) {
            val children = context.assets.list(if (path.isEmpty()) ROOT else "$ROOT/$path").orEmpty()
            if (children.isEmpty()) {
                if (path.isNotEmpty()) result.add(path)
                return
            }
            for (child in children) walk(if (path.isEmpty()) child else "$path/$child")
        }
        walk("")
        files = result
        return result
    }

    private fun storageRoot(): File = File(context.filesDir, "ios-resources")

    private fun refreshIfUpdated() {
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        val marker = File(storageRoot(), ".installed")
        if (marker.exists() && marker.readText() == installed) return
        storageRoot().deleteRecursively()
        storageRoot().mkdirs()
        marker.writeText(installed)
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaAssets {
    fun path(name: String, subdirectory: String?): String? = AriaAssetsImpl.path(name, subdirectory)
}
