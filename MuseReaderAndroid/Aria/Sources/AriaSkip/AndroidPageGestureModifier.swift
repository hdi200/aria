import Foundation
import SwiftUI
#if os(Android)
import SkipFuse
import SkipBridge
import SwiftJNI

/// The Kotlin detector calls Swift synchronously on Compose's main thread. Its native
/// closure is composition-owned, replaced on recomposition, never kept in a static queue.
extension View {
    func androidPageGestures(editing: Bool, readingHold: Bool, annotating: Bool, canPan: Bool,
        event: @escaping @MainActor (Int32, Double, Double, Double, Double) -> Int32) -> some View {
        let modifier = jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 32) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            let callback = SwiftClosure5.javaObject(forMainActor: event, options: [])!
            let object = try! AndroidPageGestureJNI.type.create(ctor: AndroidPageGestureJNI.constructor,
                options: [], args: [editing.toJavaParameter(options: []), readingHold.toJavaParameter(options: []),
                    annotating.toJavaParameter(options: []), canPan.toJavaParameter(options: []),
                    callback.toJavaParameter(options: [])])
            return try! AnyDynamicObject(for: object, options: [])
        }
        return composeModifier { modifier }
    }
}

private enum AndroidPageGestureJNI {
    static let type = try! JClass(name: "aria/skip/AriaPageGestures")
    static let constructor = type.getMethodID(name: "<init>", sig: "(ZZZZLkotlin/jvm/functions/Function5;)V")!
}

enum AndroidPageGestureTrace {
    private static let type = try! JClass(name: "aria/skip/AriaGestureDiagnostics")
    private static let enabledMethod = type.getStaticMethodID(name: "enabled", sig: "()Z")!
    private static let recordMethod = type.getStaticMethodID(name: "record", sig: "(Ljava/lang/String;)V")!
    // Read once on first use. Enable the local log property before starting the app.
    private static let enabled: Bool = {
        (try? jniContext { () throws -> Bool in
            try type.callStatic(method: enabledMethod, options: [], args: [])
        }) ?? false
    }()

    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        try? jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            try type.callStatic(method: recordMethod, options: [],
                args: [message().toJavaParameter(options: [])]) as Void
        }
    }
}
#endif
