import SwiftUI
#if os(Android)
import SkipFuse
import SkipBridge
import SwiftJNI

/// The Android side of `ariaShapeShadow` (CompatibilityViewModifiers.swift): a Compose
/// `dropShadow` of the view's rounded-rectangle outline (AriaShapeShadow.kt), in place of
/// skip-ui's `.shadow`, which composes and blurs the whole view a second time.
///
/// Each distinct shadow is one immutable Kotlin object, created once and shared, so a
/// view body that evaluates often doesn't create JNI objects.
@MainActor
enum AndroidShapeShadowCache {
    struct Key: Hashable {
        let topLeading, topTrailing, bottomTrailing, bottomLeading: Double
        let opacity, radius, x, y: Double
    }

    private static var modifiers: [Key: AnyDynamicObject] = [:]

    static func modifier(for key: Key) -> AnyDynamicObject {
        if let modifier = modifiers[key] { return modifier }
        let modifier = jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            let args = [key.topLeading, key.topTrailing, key.bottomTrailing, key.bottomLeading,
                        key.opacity, key.radius, key.x, key.y].map { $0.toJavaParameter(options: []) }
            let object = try! ShapeShadowJNI.type.create(ctor: ShapeShadowJNI.ctor, options: [], args: args)
            return try! AnyDynamicObject(for: object, options: [])
        }
        modifiers[key] = modifier
        return modifier
    }
}

private enum ShapeShadowJNI {
    static let type = try! JClass(name: "aria/skip/AriaShapeShadow")
    static let ctor = type.getMethodID(name: "<init>", sig: "(DDDDDDDD)V")!
}

extension View {
    func androidShapeShadow(opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat,
                            topLeading: CGFloat, topTrailing: CGFloat,
                            bottomTrailing: CGFloat, bottomLeading: CGFloat) -> some View {
        let key = AndroidShapeShadowCache.Key(
            topLeading: Double(topLeading), topTrailing: Double(topTrailing),
            bottomTrailing: Double(bottomTrailing), bottomLeading: Double(bottomLeading),
            opacity: opacity, radius: Double(radius), x: Double(x), y: Double(y))
        let modifier = AndroidShapeShadowCache.modifier(for: key)
        return composeModifier { modifier }
    }
}
#endif
