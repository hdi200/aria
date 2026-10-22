// ARIA PATCH: diagnostics only, compiled out unless explicitly requested by the build.
#if ARIA_PERF_DIAGNOSTICS
import Foundation

public enum AriaJNILifecycle {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: (Int, Int)] = [:]
    nonisolated(unsafe) private static var lastSample = 0.0

    public static func liveCount(_ kind: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let pair = counts[kind] ?? (0, 0)
        return pair.0 - pair.1
    }

    private static let androidDebug = try? JClass(name: "android/os/Debug", systemClass: true)
    private static let dumpMethod: JavaMethodID? = jniContext {
        let method = androidDebug?.getStaticMethodID(name: "dumpReferenceTables", sig: "()V")
        // Diagnostic hidden-API availability differs across ART versions. A denied
        // lookup must not leave an exception pending on an attached native thread.
        if JNI.jni.exceptionCheck() != 0 { JNI.jni.exceptionClear() }
        return method
    }

    /// ART's actual local table is thread-specific. Called on both the deliberately
    /// attached probe thread and the UI thread during the soak; no GC is requested.
    public static func dumpReferenceTables(_ label: String) {
        jniContext {
            print("ARIA_REFERENCE_TABLE_BEGIN \(label)")
            if let androidDebug, let dumpMethod {
                do { try androidDebug.callStatic(method: dumpMethod, options: [], args: []) as Void }
                catch { print("ARIA_REFERENCE_TABLE_FAILED \(label) \(error)") }
            } else {
                print("ARIA_REFERENCE_TABLE_UNAVAILABLE \(label)")
            }
            print("ARIA_REFERENCE_TABLE_END \(label)")
        }
    }

    public static func record(_ kind: String, created: Bool) {
        lock.lock()
        var pair = counts[kind] ?? (0, 0)
        if created { pair.0 += 1 } else { pair.1 += 1 }
        counts[kind] = pair
        let now = ProcessInfo.processInfo.systemUptime
        var sample: [String]?
        if now - lastSample >= 1 {
            lastSample = now
            sample = counts.keys.sorted().map { key in
                let value = counts[key]!
                return "\(key):init=\(value.0),deinit=\(value.1),live=\(value.0-value.1)"
            }
        }
        lock.unlock()
        if let sample {
            // Android log entries have a small payload limit. Keep all counters,
            // including globals at the end, when owner diagnostics add slot types.
            var parts: [String] = []
            var part = ""
            for entry in sample {
                if part.utf8.count + entry.utf8.count > 2500 {
                    parts.append(part)
                    part = ""
                }
                part += " " + entry
            }
            if !part.isEmpty { parts.append(part) }
            for (index, values) in parts.enumerated() {
                print("ARIA_JNI_LIFETIME uptime=\(now) part=\(index + 1)/\(parts.count)\(values)")
            }
        }
    }
}
#endif
