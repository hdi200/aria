// ARIA PATCH: exercise identity, method calls and collection of a weak JNI owner.
@testable import SwiftJNI
import Foundation
import Testing

@Suite(.serialized) struct AriaWeakObjectTests {
    init() throws { try JNI.attachJVM(launch: !isAndroid) }

    @Test func weakIdentityAndNotification() throws {
        try jniContext {
            let type = try JClass(name: "java/lang/StringBuilder", systemClass: true)
            let ctor = try #require(type.getMethodID(name: "<init>", sig: "()V"))
            let first = JObject(try type.create(ctor: ctor, options: [], args: []))
            let second = JObject(try type.create(ctor: ctor, options: [], args: []))
            let weak = JWeakObject(first)
            #expect(weak.isSameObject(as: first))
            #expect(!weak.isSameObject(as: second))
            let length = try #require(type.getMethodID(name: "setLength", sig: "(I)V"))
            #expect(try weak.callIfAlive(method: length, args: [JavaParameter(i: 3)]))
            let getLength = try #require(type.getMethodID(name: "length", sig: "()I"))
            let actual: Int32 = try first.call(method: getLength, options: [], args: [])
            #expect(actual == 3)
        }
    }

    @Test func collectedOwnerIsSafe() throws {
        try jniContext {
            let type = try JClass(name: "java/lang/Object", systemClass: true)
            let ctor = try #require(type.getMethodID(name: "<init>", sig: "()V"))
            let weak: JWeakObject = try {
                JNI.jni.withEnv { _ = $0.PushLocalFrame($1, 16) }
                defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                let object = JObject(try type.create(ctor: ctor, options: [], args: []))
                return JWeakObject(object)
            }()
            let system = try JClass(name: "java/lang/System", systemClass: true)
            let gc = try #require(system.getStaticMethodID(name: "gc", sig: "()V"))
            for _ in 0..<50 {
                try system.callStatic(method: gc, options: [], args: []) as Void
                if weak.withLocalReference({ _ in true }) == nil { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            #expect(weak.withLocalReference({ _ in true }) == nil)
            let notify = try #require(type.getMethodID(name: "notify", sig: "()V"))
            #expect(try weak.callIfAlive(method: notify) == false)
        }
    }
}
