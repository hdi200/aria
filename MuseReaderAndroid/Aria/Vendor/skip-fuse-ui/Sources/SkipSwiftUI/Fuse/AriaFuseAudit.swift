// ARIA PATCH: TEST-only native construction/conversion boundaries. No view retention.
#if ARIA_PHONE_AUDIT
import Foundation
#if os(Android)
import Bionic
#endif

public enum AriaFuseAudit {
    nonisolated(unsafe) public static var active = false
    nonisolated(unsafe) public static var record: (@Sendable (String, Int) -> Void)?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var depths: [UInt: Int] = [:]
    nonisolated(unsafe) private static var nodes: [UInt: Int] = [:]
    nonisolated(unsafe) private static var types: [Int: Any.Type] = [:]
    nonisolated public static func point(_ name: String, value: Int = 0) {
        if active { record?(name, value) }
    }
    nonisolated public static func enter(_ type: Any.Type) -> Int {
        guard active else { return 0 }
        #if os(Android)
        let thread = UInt(pthread_self())
        #else
        let thread: UInt = 1
        #endif
        lock.lock()
        let depth = depths[thread, default: 0]
        depths[thread] = depth + 1
        nodes[thread, default: 0] += 1
        let id = Int(bitPattern: ObjectIdentifier(type))
        if depth == 0 { types[id] = type; nodes[thread] = 1 }
        lock.unlock()
        if depth == 0 { point("fuse_conversion_begin", value: id) }
        return depth == 0 ? id : -1
    }
    nonisolated public static func leave(_ id: Int) {
        guard id != 0 else { return }
        #if os(Android)
        let thread = UInt(pthread_self())
        #else
        let thread: UInt = 1
        #endif
        lock.lock(); depths[thread, default: 1] -= 1
        let count = nodes[thread, default: 0]; lock.unlock()
        if id != -1 {
            point("fuse_conversion_end", value: id)
            point("fuse_conversion_nodes", value: count)
        }
    }
    // Metadata names are generated after timed phases, never per key/conversion.
    nonisolated public static func typeNames() -> [String: String] {
        lock.lock(); let snapshot = types; lock.unlock()
        return Dictionary(uniqueKeysWithValues: snapshot.map { (String($0.key), String(String(reflecting: $0.value).prefix(2000))) })
    }
}
#endif
