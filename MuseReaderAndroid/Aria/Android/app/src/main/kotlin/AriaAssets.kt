package aria.skip

import android.content.Context
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import skip.foundation.ProcessInfo

/// The iOS app's bundled files, packaged as assets under ios/ (see build.gradle.kts).
/// The shared code asks for them through AppResources (AndroidResourceFiles.swift); each
/// is copied to app storage on first use because the engine and FileManager need file
/// paths. After an app update only the files whose contents changed are copied again
/// (ios-manifest.txt, written by the build, lists each file's size and SHA-256).
object AriaAssetsImpl {
    private const val ROOT = "ios"
    private const val MANIFEST = "ios-manifest.txt"
    private const val TAG = "AriaAssets"
    private val lock = Any()
    private var files: List<String>? = null
    private var refreshed = false
    // One lock per file, so copying the 215 MB sound bank doesn't hold up lookups of other files.
    private val fileLocks = ConcurrentHashMap<String, Any>()

    private val context: Context
        get() = ProcessInfo.processInfo.androidContext

    /// Copies the resource (a file, or a folder such as ScoreTemplates.bundle) out of the
    /// base APK or install-time soundbank pack and returns its path, or null when there is none. Finds it like Bundle.url:
    /// in `subdirectory`, else at the top, else anywhere (Xcode flattens folders).
    fun path(name: String, subdirectory: String?): String? {
        val assetPath: String
        val assetFiles: List<String>
        synchronized(lock) {
            assetPath = locate(name, subdirectory) ?: return null
            refreshIfUpdated()
            assetFiles = allFiles().filter { it == assetPath || it.startsWith("$assetPath/") }
        }
        for (file in assetFiles) {
            extract(file)
        }
        return File(storageRoot(), assetPath).path
    }

    private fun extract(file: String) {
        synchronized(fileLocks.getOrPut(file) { Any() }) {
            val destination = File(storageRoot(), file)
            if (destination.exists()) return
            val started = SystemClock.elapsedRealtime()
            destination.parentFile?.mkdirs()
            val partial = File(destination.path + ".partial")
            context.assets.open("$ROOT/$file").use { input ->
                partial.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
            }
            check(partial.renameTo(destination)) { "Could not finish extracting $file" }
            if (destination.length() >= (1L shl 20)) {
                Log.i(TAG, "extracted $file (${destination.length() shr 20} MB) in ${SystemClock.elapsedRealtime() - started} ms")
            }
        }
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

    /// Once per process, before the first copy: after an app update, delete the copies whose
    /// file changed in the update (or that can't be checked) and keep the rest.
    private fun refreshIfUpdated() {
        if (refreshed) return
        refreshed = true
        val root = storageRoot()
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        val marker = File(root, ".installed")
        if (marker.exists() && marker.readText() == installed) return

        val current = try {
            context.assets.open(MANIFEST).use(::readManifest)
        } catch (error: Exception) {
            null
        }
        val savedManifest = File(root, ".manifest")
        val previous = if (savedManifest.isFile) savedManifest.inputStream().use(::readManifest) else null
        var kept = 0
        if (current == null || previous == null) {
            root.deleteRecursively()
        } else {
            root.walkBottomUp().forEach { file ->
                val relative = file.relativeTo(root).invariantSeparatorsPath
                if (file == root || relative.startsWith(".")) return@forEach
                if (file.isDirectory) {
                    if (file.list().isNullOrEmpty()) file.delete()
                    return@forEach
                }
                val entry = current[relative]
                if (entry != null && previous[relative] == entry && file.length() == entry.size) {
                    kept++
                } else {
                    file.delete()
                }
            }
        }
        root.mkdirs()
        if (current != null) {
            context.assets.open(MANIFEST).use { input -> savedManifest.outputStream().use { input.copyTo(it) } }
        } else {
            savedManifest.delete()
        }
        marker.writeText(installed)
        Log.i(TAG, "app updated: kept $kept unchanged resource copies")
    }

    private data class Entry(val size: Long, val sha256: String)

    private fun readManifest(input: InputStream): Map<String, Entry> =
        input.bufferedReader().readLines().mapNotNull { line ->
            val parts = line.split('\t')
            val size = parts.getOrNull(1)?.toLongOrNull()
            if (parts.size == 3 && size != null) parts[0] to Entry(size, parts[2]) else null
        }.toMap()
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaAssets {
    fun path(name: String, subdirectory: String?): String? = AriaAssetsImpl.path(name, subdirectory)
}
