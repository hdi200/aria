// ARIA PATCH: cache JNI method and field IDs per JClass.
//
// Skip's generated bridge declares each method ID as a computed property, so every bridged
// SwiftUI modifier call (`.frame`, `.clipped`, ...) called JNI GetMethodID, which ART
// answers with a linear search of skip.ui.View's interface methods by name and signature.
// On a Galaxy A35 that was about 5% of the main thread while editing. IDs stay valid while
// the class is loaded, and a JClass holds a reference to its class, so caching them on the
// JClass is safe. Only successful lookups are cached.
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
#if !SWIFT_JAVA_JNI_CORE
import CJNI
#endif

final class AriaJNIIDCache: @unchecked Sendable {
    enum Kind: UInt8 { case instanceMethod, staticMethod, instanceField, staticField }

    private struct Key: Hashable {
        let kind: Kind
        let name: String
        let sig: String
    }

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private var methods: [Key: JavaMethodID] = [:]
    private var fields: [Key: JavaFieldID] = [:]

    init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func method(_ kind: Kind, _ name: String, _ sig: String) -> JavaMethodID? {
        pthread_mutex_lock(mutex); defer { pthread_mutex_unlock(mutex) }
        return methods[Key(kind: kind, name: name, sig: sig)]
    }

    func field(_ kind: Kind, _ name: String, _ sig: String) -> JavaFieldID? {
        pthread_mutex_lock(mutex); defer { pthread_mutex_unlock(mutex) }
        return fields[Key(kind: kind, name: name, sig: sig)]
    }

    func store(_ id: JavaMethodID, _ kind: Kind, _ name: String, _ sig: String) {
        pthread_mutex_lock(mutex); defer { pthread_mutex_unlock(mutex) }
        methods[Key(kind: kind, name: name, sig: sig)] = id
    }

    func store(_ id: JavaFieldID, _ kind: Kind, _ name: String, _ sig: String) {
        pthread_mutex_lock(mutex); defer { pthread_mutex_unlock(mutex) }
        fields[Key(kind: kind, name: name, sig: sig)] = id
    }
}
