import SwiftUI
#if os(Android)
import SkipFuse
import SkipBridge
import SwiftJNI

/// Owns a single stateless-content Kotlin position modifier for this reader.
@MainActor
final class AndroidSelectionOverlayPosition {
    private let object: JObject
    let modifier: AnyDynamicObject

    init() {
        (object, modifier) = jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            let object = try! PositionJNI.type.create(ctor: PositionJNI.ctor, options: [], args: [])
            return (JObject(object), try! AnyDynamicObject(for: object, options: []))
        }
    }

    func move(to point: CGPoint) {
        jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            try! object.call(method: PositionJNI.update, options: [],
                args: [Double(point.x).toJavaParameter(options: []), Double(point.y).toJavaParameter(options: [])])
        }
    }
}

private enum PositionJNI {
    static let type = try! JClass(name: "aria/skip/AriaSelectionOverlayPosition")
    static let ctor = type.getMethodID(name: "<init>", sig: "()V")!
    static let update = type.getMethodID(name: "update", sig: "(DD)V")!
}

extension View {
    @ViewBuilder
    func androidSelectionOverlayPosition(_ position: AndroidSelectionOverlayPosition?, fallback: CGPoint) -> some View {
        if let position {
            composeModifier { position.modifier }
        } else {
            self.position(fallback)
        }
    }
}
#endif
