// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0

import SwiftJNI

final class Box<Value> {
    // ARIA PATCH: Compose owns StateSupport. Keep one weak JNI reference per
    // remembered slot, shared by every transient native view projection.
    var Java_stateSupport: AriaStateSupportReference?

    var value: Value {
        didSet {
            #if ARIA_PERF_DIAGNOSTICS && SKIP_BRIDGE
            ariaDescribeImageOwner("write")
            #endif
        }
    }

    /// The expirable stamp of the animated write that last changed this box, if any. Lives on
    /// the box rather than its owning property wrapper because the box is the unit shared
    /// across bridged view re-instantiations (`Java_syncStateSupport` swaps boxes between
    /// `BridgedStateBox` instances) — a stamp on the wrapper would be lost when the body is
    /// re-evaluated on a freshly synced view value.
    var lastWriteAnimation: AnimationWriteStamp?

    init(_ value: Value) {
        self.value = value
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("StateValue<\(Value.self)>", created: true)
        #endif
    }

    // ARIA PATCH: distinguish actual remembered values from transient wrappers.
    deinit {
        #if ARIA_PERF_DIAGNOSTICS && SKIP_BRIDGE
        ariaDescribeImageOwner("deinit")
        #endif
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("StateValue<\(Value.self)>", created: false)
        #endif
    }

    #if ARIA_PERF_DIAGNOSTICS && SKIP_BRIDGE
    func ariaDescribeImageOwner(_ event: String) {
        guard Value.self == Optional<UIImage>.self else { return }
        let image = value as? UIImage
        let handle = image?.uiImage.Java_peer.ariaDiagnosticGlobalHandle ?? 0
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        print("ARIA_IMAGE_OWNER event=\(event) box=\(address) globalHandle=\(handle)")
    }
    #endif
}

//extension Box : @unchecked Sendable where Value : Sendable {
//}
