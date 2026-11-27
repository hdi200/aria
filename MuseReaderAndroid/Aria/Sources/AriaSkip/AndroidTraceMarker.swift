#if os(Android)
import Android

/// Zero-length system-trace markers, for measuring touch-to-screen latency in Perfetto:
/// a page or selection image handed to the view is matched with the next frame and its
/// on-screen time (MainActivity.dispatchTouchEvent marks the finger-down). Calls the NDK's
/// ATrace directly; when no trace is recording it is one function call and nothing else.
enum AndroidTraceMarker {
    private typealias Section = @convention(c) (UnsafePointer<CChar>) -> Void
    private typealias Void0 = @convention(c) () -> Void
    private typealias Enabled = @convention(c) () -> Bool

    private struct Functions {
        let enabled: Enabled
        let begin: Section
        let end: Void0
    }

    nonisolated(unsafe) private static let functions: Functions? = {
        guard let library = dlopen("libandroid.so", RTLD_NOW),
              let enabled = dlsym(library, "ATrace_isEnabled"),
              let begin = dlsym(library, "ATrace_beginSection"),
              let end = dlsym(library, "ATrace_endSection") else { return nil }
        return Functions(enabled: unsafeBitCast(enabled, to: Enabled.self),
                         begin: unsafeBitCast(begin, to: Section.self),
                         end: unsafeBitCast(end, to: Void0.self))
    }()

    nonisolated static func mark(_ name: @autoclosure () -> String) {
        guard let functions, functions.enabled() else { return }
        name().withCString { functions.begin($0) }
        functions.end()
    }
}
#endif
