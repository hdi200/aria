// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import SkipBridge
import SkipUI
import SwiftJNI
#if ARIA_PERF_DIAGNOSTICS
import Foundation
#endif

public final class BridgedStateBox<Value> {
    private let comparator: (Value, Value) -> Bool

    init(_ value: Value, comparator: @escaping (Value, Value) -> Bool) {
        self._value = Box(value)
        self.comparator = comparator
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("StateBox<\(Value.self)>", created: true)
        #endif
    }

    // ARIA PATCH: opt-in lifetime evidence for state-wrapper ownership.
    deinit {
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("StateBox<\(Value.self)>", created: false)
        #endif
    }

    var value: Value {
        get {
            _value.Java_stateSupport?.access()
            // Report this slot's animation provenance so an animatable modifier consuming
            // this read can decide animate-vs-snap. Skip the call entirely for un-stamped
            // slots — the common case for state never written in withAnimation. The stamp
            // lives on the shared box so it survives bridged view re-instantiation.
            if let animation = _value.lastWriteAnimation {
                StateProvenance.recordRead(animation)
            }
            return _value.value
        }
        set {
            // Stamp the slot with the active withAnimation scope's animation; a plain write
            // clears a stale stamp so later reads don't wrongly animate.
            let animation = StateProvenance.makeWriteStamp()
            if animation != nil || _value.lastWriteAnimation != nil {
                _value.lastWriteAnimation = animation
            }
            let isUpdate = !comparator(_value.value, newValue)
            _value.value = newValue
            if isUpdate {
                _value.Java_stateSupport?.update()
            }
        }
    }
    private var _value: Box<Value>

    public func Java_initStateSupport() -> StateSupport {
        let ptr = SwiftObjectPointer.pointer(to: _value, retain: true)
        let support = StateSupport(valueHolder: ptr)
        _value.Java_stateSupport = AriaStateSupportReference(support)
        #if ARIA_PERF_DIAGNOSTICS && SKIP_BRIDGE
        _value.ariaDescribeImageOwner("support_init")
        #endif
        return support
    }

    public func Java_syncStateSupport(_ support: StateSupport) {
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("StateSync", created: true)
        #endif
        let box: Box<Value> = support.valueHolder.pointee()!
        _value = box
        // ARIA PATCH: incoming projections are temporary. Compose remembers the
        // support and the support owns the native value. Transient native page
        // projections must not independently extend that Java owner's lifetime.
        // Identity comparison also avoids a weak-ref allocation on every Evaluate.
        if box.Java_stateSupport?.isSameObject(as: support) != true {
            box.Java_stateSupport = AriaStateSupportReference(support)
        }
    }
}

//extension BridgedStateBox : @unchecked Sendable where Value : Sendable {
//}

// ARIA PATCH: only Android's generated projections own JNI objects. The Skip
// package's Darwin scaffold uses its native StateSupport implementation instead.
final class AriaStateSupportReference {
    #if SKIP_BRIDGE
    private let reference: JWeakObject
    #else
    private let reference: StateSupport
    #endif
    private var reportedCleared = false

    init(_ support: StateSupport) {
        #if SKIP_BRIDGE
        reference = JWeakObject(support.Java_peer)
        #else
        reference = support
        #endif
    }

    func isSameObject(as support: StateSupport) -> Bool {
        #if SKIP_BRIDGE
        reference.isSameObject(as: support.Java_peer)
        #else
        reference === support
        #endif
    }

    var isAlive: Bool {
        #if SKIP_BRIDGE
        reference.withLocalReference { _ in true } ?? false
        #else
        true
        #endif
    }

    func access() {
        #if SKIP_BRIDGE
        notify(method: AriaStateSupportMethods.access, operation: "access")
        #else
        reference.access()
        #endif
    }

    func update() {
        #if SKIP_BRIDGE
        notify(method: AriaStateSupportMethods.update, operation: "update")
        #else
        reference.update()
        #endif
    }

    #if SKIP_BRIDGE
    private func notify(method: JavaMethodID, operation: String) {
        if (try! reference.callIfAlive(method: method)) == false {
            #if ARIA_PERF_DIAGNOSTICS
            AriaJNILifecycle.record("cleared_support_" + operation, created: true)
            if !reportedCleared {
                reportedCleared = true
                print("ARIA_STATE_SUPPORT_CLEARED operation=\(operation) nativeValuePreserved=true reattach=Java_initStateSupport")
            }
            #endif
        }
    }
    #endif
}

#if SKIP_BRIDGE
private enum AriaStateSupportMethods {
    static let javaClass = try! JClass(name: "skip/ui/StateSupport")
    static let access = javaClass.getMethodID(name: "access", sig: "()V")!
    static let update = javaClass.getMethodID(name: "update", sig: "()V")!
}
#endif

#if ARIA_PERF_DIAGNOSTICS && SKIP_BRIDGE
// ARIA PATCH: deterministic cleared-owner + native-attached-thread diagnostics.
// Not linked into the upload build. No score or application model is involved.
extension BridgedStateBox where Value == Int {
    public static func ariaRunLifecycleProbe() {
        jniContext {
            let box = BridgedStateBox(7, comparator: ==)
            do {
                JNI.jni.withEnv { _ = $0.PushLocalFrame($1, 16) }
                defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                let support = box.Java_initStateSupport()
                box.Java_syncStateSupport(support)
                precondition(box.value == 7)
                withExtendedLifetime(support) {}
            }
            let system = try! JClass(name: "java/lang/System", systemClass: true)
            let gc = system.getStaticMethodID(name: "gc", sig: "()V")!
            let finalize = system.getStaticMethodID(name: "runFinalization", sig: "()V")!
            for _ in 0..<50 {
                try! system.callStatic(method: gc, options: [], args: []) as Void
                try! system.callStatic(method: finalize, options: [], args: []) as Void
                if box._value.Java_stateSupport?.isAlive == false { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            precondition(box._value.Java_stateSupport?.isAlive == false, "Audit owner did not collect")
            box.value = 42
            precondition(box.value == 42, "Cleared support lost native state")
            let replacement = box.Java_initStateSupport()
            box.Java_syncStateSupport(replacement)
            precondition(box.value == 42, "Reattachment lost native state")
            print("ARIA_STATE_LIFECYCLE_PROBE cleared=true nativeValue=42 reattachedValue=42")

            // The outer jniContext attaches this native worker once for the whole
            // loop. No incoming JNI frame or per-iteration detach can hide a leak.
            AriaJNILifecycle.dumpReferenceTables("native_worker_before_100000_accesses")
            let localsBefore = AriaJNILifecycle.liveCount("weak_locals")
            for _ in 0..<100_000 { box._value.Java_stateSupport?.access() }
            let localsAfter = AriaJNILifecycle.liveCount("weak_locals")
            AriaJNILifecycle.dumpReferenceTables("native_worker_after_100000_accesses")
            precondition(localsBefore == localsAfter, "Scoped JNI local leak")
            print("ARIA_NATIVE_LOCAL_PROBE accesses=100000 before=\(localsBefore) after=\(localsAfter)")
            withExtendedLifetime(replacement) {}
        }
    }
}
#endif
