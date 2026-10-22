// Copyright 2024–2026 Skip
#if SWIFT_JAVA_JNI_CORE
import SwiftJavaJNICore
#else
import CJNI
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import CRT
import WinSDK
#endif

// MARK: JNI Types

#if SWIFT_JAVA_JNI_CORE
public typealias JavaVM = SwiftJavaJNICore.JavaVM
public typealias JNIEnv = SwiftJavaJNICore.JNIEnv
#else
public typealias JavaVM = CJNI.JavaVM
public typealias JNIEnv = CJNI.JNIEnv
#endif
public typealias JNIEnvPointer = UnsafeMutablePointer<JNIEnv?>
public typealias JavaBoolean = jboolean
public typealias JavaByte = jbyte
public typealias JavaChar = jchar
public typealias JavaShort = jshort
public typealias JavaInt = jint
public typealias JavaLong = jlong
public typealias JavaFloat = jfloat
public typealias JavaDouble = jdouble

public typealias JavaObjectPointer = jobject
public typealias JavaClassPointer = jobject
public typealias JavaString = jstring
public typealias JavaArray = jarray
public typealias JavaObjectArray = jobjectArray
public typealias JavaBooleanArray = jbooleanArray
public typealias JavaByteArray = jbyteArray
public typealias JavaCharArray = jcharArray
public typealias JavaShortArray = jshortArray
public typealias JavaIntArray = jintArray
public typealias JavaLongArray = jlongArray
public typealias JavaFloatArray = jfloatArray
public typealias JavaDoubleArray = jdoubleArray
public typealias JavaThrowable = jthrowable
public typealias JavaWeakReference = jweak
public typealias JavaParameter = jvalue

// MARK: JNI

/// Whether the shared JNI instance has been initialized.
public var isJNIInitialized: Bool {
    JNI.jni != nil
}

/// Establish a context in which to perform JNI operations.
///
/// - Warning: You cannot initiate JNI operations from native code outside of a context.
public func jniContext<T>(_ block: () throws -> T) rethrows -> T {
    precondition(JNI.jni != nil, "JNI.jni was unset")
    precondition(JNI.jni._jvm.pointee != nil, "JNI.jni._jvm.pointee was nil")

    let jvm: JNIInvokeInterface = JNI.jni._jvm.pointee!.pointee
    var tenv: UnsafeMutableRawPointer?
    let threadStatus = jvm.GetEnv(JNI.jni._jvm, &tenv, JavaInt(JNI_VERSION_1_6))

    // Ensure that there is a `JNIEnvPointer` for the current thread
    // See: https://developer.android.com/training/articles/perf-jni#threads
    switch threadStatus {
    case JNI_OK:
        return try block()
    case JNI_EDETACHED:
        // we weren't attached to the Java thread; attach, perform the block, and then detach
        var tenv: JNIEnvPointer!
        if jvm.AttachCurrentThread(JNI.jni._jvm, &tenv, nil) != JNI_OK {
            fatalError("SwiftJNI: unable to attach JNI to current thread")
        }
        defer {
            if jvm.DetachCurrentThread(JNI.jni._jvm) != JNI_OK {
                fatalError("SwiftJNI: unable to detach JNI from thread")
            }
        }

        // We set the ClassLoader for the current thread to be the application ClassLoader, otherwise classes defined in the app may not be found when loaded from a natively-created thread when loaded via reflection
        JClassLoader.setThreadClassLoader()
        return try block()
    case JNI_EVERSION:
        fatalError("SwiftJNI: unsupported JNI version")
    default:
        fatalError("SwiftJNI: unexpected JNI thread status: \(threadStatus)")
    }
}

#if SWIFT_JAVA_JNI_CORE
public typealias JNI = SwiftJavaJNICore.JavaVirtualMachine

extension JNI {
    public static var jni: JNI! { // this should be set in "OnLoad" and so should always exist
        get {
            try! JavaVirtualMachine.shared()
        }

        set {
            JavaVirtualMachine.setShared(newValue)
            jniContext {
                JClassLoader.globalClassLoader = try? JThread.currentThread.getContextClassLoader() // cache the global class loader on initialization
            }
        }
    }

    // Normally we init the jni global ourselves in JNI_OnLoad
    public convenience init(jvm: UnsafeMutablePointer<JavaVM?>) {
        self.init(adoptingJVM: jvm)
    }

    /// Our reference to the Java Virtual Machine, to be set on init
    var _jvm: UnsafeMutablePointer<JavaVM?> {
        get {
            var jvm: UnsafeMutablePointer<JavaVM?>? = nil
            let env = try! environment()
            guard env.pointee!.pointee.GetJavaVM(env, &jvm) == JNI_OK, let jvm else {
                fatalError("unable to call getJavaVM")
            }
            return jvm
        }
    }
}
#else
/// Gateway to JVM and JNI functionality.
public class JNI {
    /// The single shared singleton JNI instance for the process.
    nonisolated(unsafe) public static var jni: JNI! { // this should be set in "OnLoad" and so should always exist
        didSet {
            jniContext {
                JClassLoader.globalClassLoader = try? JThread.currentThread.getContextClassLoader() // cache the global class loader on initialization
            }
        }
    }

    /// Our reference to the Java Virtual Machine, to be set on init
    let _jvm: UnsafeMutablePointer<JavaVM?>

    // Normally we init the jni global ourselves in JNI_OnLoad
    public init(jvm: UnsafeMutablePointer<JavaVM?>) {
        self._jvm = jvm
    }
}
#endif

extension JNI {
    /// Perform an operation with the current thread's `JNIEnviPointer`.
    public func withEnv<T>(_ block: (JNINativeInterface, JNIEnvPointer) throws -> T) rethrows -> T {
        let jvm: JNIInvokeInterface = _jvm.pointee!.pointee
        var tenv: UnsafeMutableRawPointer?
        let threadStatus = jvm.GetEnv(_jvm, &tenv, JavaInt(JNI_VERSION_1_6))
        guard threadStatus == JNI_OK else {
            fatalError("SwiftJNI: you must perform JNI operations within a jniContext { ... } block")
        }
        let env = tenv!.assumingMemoryBound(to: JNIEnv?.self)
        return try block(env.pointee!.pointee, env)
    }

    /// Same as `withEnv`, but also checks for any java exceptions. If an exception occurred,
    /// it will throw a `JavaException` and clear the JNI exception.
    public func withEnvThrowing<T>(options: JConvertibleOptions, _ block: (JNINativeInterface, JNIEnvPointer) throws -> T) throws -> T {
        let result = try withEnv(block)
        try checkExceptionAndThrow(options: options)
        return result
    }

    /// Checks whether there is a Java exception outstanding, and if so, clears the exception and throws it as a Swift error.
    public func checkExceptionAndThrow(options: JConvertibleOptions) throws {
        if let throwable = self.exceptionOccurred() {
            self.exceptionClear()
            throw JThrowable(throwable).toError(options: options)
        }
    }

    @discardableResult public func checkExceptionAndClear() -> Bool {
        if self.exceptionCheck() == true {
            self.exceptionClear()
            return true
        } else {
            return false
        }
    }
}

extension JNI {
    /// The JNI version in effect
    public var version: JavaInt { withEnv { $0.GetVersion($1) } }

    private func getJavaVM(vm: UnsafeMutablePointer<UnsafeMutablePointer<JavaVM?>?>) -> JavaInt {
        withEnv { $0.GetJavaVM($1, vm) }
    }

    public func registerNatives(targetClass: JavaClassPointer, _ methods: UnsafePointer<JNINativeMethod>, _ nMethods: JavaInt) -> JavaInt {
        withEnv { $0.RegisterNatives($1, targetClass, methods, nMethods) }
    }

    public func unregisterNatives(targetClass: JavaClassPointer) -> JavaInt {
        withEnv { $0.UnregisterNatives($1, targetClass) }
    }

    public func exceptionCheck() -> JavaBoolean {
        withEnv { $0.ExceptionCheck($1) }
    }

    public func exceptionClear() {
        withEnv { $0.ExceptionClear($1) }
    }

    public func exceptionOccurred() -> JavaThrowable? {
        withEnv { $0.ExceptionOccurred($1) }
    }

    public func exceptionDescribe() {
        withEnv { $0.ExceptionDescribe($1) }
    }

    public func monitorEnter(obj: JavaObjectPointer) -> JavaInt {
        withEnv { $0.MonitorEnter($1, obj) }
    }

    public func monitorExit(obj: JavaObjectPointer) -> JavaInt {
        withEnv { $0.MonitorExit($1, obj) }
    }

    func synchronized<T>(_ obj: JavaObjectPointer, _ block: () throws -> T) rethrows -> T {
        try withEnv { inv, env in
            if inv.MonitorEnter(env, obj) != JNI_OK {
                fatalError("SwiftJNI: unable to MonitorEnter")
            }
            defer {
                if inv.MonitorExit(env, obj) != JNI_OK {
                    fatalError("SwiftJNI: unable to MonitorExit")
                }
            }
            return try block()
        }
    }

    fileprivate func findClass(_ name: String) -> JavaClassPointer? {
        withEnv { $0.FindClass($1, name) }
    }

    public func newGlobalRef(_ obj: JavaObjectPointer) -> JavaObjectPointer! {
        let reference = withEnv { $0.NewGlobalRef($1, obj) }
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("globals", created: true)
        #endif
        return reference
    }

    public func deleteGlobalRef(_ obj: JavaObjectPointer) {
        withEnv { $0.DeleteGlobalRef($1, obj) }
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("globals", created: false)
        #endif
    }

    public func newLocalRef(_ obj: JavaObjectPointer) -> JavaObjectPointer! {
        withEnv { $0.NewLocalRef($1, obj) }
    }

    public func deleteLocalRef(_ obj: JavaObjectPointer) {
        withEnv { $0.DeleteLocalRef($1, obj) }
    }

    public func getObjectClass(_ obj: JavaObjectPointer) -> JavaClassPointer! {
        withEnv { $0.GetObjectClass($1, obj) }
    }

    public func getByteArrayElements(_ array: JavaByteArray) -> (UnsafeMutablePointer<JavaByte>?, JavaInt) {
        withEnv { ($0.GetByteArrayElements($1, array, nil), $0.GetArrayLength($1, array)) }
    }

    public func releaseByteArrayElements(_ array: JavaByteArray, elements: UnsafeMutablePointer<JavaByte>?, mode: JniReleaseArrayElementsMode) {
        withEnv { $0.ReleaseByteArrayElements($1, array, elements, mode.rawValue) }
    }

    public func newByteArray(_ array: UnsafeRawPointer?, size: JavaInt) -> JavaByteArray? {
        withEnv {
            let byteArray = $0.NewByteArray($1, size)
            $0.SetByteArrayRegion($1, byteArray, 0, size, array)
            return byteArray
        }
    }
}

/// https://developer.android.com/training/articles/perf-jni#primitive-arrays
public enum JniReleaseArrayElementsMode : jint {
    /// Copy back the content and free the elems buffer
    case unpin = 0
    /// Copy back the content but do not free the elems buffer
    case commit = 1 // JNI_COMMIT
    /// Free the buffer without copying back the possible changes
    case abort = 2 // JNI_ABORT
}

public struct JavaMethodID : @unchecked Sendable {
    let methodID: jmethodID
}

public struct JavaFieldID : @unchecked Sendable {
    let fieldID: jfieldID
}


// MARK: Errors

/// A system-level error relating to interacting with the Java Virtual Machine.
public struct JVMError: Error, CustomStringConvertible {
    public var description: String

    public init(description: String) {
        self.description = description
    }
}

/// A class could not be loaded
public struct ClassNotFoundError: Error, CustomStringConvertible {
    public var description: String

    public init(name: String) {
        self.description = "Unable to load class: \(name)"
    }
}

/// An unexpected JNI error
public struct JNIError: Error, CustomStringConvertible {
    public var description: String

    public init(description: String = "JNIError", clear: Bool) {
        self.description = description

        JNI.jni.exceptionDescribe()
        if clear {
            JNI.jni.exceptionClear()
        }
    }
}

/// An error from a Java `Throwable`.
public struct ThrowableError: Error, CustomStringConvertible, JObjectProtocol, JConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }

    public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> ThrowableError {
        return JThrowable.descriptionToError(obj!, options: options)
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        return JThrowable.descriptionToThrowable(self, options: options)
    }
}

// MARK: Convertions

/// Java conversion options.
public struct JConvertibleOptions: OptionSet {
    /// Optimize for bridging to pure Kotlin code rather than transpiled Swift.
    nonisolated(unsafe) public static let kotlincompat = JConvertibleOptions(rawValue: 1 << 0)
    /// Map to a Kotlin container type. Useful for passing an array or dictionary to a known List or Map, even when content might
    /// not be expected to be `.kotlincompat`.
    nonisolated(unsafe) public static let kotlincompatContainer = JConvertibleOptions(rawValue: 1 << 1)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Type that can be converted to and from Java.
public protocol JConvertible {
    static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Self
    static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Self

    static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Self
    func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Void

    static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Self
    func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Void

    static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self
    func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer?

    func toJavaParameter(options: JConvertibleOptions) -> JavaParameter
}

/// Type represented by a Java object.
public protocol JObjectProtocol {
}

extension JConvertible where Self: JObjectProtocol {
    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Self {
        fromJavaObject(try JNI.jni.withEnvThrowing(options: options) { $0.CallObjectMethodA($1, obj, method.methodID, args) }, options: options)
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Self {
        fromJavaObject(try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticObjectMethodA($1, cls, method.methodID, args) }, options: options)
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Self {
        fromJavaObject(JNI.jni.withEnv { $0.GetObjectField($1, obj, field.fieldID) }, options: options)
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Void {
        JNI.jni.withEnv { $0.SetObjectField($1, obj, field.fieldID, toJavaObject(options: options)) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Self {
        fromJavaObject(JNI.jni.withEnv { $0.GetStaticObjectField($1, cls, field.fieldID) }, options: options)
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Void {
        JNI.jni.withEnv { $0.SetStaticObjectField($1, cls, field.fieldID, toJavaObject(options: options)) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(l: toJavaObject(options: options))
    }
}

/// All optionals are represented by Java objects
extension Optional: JObjectProtocol {
}

extension Optional: JConvertible where Wrapped: JConvertible {
    public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
        if let obj {
            return Wrapped.fromJavaObject(obj, options: options)
        } else {
            return nil
        }
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        if let self {
            return self.toJavaObject(options: options)
        } else {
            return nil
        }
    }
}

extension JavaObjectPointer: JObjectProtocol {
}

extension JavaObjectPointer: JConvertible {
    public func get<T: JConvertible>(field: JavaFieldID) -> T {
        return T.load(field, of: self, options: [])
    }

    public func set<T: JConvertible>(field: JavaFieldID, value: T, options: JConvertibleOptions) {
        value.store(field, of: self, options: options)
    }

    public func call(method: JavaMethodID, options: JConvertibleOptions, args : [JavaParameter]) throws -> Void {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallVoidMethodA($1, self, method.methodID, args) }
    }

    public func call<T>(method: JavaMethodID, options: JConvertibleOptions, args: [JavaParameter]) throws -> T where T: JConvertible {
        return try T.call(method, on: self, options: options, args: args)
    }

    public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> JavaObjectPointer {
        return obj!
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        return self
    }
}

/// A Java primitive wrapper, e.g. java/lang/Integer
public protocol JPrimitiveWrapperProtocol: JObjectProtocol {
    static var javaClass: JClass { get }
    static var initWithPrimitiveValueMethodID: JavaMethodID { get }
    static var primitiveValueMethodID: JavaMethodID? { get }
    static var primitiveValueFieldID: JavaFieldID? { get }

    associatedtype JConvertibleType: JConvertible
    init(_ value: JConvertibleType, options: JConvertibleOptions)
    init(_ obj: JavaObjectPointer)
    func value(options: JConvertibleOptions) throws -> JConvertibleType
}

extension JPrimitiveWrapperProtocol where Self: JObject {
    public init(_ value: JConvertibleType, options: JConvertibleOptions) {
        // we force try because primitive wrapper initializers should never fail
        let ptr = try! Self.javaClass.create(ctor: Self.initWithPrimitiveValueMethodID, options: options, args: [value.toJavaParameter(options: options)])
        self.init(ptr)
    }

    public func value(options: JConvertibleOptions) throws -> JConvertibleType {
        if let methodID = Self.primitiveValueMethodID {
            return try call(method: methodID, options: options, args: [])
        } else if let fieldID = Self.primitiveValueFieldID {
            return get(field: fieldID)
        } else {
            fatalError()
        }
    }
}

#if SWIFT_JAVA_JNI_CORE
/// A Java primitive
public protocol JPrimitiveProtocol: JConvertible, JavaValue {
    associatedtype JWrapperType: JPrimitiveWrapperProtocol
}

/// JavaValue conformance
public extension JPrimitiveProtocol {

}

#else
/// A Java primitive
public protocol JPrimitiveProtocol: JConvertible {
    associatedtype JWrapperType: JPrimitiveWrapperProtocol
}
#endif

extension JPrimitiveProtocol where JWrapperType.JConvertibleType == Self {
    public static func fromJavaObject(_ ptr: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
        if let methodID = JWrapperType.primitiveValueMethodID {
            return try! Self.call(methodID, on: ptr!, options: options, args: [])
        } else if let fieldID = JWrapperType.primitiveValueFieldID {
            return Self.load(fieldID, of: ptr!, options: options)
        } else {
            fatalError()
        }
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        return try! JWrapperType.javaClass.create(ctor: JWrapperType.initWithPrimitiveValueMethodID, options: options, args: [self.toJavaParameter(options: options)])
    }
}

// MARK: Object Wrappers

open class JObject: JObjectProtocol, @unchecked Sendable {
    #if ARIA_PERF_DIAGNOSTICS
    // ARIA PATCH: correlate a native owner with HPROF ROOT_JNI_GLOBAL's handle.
    // Reading this identifier creates neither a local nor a global reference.
    public var ariaDiagnosticGlobalHandle: UInt { UInt(bitPattern: ptr) }
    #endif
    let ptr: JavaObjectPointer

    public init(_ ptr: JavaObjectPointer) {
        self.ptr = JNI.jni.newGlobalRef(ptr)
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("JObject", created: true)
        #endif
    }

    public convenience init?(_ ptr: JavaObjectPointer?) {
        if let ptr {
            self.init(ptr as JavaObjectPointer)
        } else {
            return nil
        }
    }

    #if SWIFT_JAVA_JNI_CORE
    public required init(fromJNI value: JavaObjectPointer?, in environment: JNIEnvironment) {
        self.ptr = JNI.jni.newGlobalRef(value!)
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("JObject", created: true)
        #endif
    }
    #endif

    deinit {
        #if ARIA_PERF_DIAGNOSTICS
        AriaJNILifecycle.record("JObject", created: false)
        #endif
        jniContext { JNI.jni.deleteGlobalRef(ptr) }
    }

    /// Return a reference to this object that will not become invalid if this `JObject` struct is deallocated.
    public func safePointer() -> JavaObjectPointer {
        return JNI.jni.newLocalRef(ptr)
    }

    public func get<T: JConvertible>(field: JavaFieldID) -> T {
        return T.load(field, of: ptr, options: [])
    }

    public func set<T: JConvertible>(field: JavaFieldID, value: T, options: JConvertibleOptions) {
        value.store(field, of: ptr, options: options)
    }

    public func call(method: JavaMethodID, options: JConvertibleOptions, args : [JavaParameter]) throws -> Void {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallVoidMethodA($1, ptr, method.methodID, args) }
    }

    public func call<T>(method: JavaMethodID, options: JConvertibleOptions, args: [JavaParameter]) throws -> T where T: JConvertible {
        return try T.call(method, on: ptr, options: options, args: args)
    }
}

#if SWIFT_JAVA_JNI_CORE
/// Type represented by a Java object.
extension JObject: JavaValue {
    public typealias JNIType = JavaObjectPointer?

    public static var jvalueKeyPath: WritableKeyPath<jvalue, JNIType> { \.l }

    public func getJNIValue(in environment: SwiftJavaJNICore.JNIEnvironment) -> JNIType {
        self.ptr
    }

    public static var javaType: SwiftJavaJNICore.JavaType {
        .class(package: "java.lang", name: "Object")
    }

    public static func jniMethodCall(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIMethodCall<JNIType> {
        environment.interface.CallObjectMethodA
    }

    public static func jniFieldGet(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIFieldGet<JNIType> {
        environment.interface.GetObjectField
    }

    public static func jniFieldSet(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIFieldSet<JNIType> {
        environment.interface.SetObjectField
    }

    public static func jniStaticMethodCall(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIStaticMethodCall<JNIType> {
        environment.interface.CallStaticObjectMethodA
    }

    public static func jniStaticFieldGet(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIStaticFieldGet<JNIType> {
        environment.interface.GetStaticObjectField
    }

    public static func jniStaticFieldSet(in environment: SwiftJavaJNICore.JNIEnvironment) -> SwiftJavaJNICore.JNIStaticFieldSet<JNIType> {
        environment.interface.SetStaticObjectField
    }

    public static func jniNewArray(in environment: JNIEnvironment) -> JNINewArray {
        return { environment, size in
            let objectClass = environment.interface.FindClass(environment, "java/lang/Object")
            return environment.interface.NewObjectArray(environment, size, objectClass, nil)
        }
    }

    public static func jniGetArrayRegion(in environment: JNIEnvironment) -> JNIGetArrayRegion<JNIType> {
        { environment, array, start, length, outPointer in
            let buffer = UnsafeMutableBufferPointer(start: outPointer, count: Int(length))
            for i in start..<start + length {
                buffer.initializeElement(
                    at: Int(i),
                    to: environment.interface.GetObjectArrayElement(environment, array, Int32(i))
                )
            }
        }
    }

    public static func jniSetArrayRegion(in environment: JNIEnvironment) -> JNISetArrayRegion<JNIType> {
        { environment, array, start, length, outPointer in
            let buffer = UnsafeBufferPointer(start: outPointer, count: Int(length))
            for i in start..<start + length {
                environment.interface.SetObjectArrayElement(environment, array, i, buffer[Int(i)])
            }
        }
    }

    public static var jniPlaceholderValue: JNIType {
        nil
    }
}
#endif

public final class JClass : JObject, @unchecked Sendable {
    public let name: String

    public init(_ ptr: JavaObjectPointer, name: String) {
        self.name = name
        super.init(ptr)
    }

    /// Looks up the Java class by name.
    /// - Parameters:
    ///   - name: the name of the Java class, like `java/lang/String`
    ///   - systemClass: whether this is a system class provided by the bootclassloader, or a class that may only be available through the `JClassLoader.globalClassLoader` (which is set when JNI initializes, and typically will contain all the classes packaged with an application).
    public convenience init(name: String, systemClass: Bool = false) throws {
        if !systemClass, let classLoader = JClassLoader.globalClassLoader {
            // use the same ClassLoader as when JNI was initialized, which will include the classes bundled with the app
            let cls = try classLoader.loadClass(name.split(separator: "/").joined(separator: "."))
            self.init(cls, name: name)
        } else {
            // findClass will use the Thread's ClassLoader, and when the thread is created natively, it will only be the bootstrap ClassLoader, which doesn't contain any classes embedded in the app itself
            guard let cls = JNI.jni.findClass(name) else {
                JNI.jni.exceptionClear()
                throw ClassNotFoundError(name: name)
            }
            self.init(cls, name: name)
        }
    }
    

    #if SWIFT_JAVA_JNI_CORE
    public required init(fromJNI value: JavaObjectPointer?, in environment: JNIEnvironment) {
        // TODO: revisit required initializer
        self.name = ""
        super.init(value!)
    }
    #endif

    public func getFieldID(name: String, sig: String) -> JavaFieldID? {
        defer { JNI.jni.checkExceptionAndClear() }
        return JNI.jni.withEnv { $0.GetFieldID($1, self.ptr, name, sig).flatMap(JavaFieldID.init) }
    }

    public func getStaticFieldID(name: String, sig: String) -> JavaFieldID? {
        defer { JNI.jni.checkExceptionAndClear() }
        return JNI.jni.withEnv { $0.GetStaticFieldID($1, self.ptr, name, sig).flatMap(JavaFieldID.init) }
    }

    public func getMethodID(name: String, sig: String) -> JavaMethodID? {
        defer { JNI.jni.checkExceptionAndClear() }
        return JNI.jni.withEnv { $0.GetMethodID($1, self.ptr, name, sig).flatMap(JavaMethodID.init) }
    }

    public func getStaticMethodID(name: String, sig: String) -> JavaMethodID? {
        defer { JNI.jni.checkExceptionAndClear() }
        return JNI.jni.withEnv { $0.GetStaticMethodID($1, self.ptr, name, sig).flatMap(JavaMethodID.init) }
    }

    public func create(ctor: JavaMethodID, options: JConvertibleOptions, args: [JavaParameter]) throws -> JavaObjectPointer {
        guard let obj = try JNI.jni.withEnvThrowing(options: options, { $0.NewObjectA($1, self.ptr, ctor.methodID, args) }) else {
            throw JNIError(clear: true) // init should never return nil
        }
        return obj
    }

    public func getStatic<T: JConvertible>(field: JavaFieldID, options: JConvertibleOptions) -> T {
        return T.loadStatic(field, of: ptr, options: options)
    }

    public func setStatic<T: JConvertible>(field: JavaFieldID, value: T, options: JConvertibleOptions) {
        value.storeStatic(field, of: self.ptr, options: options)
    }

    public func callStatic(method: JavaMethodID, options: JConvertibleOptions, args : [JavaParameter]) throws -> Void {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticVoidMethodA($1, self.ptr, method.methodID, args) }
    }

    public func callStatic<T: JConvertible>(method: JavaMethodID, options: JConvertibleOptions, args: [JavaParameter]) throws -> T {
        return try T.callStatic(method, on: self.ptr, options: options, args: args)
    }
}

public final class JClassLoader: JObject, @unchecked Sendable {
    private static let javaClass = try! JClass(name: "java/lang/ClassLoader", systemClass: true)
    private static let loadClassID = javaClass.getMethodID(name: "loadClass", sig: "(Ljava/lang/String;)Ljava/lang/Class;")!

    nonisolated(unsafe) public fileprivate(set) static var globalClassLoader: JClassLoader?

    /// Sets the current thread's ClassLoader to be the single global classLoader
    public static func setThreadClassLoader() {
        if let globalClassLoader {
            try? JThread.currentThread.setContextClassLoader(globalClassLoader)
        }
    }

    fileprivate func loadClass(_ name: String) throws -> jclass {
        try call(method: Self.loadClassID, options: [], args: [name.toJavaParameter(options: [])])
    }
}

public final class JThread: JObject, @unchecked Sendable {
    private static let javaClass = try! JClass(name: "java/lang/Thread", systemClass: true)
    private static let threadCurrentThreadID = javaClass.getStaticMethodID(name: "currentThread", sig: "()Ljava/lang/Thread;")!
    private static let getContextClassLoaderID = javaClass.getMethodID(name: "getContextClassLoader", sig: "()Ljava/lang/ClassLoader;")!
    private static let setContextClassLoaderID = javaClass.getMethodID(name: "setContextClassLoader", sig: "(Ljava/lang/ClassLoader;)V")!

    /// Returns the current thread for the caller
    public static var currentThread: JThread {
        JThread(try! javaClass.callStatic(method: threadCurrentThreadID, options: [], args: []))
    }

    public func getContextClassLoader() throws -> JClassLoader? {
        JClassLoader(try call(method: Self.getContextClassLoaderID, options: [], args: []))
    }

    public func setContextClassLoader(_ loader: JClassLoader?) throws {
        try call(method: Self.setContextClassLoaderID, options: [], args: [loader?.ptr.toJavaParameter(options: []) ?? .init()])
    }
}

public final class JThrowable: JObject, @unchecked Sendable {
    private static let javaClass = try! JClass(name: "java/lang/Throwable", systemClass: true)
    private static let javaErrorExceptionClass = try! JClass(name: "skip/lib/ErrorException")
    private static let javaErrorExceptionConstructor = javaErrorExceptionClass.getMethodID(name: "<init>", sig: "(Ljava/lang/String;)V")!
    /// Handles converting the error pointer into the error that will ultimately be thrown
    nonisolated(unsafe) public static var errorConverter: ((JavaObjectPointer, JConvertibleOptions) -> Error?) = { ptr, options in descriptionToError(ptr, options: options) }

    public static func toError(_ ptr: JavaObjectPointer?, options: JConvertibleOptions) -> Error? {
        guard let ptr else {
            return nil
        }
        return errorConverter(ptr, options)
    }

    public static func descriptionToError(_ ptr: JavaObjectPointer, options: JConvertibleOptions) -> ThrowableError {
        let str = try? String.call(toStringID, on: ptr, options: options, args: [])
        return ThrowableError(description: str ?? "A Java exception occurred, and an error was raised when trying to get the exception message")
    }

    public static func toThrowable(_ error: (any Error)?, options: JConvertibleOptions) -> JavaObjectPointer? {
        guard let error else {
            return nil
        }
        guard let convertibleError = error as? JConvertible else {
            return descriptionToThrowable(error, options: options)
        }
        return convertibleError.toJavaObject(options: options)
    }

    public static func descriptionToThrowable(_ error: any Error, options: JConvertibleOptions) -> JavaObjectPointer {
        // Note: It would be nice to keep JNI independent of some of the Skip-specific skip.lib.ErrorException, but
        // if we want to support compatibility with transpiled Swift we need to use Skip types
        let throwable = try! javaErrorExceptionClass.create(ctor: javaErrorExceptionConstructor, options: options, args: [String(describing: error).toJavaParameter(options: options)])
        return throwable
    }

    /// Throw a Swift error to Kotlin.
    public static func `throw`(_ error: any Error, options: JConvertibleOptions, env: JNIEnvPointer) {
        let throwable = toThrowable(error, options: options)
        let jniEnv = env.pointee!.pointee
        let _ = jniEnv.Throw(env, throwable)
    }

    public func getMessage() throws -> String? {
        try call(method: Self.getMessageID, options: [], args: [])
    }
    private static let getMessageID = javaClass.getMethodID(name: "getMessage", sig: "()Ljava/lang/String;")!

    public func getLocalizedMessage() throws -> String? {
        try call(method: Self.getLocalizedMessageID, options: [], args: [])
    }
    private static let getLocalizedMessageID = javaClass.getMethodID(name: "getLocalizedMessage", sig: "()Ljava/lang/String;")!

    public func toString() throws -> String? {
        try call(method: Self.toStringID, options: [], args: [])
    }
    private static let toStringID = javaClass.getMethodID(name: "toString", sig: "()Ljava/lang/String;")!

    public func toError(options: JConvertibleOptions) -> Error {
        return Self.toError(ptr, options: options)!
    }
}

// MARK: Primitives

#if compiler(>=6)
extension JavaBoolean : @retroactive ExpressibleByBooleanLiteral {
}
#else
extension JavaBoolean : ExpressibleByBooleanLiteral {
}
#endif

extension JavaBoolean {
    public init(booleanLiteral value: Bool) {
        self = value ? JavaBoolean(JNI_TRUE) : JavaBoolean(JNI_FALSE)
    }
}

public final class JBoolean: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Bool
    public static let javaClass = try! JClass(name: "java/lang/Boolean", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(Z)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "booleanValue", sig: "()Z")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Bool: JPrimitiveProtocol {
    public typealias JWrapperType = JBoolean

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Bool {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallBooleanMethodA($1, obj, method.methodID, args) == JNI_TRUE }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Bool {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticBooleanMethodA($1, cls, method.methodID, args) == JNI_TRUE }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Bool {
        JNI.jni.withEnv { $0.GetBooleanField($1, obj, field.fieldID) == JNI_TRUE }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Void {
        JNI.jni.withEnv { $0.SetBooleanField($1, obj, field.fieldID, (self) ? 1 : 0) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Bool {
        JNI.jni.withEnv { $0.GetStaticBooleanField($1, cls, field.fieldID) == JNI_TRUE }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Void {
        JNI.jni.withEnv { $0.SetBooleanField($1, cls, field.fieldID, (self) ? 1 : 0) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(z: (self) ? 1 : 0)
    }
}

final public class JByte: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Int8
    public static let javaClass = try! JClass(name: "java/lang/Byte", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(B)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "byteValue", sig: "()B")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Int8: JPrimitiveProtocol {
    public typealias JWrapperType = JByte

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int8 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallByteMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int8 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticByteMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Int8 {
        JNI.jni.withEnv { $0.GetByteField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetByteField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Int8 {
        JNI.jni.withEnv { $0.GetStaticByteField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticByteField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(b: self)
    }
}

public final class JShort: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Int16
    public static let javaClass = try! JClass(name: "java/lang/Short", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(S)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "shortValue", sig: "()S")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Int16: JPrimitiveProtocol {
    public typealias JWrapperType = JShort

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int16 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallShortMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int16 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticShortMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Int16 {
        JNI.jni.withEnv { $0.GetShortField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetShortField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Int16 {
        JNI.jni.withEnv { $0.GetStaticShortField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticShortField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(s: self)
    }
}

public final class JInteger: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Int32
    public static let javaClass = try! JClass(name: "java/lang/Integer", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(I)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "intValue", sig: "()I")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Int32: JPrimitiveProtocol {
    public typealias JWrapperType = JInteger

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int32 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallIntMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int32 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticIntMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Int32 {
        JNI.jni.withEnv { $0.GetIntField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetIntField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Int32 {
        JNI.jni.withEnv { $0.GetStaticIntField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticIntField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(i: self)
    }
}

public final class JLong: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Int64
    public static let javaClass = try! JClass(name: "java/lang/Long", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(J)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "longValue", sig: "()J")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Int64: JPrimitiveProtocol {
    public typealias JWrapperType = JLong

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int64 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallLongMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int64 {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticLongMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Int64 {
        JNI.jni.withEnv { $0.GetLongField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetLongField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Int64 {
        JNI.jni.withEnv { $0.GetStaticLongField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticLongField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(j: self)
    }
}

extension Int: JPrimitiveProtocol {
    public typealias JWrapperType = JInteger

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int {
        return Int(try Int32.call(method, on: obj, options: options, args: args))
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Int {
        return Int(try Int32.callStatic(method, on: cls, options: options, args: args))
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Int {
        return Int(Int32.load(field, of: obj, options: options))
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        Int32(self).store(field, of: obj, options: options)
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Int {
        return Int(Int32.loadStatic(field, of: cls, options: options))
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        Int32(self).storeStatic(field, of: cls, options: options)
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return Int32(self).toJavaParameter(options: options)
    }

    public static func fromJavaObject(_ ptr: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
        return Int(Int32.fromJavaObject(ptr, options: options))
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        return Int32(self).toJavaObject(options: options)
    }
}

final public class JUByte: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = UInt8
    public static let javaClass = try! JClass(name: "kotlin/UByte", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(B)V")!
    public static let primitiveValueMethodID: JavaMethodID? = nil
    public static let primitiveValueFieldID: JavaFieldID? = javaClass.getFieldID(name: "data", sig: "B")
}

extension UInt8: JPrimitiveProtocol {
    public typealias JWrapperType = JUByte

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt8 {
        try UInt8(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallByteMethodA($1, obj, method.methodID, args) })
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt8 {
        try UInt8(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallStaticByteMethodA($1, cls, method.methodID, args) })
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> UInt8 {
        UInt8(bitPattern: JNI.jni.withEnv { $0.GetByteField($1, obj, field.fieldID) })
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetByteField($1, obj, field.fieldID, Int8(bitPattern: self)) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> UInt8 {
        UInt8(bitPattern: JNI.jni.withEnv { $0.GetStaticByteField($1, cls, field.fieldID) })
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticByteField($1, cls, field.fieldID, Int8(bitPattern: self)) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(b: Int8(bitPattern: self))
    }
}

final public class JUShort: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = UInt16
    public static let javaClass = try! JClass(name: "kotlin/UShort", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(S)V")!
    public static let primitiveValueMethodID: JavaMethodID? = nil
    public static let primitiveValueFieldID: JavaFieldID? = javaClass.getFieldID(name: "data", sig: "S")
}

extension UInt16: JPrimitiveProtocol {
    public typealias JWrapperType = JUShort

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt16 {
        try UInt16(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallShortMethodA($1, obj, method.methodID, args) })
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt16 {
        try UInt16(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallStaticShortMethodA($1, cls, method.methodID, args) })
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> UInt16 {
        UInt16(bitPattern: JNI.jni.withEnv { $0.GetShortField($1, obj, field.fieldID) })
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetShortField($1, obj, field.fieldID, Int16(bitPattern: self)) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> UInt16 {
        UInt16(bitPattern: JNI.jni.withEnv { $0.GetStaticShortField($1, cls, field.fieldID) })
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticShortField($1, cls, field.fieldID, Int16(bitPattern: self)) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(s: Int16(bitPattern: self))
    }
}

public final class JUInt: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = UInt32
    public static let javaClass = try! JClass(name: "kotlin/UInt", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(I)V")!
    public static let primitiveValueMethodID: JavaMethodID? = nil
    public static let primitiveValueFieldID: JavaFieldID? = javaClass.getFieldID(name: "data", sig: "I")
}

extension UInt32: JPrimitiveProtocol {
    public typealias JWrapperType = JUInt

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt32 {
        try UInt32(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallIntMethodA($1, obj, method.methodID, args) })
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt32 {
        try UInt32(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallStaticIntMethodA($1, cls, method.methodID, args) })
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> UInt32 {
        UInt32(bitPattern: JNI.jni.withEnv { $0.GetIntField($1, obj, field.fieldID) })
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetIntField($1, obj, field.fieldID, Int32(bitPattern: self)) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> UInt32 {
        UInt32(bitPattern: JNI.jni.withEnv { $0.GetStaticIntField($1, cls, field.fieldID) })
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticIntField($1, cls, field.fieldID, Int32(bitPattern: self)) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(i: Int32(bitPattern: self))
    }
}

public final class JULong: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = UInt64
    public static let javaClass = try! JClass(name: "kotlin/ULong", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(J)V")!
    public static let primitiveValueMethodID: JavaMethodID? = nil
    public static let primitiveValueFieldID: JavaFieldID? = javaClass.getFieldID(name: "data", sig: "J")
}

extension UInt64: JPrimitiveProtocol {
    public typealias JWrapperType = JULong

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt64 {
        try UInt64(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallLongMethodA($1, obj, method.methodID, args) })
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt64 {
        try UInt64(bitPattern: JNI.jni.withEnvThrowing(options: options) { $0.CallStaticLongMethodA($1, cls, method.methodID, args) })
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> UInt64 {
        UInt64(bitPattern: JNI.jni.withEnv { $0.GetLongField($1, obj, field.fieldID) })
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetLongField($1, obj, field.fieldID, Int64(bitPattern: self)) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> UInt64 {
        UInt64(bitPattern: JNI.jni.withEnv { $0.GetStaticLongField($1, cls, field.fieldID) })
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticLongField($1, cls, field.fieldID, Int64(bitPattern: self)) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(j: Int64(bitPattern: self))
    }
}

extension UInt: JPrimitiveProtocol {
    public typealias JWrapperType = JUInt

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt {
        return UInt(try UInt32.call(method, on: obj, options: options, args: args))
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> UInt {
        return UInt(try UInt32.callStatic(method, on: cls, options: options, args: args))
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> UInt {
        return UInt(UInt32.load(field, of: obj, options: options))
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        UInt32(self).store(field, of: obj, options: options)
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> UInt {
        return UInt(UInt32.loadStatic(field, of: cls, options: options))
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        UInt32(self).storeStatic(field, of: cls, options: options)
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return UInt32(self).toJavaParameter(options: options)
    }

    public static func fromJavaObject(_ ptr: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
        return UInt(UInt32.fromJavaObject(ptr, options: options))
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
        return UInt32(self).toJavaObject(options: options)
    }
}

public final class JFloat: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Float
    public static let javaClass = try! JClass(name: "java/lang/Float", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(F)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "floatValue", sig: "()F")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Float: JPrimitiveProtocol {
    public typealias JWrapperType = JFloat

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Float {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallFloatMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Float {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticFloatMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Float {
        JNI.jni.withEnv { $0.GetFloatField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetFloatField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Float {
        JNI.jni.withEnv { $0.GetStaticFloatField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticFloatField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(f: self)
    }
}

public final class JDouble: JObject, JPrimitiveWrapperProtocol, @unchecked Sendable {
    public typealias JConvertibleType = Double
    public static let javaClass = try! JClass(name: "java/lang/Double", systemClass: true)
    public static let initWithPrimitiveValueMethodID = javaClass.getMethodID(name: "<init>", sig: "(D)V")!
    public static let primitiveValueMethodID: JavaMethodID? = javaClass.getMethodID(name: "doubleValue", sig: "()D")
    public static let primitiveValueFieldID: JavaFieldID? = nil
}

extension Double: JPrimitiveProtocol {
    public typealias JWrapperType = JDouble

    public static func call(_ method: JavaMethodID, on obj: JavaObjectPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Double {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallDoubleMethodA($1, obj, method.methodID, args) }
    }

    public static func callStatic(_ method: JavaMethodID, on cls: JavaClassPointer, options: JConvertibleOptions, args: [JavaParameter]) throws -> Double {
        try JNI.jni.withEnvThrowing(options: options) { $0.CallStaticDoubleMethodA($1, cls, method.methodID, args) }
    }

    public static func load(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) -> Double {
        JNI.jni.withEnv { $0.GetDoubleField($1, obj, field.fieldID) }
    }

    public func store(_ field: JavaFieldID, of obj: JavaObjectPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetDoubleField($1, obj, field.fieldID, self) }
    }

    public static func loadStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) -> Double {
        JNI.jni.withEnv { $0.GetStaticDoubleField($1, cls, field.fieldID) }
    }

    public func storeStatic(_ field: JavaFieldID, of cls: JavaClassPointer, options: JConvertibleOptions) {
        JNI.jni.withEnv { $0.SetStaticDoubleField($1, cls, field.fieldID, self) }
    }

    public func toJavaParameter(options: JConvertibleOptions) -> JavaParameter {
        return JavaParameter(d: self)
    }
}

extension String: JObjectProtocol, JConvertible {
    private static let javaClass = try! JClass(name: "java/lang/String", systemClass: true)

    public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> String {
        JNI.jni.withEnv { jni, env in
            guard let chars = jni.GetStringUTFChars(env, obj, nil) else {
                fatalError("Could not get characters from String")
            }
            defer { jni.ReleaseStringUTFChars(env, obj, chars) }
            if let str = String(validatingUTF8: chars) {
                return str
            }
            // "modified UTF-8" encodes characters outside the BMP as surrogate pairs, which are not valid UTF-8
            let length = jni.GetStringLength(env, obj)
            return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: Int(length)) { buffer in
                jni.GetStringRegion(env, obj, 0, length, buffer.baseAddress)
                return String(decoding: buffer, as: UTF16.self)
            }
        }
    }

    public func toJavaObject(options: JConvertibleOptions) -> JavaString? {
        JNI.jni.withEnv { jni, env in
            // NewStringUTF takes Java's "modified UTF-8", which matches standard UTF-8 unless the string has an embedded NUL or a character outside the BMP.
            // Scanning the contiguous UTF-8 buffer is ~2.7x faster than iterating String.UTF8View; strings without one (e.g. bridged NSStrings) take the UTF-16 path.
            let isModifiedUTF8 = self.utf8.withContiguousStorageIfAvailable { utf8 in
                !utf8.contains { $0 == 0 || $0 >= 0xF0 }
            }
            if isModifiedUTF8 == true {
                return self.withCString { jni.NewStringUTF(env, $0) }
            }

            let chars = self.utf16
            let count = jsize(chars.count)

            // withContiguousStorageIfAvailable often returns nil,
            // so fall back to using a ContiguousArray
            return chars.withContiguousStorageIfAvailable {
                return jni.NewString(env, $0.baseAddress, count)
            } ?? ContiguousArray(chars).withUnsafeBufferPointer {
                return jni.NewString(env, $0.baseAddress, count)
            }
        }
    }
}

// MARK: JVM Management

public struct JVMOptions {
    nonisolated(unsafe) public static let `default` = JVMOptions()

    public var verboseGarbageCollection = false
    public var verboseClassLoading = false
    public var verboseJNI = false
    public var checkJNI = false
    public var classPath: [String] = []
    public var libraryPath: [String] = []
    public var extDirs: [String] = []
    public var compiler: String? = nil // e.g. "none" to disable JIT

    /// Returns the options as an array of strings to use for JVM initialization
    public var vmoptions: [String] {
        var opts: [String] = []
        if verboseGarbageCollection { opts += ["-verbose:gc"] }
        if verboseClassLoading { opts += ["-verbose:class"] }

        if verboseJNI { opts += ["-verbose:jni"] }
        if checkJNI { opts += ["-Xcheck:jni"] }

        if !classPath.isEmpty { opts += ["-Djava.class.path=" + classPath.joined(separator: ":")] }
        if !libraryPath.isEmpty { opts += ["-Djava.library.path=" + libraryPath.joined(separator: ":")] }
        if !extDirs.isEmpty { opts += ["-Djava.ext.dirs=" + extDirs.joined(separator: ":")] }

        if let compiler = compiler { opts += ["-Djava.compiler=" + compiler] }

        return opts
    }
}

#if SWIFT_JAVA_JNI_CORE
extension JNI {
    /// compat that just passes through to `JNI.shared()`
    public static func attachJVM(launch: Bool = false) throws {
        _ = try JNI.shared()
    }
}
#else
extension JNI {
    /// Find the running JVM and sets it as the JNI VM.
    /// If the JNI context is nil (e.g., we are running on macOS rather than Android), starts up an embedded JVM process and sets the JNI context from that.
    /// - Parameter options: the options that will be used when launching the Java VM
    public static func attachJVM(options: JVMOptions = .default, launch: Bool = false) throws {
        if jni != nil {
            return
        }

        // we need to get the host JVM using JNI_GetCreatedJavaVMs, but it is not exported in jni.h,
        // so we need to dlsym it from some library, which has changed over various Android APIs
        // libnativehelper.so added in API 31 (https://github.com/android/ndk/issues/1320) to work around "libart.so" no longer being allowed to load
        // FIXME: this does *not* work on API 29 and 30 specifically, since it is after Android started restricting access to the APIs but before they exposed JNI_GetCreatedJavaVMs publicly
        for libname in [nil, "libnativehelper.so", "libart.so", "libdvm.so"] {
            // Windows TODO: need to use LoadLibraryW (see https://github.com/swiftlang/sourcekit-lsp/blob/main/Sources/SourceKitD/dlopen.swift)
            let lib = dlopen(libname, RTLD_NOW)
            typealias JavaVMPtr = UnsafeMutablePointer<JavaVM?>
            typealias GetCreatedJavaVMs = @convention(c) (_ pvm: UnsafeMutablePointer<JavaVMPtr?>, _ count: Int32, _ num: UnsafeMutablePointer<Int32>) -> jint

            // Windows TODO: need to use GetProcAddress
            guard let getCreatedJavaVMs = dlsym(lib, "JNI_GetCreatedJavaVMs").map({ unsafeBitCast($0, to: (GetCreatedJavaVMs).self) }) else {
                continue
            }

            // check to see if we are already running inside of a VM; if so, return the existing VM
            var runningCount: Int32 = 0
            var jvm: JavaVMPtr?
            if getCreatedJavaVMs(&jvm, 1, &runningCount) == JNI_OK, let jvm = jvm {
                jni = JNI(jvm: jvm)
                return
            } else if !launch {
                throw JVMError(description: "unable to invoke getCreatedJavaVMs for lib: \(libname ?? "")")
            }
        }

        if jni == nil && launch {
            try JNI.launchJavaVM(options: options)
        }

        if jni == nil {
            throw JVMError(description: "No jni pointer was attached, and could not get/create a JVM instance")
        }
    }

    /// Instantiate an embedded Java Virtual Machine.
    /// This is just used in local testing, where a Swift test case needs to be able to call into JNI from a macOS environment
    public static func launchJavaVM(options: JVMOptions = .default) throws {
        if jni != nil {
            return
        }

        let library = try loadLibJava()

        typealias CreateJavaVM = @convention(c) (_ pvm: UnsafeMutablePointer<UnsafeMutablePointer<JavaVM?>?>?, _ penv: UnsafeMutablePointer<UnsafeMutablePointer<JNIEnv?>?>?, _ args: UnsafeMutableRawPointer) -> jint

        guard let JNI_CreateJavaVM_dlsym = dlsym(library, "JNI_CreateJavaVM").map({ unsafeBitCast($0, to: (CreateJavaVM).self) }) else {
            throw JVMError(description: "Unable to dlsym JNI_CreateJavaVM")
        }

        var pvm: UnsafeMutablePointer<JavaVM?>?
        var penv: UnsafeMutablePointer<JNIEnv?>?
        var jargs = JavaVMInitArgs()
        jargs.version = JNI_VERSION_1_6

        let vmopts = options.vmoptions

        let copts = vmopts.map { NullTerminatedCString($0) }
        jargs.nOptions = jint(copts.count)
        let jopts = UnsafeMutablePointer<JavaVMOption>.allocate(capacity: copts.count)
        for (i, copt) in copts.enumerated() {
            jopts[i].optionString = copt.buffer
        }
        jargs.options = jopts

        // we need to manually dlsym(), or else we get: Undefined symbol: _JNI_CreateJavaVM
        //JNI_CreateJavaVM(&pvm, &penv, nil)

        let success: jint = JNI_CreateJavaVM_dlsym(&pvm, &penv, &jargs)

        guard success == JNI_OK, let pvm = pvm else {
            throw JVMError(description: "Could not launch embedded Java virtual machine: \(success)")
        }

        #if os(Android)
        // TODO: need to create JniInvocation::JniInvocation() or else crash with error: "Failed to create JniInvocation instance before using JNI invocation API"
        #endif

        jni = JNI(jvm: pvm)
    }

    /// Finds the loads the local dynamic library that contains the JNI entry point functions
    /// `JNI_GetCreatedJavaVMs` and `JNI_CreateJavaVM`
    private static func loadLibJava() throws -> UnsafeMutableRawPointer {
        #if os(Android)
        for libname in ["libart.so", "libdvm.so", "libnativehelper.so"] {
            // Windows TODO: need to use LoadLibraryW (see https://github.com/swiftlang/sourcekit-lsp/blob/main/Sources/SourceKitD/dlopen.swift)
            // Android error: "Runtime library not loaded"
            if let lib = dlopen(libname, RTLD_NOW) {
                return lib
            }
        }
        #endif

        // if JAVA_HOME is unset, default to the Homebrew installation
        if getenv("JAVA_HOME") == nil {
            if FileManager.default.fileExists(atPath: "/opt/homebrew/opt/java") {
                setenv("JAVA_HOME", "/opt/homebrew/opt/java", 0) // Homebrew ARM location
            } else if FileManager.default.fileExists(atPath: "/usr/local/opt/java") {
                setenv("JAVA_HOME", "/usr/local/opt/java", 0) // Homebrew Intel location
            } else {
                throw JVMError(description: "No JAVA_HOME set, and could not locate default Java installation")
            }
        }
        let JAVA_HOME = getenv("JAVA_HOME")!
        let javaHome = URL(fileURLWithPath: String(validatingUTF8: JAVA_HOME)!)

        let ext: String
        #if os(Windows)
        ext = "dll"
        #elseif canImport(Darwin) // macOS, iOS, etc.
        ext = "dylib"
        #else
        ext = "so"
        #endif

        let libs = [
            URL(fileURLWithPath: "java/lib/server/libjvm.\(ext)", relativeTo: javaHome),
            URL(fileURLWithPath: "jre/lib/server/libjvm.\(ext)", relativeTo: javaHome),
            URL(fileURLWithPath: "lib/server/libjvm.\(ext)", relativeTo: javaHome),
            URL(fileURLWithPath: "lib/libjvm.\(ext)", relativeTo: javaHome),
            URL(fileURLWithPath: "java/libexec/openjdk.jdk/Contents/Home/lib/server/libjvm.\(ext)", relativeTo: javaHome), // Homebrew
        ]

        guard let lib = libs.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw JVMError(description: "Could not find libjvm in: \(libs.map(\.path))")
        }

        // TODO: on macOS, reduce signal interception debugging issues by locating libjsig.dylib and adding it to DYLD_INSERT_LIBRARIES
        guard let dylib = dlopen(lib.path, RTLD_NOW) else {
            if let error = dlerror() {
                throw JVMError(description: "dlopen error: \(String(cString: error))")
            } else {
                throw JVMError(description: "Unknown dlopen error")
            }
        }

        return dylib
    }
}
#endif

final class NullTerminatedCString {
    let length: Int
    let buffer: UnsafePointer<CChar>

    init(_ string: String) {
        (length, buffer) = string.withCString {
            let len = Int(strlen($0) + 1)
            let dst = UnsafePointer(strcpy(UnsafeMutablePointer<CChar>.allocate(capacity: len), $0))
            return (len, dst!)
        }
    }

    deinit {
        buffer.deallocate()
    }
}
