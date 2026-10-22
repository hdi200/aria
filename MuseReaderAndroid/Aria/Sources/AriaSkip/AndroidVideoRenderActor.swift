// Canvas, Core Image stand-ins and the encoder share one serial export worker.
// An outer Task.detached is insufficient when its renderer inherits MainActor.
#if os(Android)
import Dispatch
import SwiftJNI

@globalActor
actor AndroidVideoRenderActor {
    nonisolated static let shared = AndroidVideoRenderActor()
    private nonisolated let executor = AndroidVideoSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    /// Frames/chunks may share one native attachment, but never retain its locals.
    /// Callers return Swift values or owning JObject projections, not JNI locals.
    @AndroidVideoRenderActor
    static func withJNIFrame<T>(videoFrame: Int? = nil, _ body: () throws -> T) rethrows -> T {
        #if ARIA_VIDEO_AUDIT
        let sample = videoFrame == 0 || videoFrame == 899
        if sample { dumpLocals("before_frame_\(videoFrame!)") }
        #endif
        JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 64) == 0) }
        defer {
            JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) }
            #if ARIA_VIDEO_AUDIT
            if sample { dumpLocals("after_frame_\(videoFrame!)") }
            #endif
        }
        return try body()
    }

    #if ARIA_VIDEO_AUDIT
    private nonisolated static func dumpLocals(_ label: String) {
        guard let debug = try? JClass(name: "android/os/Debug", systemClass: true) else { return }
        let method = debug.getStaticMethodID(name: "dumpReferenceTables", sig: "()V")
        if JNI.jni.exceptionCheck() != 0 { JNI.jni.exceptionClear() }
        guard let method else { return }
        print("ARIA_VIDEO_LOCAL_TABLE \(label)")
        do { try debug.callStatic(method: method, options: [], args: []) as Void }
        catch { print("ARIA_VIDEO_LOCAL_TABLE_UNAVAILABLE") }
    }
    #endif
}

private nonisolated final class AndroidVideoSerialExecutor: SerialExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "aria.video.render", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let pending = UnownedJob(job)
        queue.async {
            // Keep the worker attached for the job instead of attaching for every
            // reflected Canvas/color/bitmap call. Frame scopes below this job
            // release locals even when an async continuation runs many frames.
            jniContext {
                JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 64) == 0) }
                defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                pending.runSynchronously(on: self.asUnownedSerialExecutor())
            }
        }
    }
}
#endif
