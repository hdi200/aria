// ARIA PATCH: a native observer must not globally root its Java lifecycle owner.
import Foundation

/// Does not keep the Java object alive. A promoted local reference protects every
/// operation against concurrent collection; the raw weak reference never escapes.
public final class JWeakObject: @unchecked Sendable {
    private let reference: JavaWeakReference

    public init(_ object: JObject) {
        reference = jniContext {
            JNI.jni.withEnv { $0.NewWeakGlobalRef($1, object.ptr)! }
        }
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("weak_globals", created: true)
        #endif
    }

    deinit {
        jniContext { JNI.jni.withEnv { $0.DeleteWeakGlobalRef($1, reference) } }
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("weak_globals", created: false)
        #endif
    }

    public func isSameObject(as object: JObject) -> Bool {
        jniContext { JNI.jni.withEnv { $0.IsSameObject($1, reference, object.ptr) != 0 } }
    }

    /// Returns nil when Java has collected the owner. Never check-then-use a weak JNI
    /// reference: NewLocalRef both tests it and retains the referent for this scope.
    public func withLocalReference<T>(_ body: (JavaObjectPointer) throws -> T) rethrows -> T? {
        try jniContext {
            guard let local = JNI.jni.newLocalRef(reference) else { return nil }
            // ARIA PATCH: attached native threads do not get JNI-frame cleanup.
            #if ARIA_PERF_DIAGNOSTICS
            AriaJNILifecycle.record("weak_locals", created: true)
            #endif
            defer {
                JNI.jni.deleteLocalRef(local)
                #if ARIA_PERF_DIAGNOSTICS
                AriaJNILifecycle.record("weak_locals", created: false)
                #endif
            }
            return try body(local)
        }
    }

    /// Access/update notifications need no Swift projection or additional global ref.
    @discardableResult
    public func callIfAlive(method: JavaMethodID, options: JConvertibleOptions = [],
                            args: [JavaParameter] = []) throws -> Bool {
        try withLocalReference { local in
            try JNI.jni.withEnvThrowing(options: options) { $0.CallVoidMethodA($1, local, method.methodID, args) }
            return true
        } ?? false
    }
}
