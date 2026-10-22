// Copyright 2023–2026 Skip
@testable import SwiftJNI
import Testing

#if os(Android)
let isAndroid = true
#else
let isAndroid = false
#endif

@Suite(.serialized) struct SwiftJNITests {
    init() throws {
        try JNI.attachJVM(launch: !isAndroid)
    }

    @Test func testSwiftJNI() throws {
        try jniContext {
            let integerClass = try JClass(name: "java/lang/Integer", systemClass: true)

            let integerInit = try #require(integerClass.getMethodID(name: "<init>", sig: "(I)V"))
            let integerInstance = try integerClass.create(ctor: integerInit, options: [], args: [JavaParameter(i: .max)])

            let integerIntValue = try #require(integerClass.getMethodID(name: "intValue", sig: "()I"))
            let i: Int32 = try integerInstance.call(method: integerIntValue, options: [], args: [])

            #expect(i == 2147483647, "Int.MAX_VALUE should be 32-bit")
        }
    }

    // MARK: - Numeric edge cases (32-bit vs 64-bit JVM differences)

    @Test func testLongMinMax() throws {
        // Java long is always 64-bit, but ART and HotSpot may optimize differently
        try jniContext {
            let longClass = try JClass(name: "java/lang/Long", systemClass: true)
            let longInit = try #require(longClass.getMethodID(name: "<init>", sig: "(J)V"))
            let longValue = try #require(longClass.getMethodID(name: "longValue", sig: "()J"))

            let maxObj = try longClass.create(ctor: longInit, options: [], args: [JavaParameter(j: Int64.max)])
            let maxVal: Int64 = try maxObj.call(method: longValue, options: [], args: [])
            #expect(maxVal == Int64.max)

            let minObj = try longClass.create(ctor: longInit, options: [], args: [JavaParameter(j: Int64.min)])
            let minVal: Int64 = try minObj.call(method: longValue, options: [], args: [])
            #expect(minVal == Int64.min)
        }
    }

    @Test func testDoubleSpecialValues() throws {
        // NaN, Infinity handling — ART has historically had quirks with NaN comparisons
        try jniContext {
            let doubleClass = try JClass(name: "java/lang/Double", systemClass: true)
            let doubleInit = try #require(doubleClass.getMethodID(name: "<init>", sig: "(D)V"))
            let doubleValue = try #require(doubleClass.getMethodID(name: "doubleValue", sig: "()D"))
            let isNaN = try #require(doubleClass.getStaticMethodID(name: "isNaN", sig: "(D)Z"))
            let isInfinite = try #require(doubleClass.getStaticMethodID(name: "isInfinite", sig: "(D)Z"))

            // NaN round-trip
            let nanObj = try doubleClass.create(ctor: doubleInit, options: [], args: [JavaParameter(d: Double.nan)])
            let nanVal: Double = try nanObj.call(method: doubleValue, options: [], args: [])
            #expect(nanVal.isNaN)

            // Static method: Double.isNaN(NaN) == true
            let nanCheck: Bool = try doubleClass.callStatic(method: isNaN, options: [], args: [JavaParameter(d: Double.nan)])
            #expect(nanCheck == true)

            // Positive infinity
            let infObj = try doubleClass.create(ctor: doubleInit, options: [], args: [JavaParameter(d: Double.infinity)])
            let infVal: Double = try infObj.call(method: doubleValue, options: [], args: [])
            #expect(infVal == Double.infinity)

            let infCheck: Bool = try doubleClass.callStatic(method: isInfinite, options: [], args: [JavaParameter(d: Double.infinity)])
            #expect(infCheck == true)

            // Negative zero — Java preserves negative zero but equals() treats -0.0 != +0.0
            // (unlike ==) which is a well-known JVM gotcha
            let negZeroObj = try doubleClass.create(ctor: doubleInit, options: [], args: [JavaParameter(d: -0.0)])
            let negZeroVal: Double = try negZeroObj.call(method: doubleValue, options: [], args: [])
            #expect(negZeroVal.isZero)
            #expect(negZeroVal.sign == .minus)
        }
    }

    @Test func testIntegerOverflowArithmetic() throws {
        // Math.addExact throws ArithmeticException on overflow — critical for
        // Skip Lite where Int is 32-bit on Kotlin but 64-bit on Swift
        try jniContext {
            let mathClass = try JClass(name: "java/lang/Math", systemClass: true)
            let addExact = try #require(mathClass.getStaticMethodID(name: "addExact", sig: "(II)I"))

            // Normal addition
            let sum: Int32 = try mathClass.callStatic(method: addExact, options: [], args: [
                JavaParameter(i: 1_000_000),
                JavaParameter(i: 2_000_000),
            ])
            #expect(sum == 3_000_000)

            // Overflow should throw ArithmeticException
            do {
                let _: Int32 = try mathClass.callStatic(method: addExact, options: [.kotlincompat], args: [
                    JavaParameter(i: Int32.max),
                    JavaParameter(i: 1),
                ])
                Issue.record("Expected ArithmeticException for integer overflow")
            } catch {
                // Expected — Java throws ArithmeticException
            }
        }
    }

    // MARK: - String encoding edge cases

    @Test func testStringBMPCharacters() throws {
        // Basic multilingual plane — should work identically everywhere
        jniContext {
            let testStrings = ["hello", "héllo", "日本語", "مرحبا"]
            for str in testStrings {
                let jstr = str.toJavaObject(options: [])
                let roundTripped = String.fromJavaObject(jstr, options: [])
                #expect(roundTripped == str, "Round-trip failed for: \(str)")
            }
        }
    }

    @Test func testStringSupplementaryPlane() throws {
        // Characters outside BMP (U+10000+) use surrogate pairs in Java's UTF-16,
        // which GetStringUTFChars returns as invalid UTF-8 on desktop JVMs, so fromJavaObject falls back to UTF-16.
        try jniContext {
            let stringClass = try JClass(name: "java/lang/String", systemClass: true)
            let lengthMethod = try #require(stringClass.getMethodID(name: "length", sig: "()I"))
            let codePointCount = try #require(stringClass.getMethodID(name: "codePointCount", sig: "(II)I"))

            // "🎵🎶" = 2 code points, 4 UTF-16 code units (each is a surrogate pair)
            let emoji = "🎵🎶"
            let jstr = emoji.toJavaObject(options: [])!
            let utf16Len: Int32 = try jstr.call(method: lengthMethod, options: [], args: [])
            #expect(utf16Len == 4, "Two supplementary characters = 4 UTF-16 code units")

            let cpCount: Int32 = try jstr.call(method: codePointCount, options: [], args: [
                JavaParameter(i: 0), JavaParameter(i: utf16Len),
            ])
            #expect(cpCount == 2, "Should be 2 Unicode code points")

            // Mixed BMP + supplementary: "A🎵B" = 3 code points, 4 UTF-16 code units
            let mixed = "A🎵B"
            let jmixed = mixed.toJavaObject(options: [])!
            let mixedLen: Int32 = try jmixed.call(method: lengthMethod, options: [], args: [])
            #expect(mixedLen == 4) // 'A' + surrogate pair + 'B'

            for str in [emoji, mixed, "Fed 🇺🇸 📉"] {
                #expect(String.fromJavaObject(str.toJavaObject(options: []), options: []) == str, "Round-trip failed for: \(str)")
            }
        }
    }

    @Test func testStringWithEmbeddedNull() throws {
        // Java strings can contain \0. Verify the UTF-16 encoding path preserves it.
        // GetStringUTFChars uses Modified UTF-8 where \0 becomes 0xC0 0x80, so fromJavaObject falls back to UTF-16.
        try jniContext {
            let str = "before\0after"
            let jstr = str.toJavaObject(options: [])!

            let stringClass = try JClass(name: "java/lang/String", systemClass: true)
            let lengthMethod = try #require(stringClass.getMethodID(name: "length", sig: "()I"))
            let jlen: Int32 = try jstr.call(method: lengthMethod, options: [], args: [])
            #expect(jlen == Int32(str.utf16.count))
            #expect(String.fromJavaObject(jstr, options: []) == str)
        }
    }

    // MARK: - Class loading and reflection

    @Test func testSystemClassLoading() throws {
        // System classes must be findable via FindClass (boot class loader)
        try jniContext {
            let classClass = try JClass(name: "java/lang/Class", systemClass: true)
            let getNameMethod = try #require(classClass.getMethodID(name: "getName", sig: "()Ljava/lang/String;"))

            let classes = [
                "java/lang/Object",
                "java/lang/String",
                "java/lang/Class",
                "java/lang/System",
                "java/util/HashMap",
                "java/util/ArrayList",
                "java/io/InputStream",
                "java/lang/Thread",
            ]
            for name in classes {
                let cls = try JClass(name: name, systemClass: true)
                // cls.ptr is a jclass (which is a java.lang.Class instance), so call getName on it
                let javaName: String = try cls.ptr.call(method: getNameMethod, options: [], args: [])
                #expect(javaName == name.replacing("/", with: "."))
            }
        }
    }

    @Test func testClassNotFound() throws {
        // Non-existent class should throw, not crash
        jniContext {
            do {
                let _ = try JClass(name: "com/nonexistent/BogusClass", systemClass: true)
                Issue.record("Expected ClassNotFoundError")
            } catch {
                // Expected
            }
        }
    }

    // MARK: - Object lifecycle and references

    @Test func testGlobalRefSurvivesLocalFrame() throws {
        // Global refs must survive PushLocalFrame/PopLocalFrame — this matters on
        // Android where ART aggressively collects local refs
        try jniContext {
            let stringClass = try JClass(name: "java/lang/String", systemClass: true)
            let classClass = try JClass(name: "java/lang/Class", systemClass: true)
            let globalPtr = stringClass.ptr // JObject stores global refs

            JNI.jni.withEnv { jni, env in
                // Push a local frame, create a local ref, pop — global should survive
                _ = jni.PushLocalFrame(env, 16)
                let localRef = jni.NewLocalRef(env, globalPtr)
                #expect(localRef != nil)
                _ = jni.PopLocalFrame(env, nil) // frees all local refs in frame
            }

            // Global ref should still be valid — verify by calling getName() on the Class object
            let getNameMethod = try #require(classClass.getMethodID(name: "getName", sig: "()Ljava/lang/String;"))
            let name: String = try stringClass.ptr.call(method: getNameMethod, options: [], args: [])
            #expect(name == "java.lang.String")
        }
    }

    @Test func testObjectIdentity() throws {
        // isSameObject should reflect Java object identity, not value equality
        jniContext {
            let s1 = "test".toJavaObject(options: [])!
            let s2 = "test".toJavaObject(options: [])!

            // A ref compared to itself must always be the same
            let selfSame: Bool = JNI.jni.withEnv { jni, env in jni.IsSameObject(env, s1, s1) == 1 }
            #expect(selfSame)

            // null compared to null
            let nullSame: Bool = JNI.jni.withEnv { jni, env in jni.IsSameObject(env, nil, nil) == 1 }
            #expect(nullSame)

            // non-null vs null
            let mixedSame: Bool = JNI.jni.withEnv { jni, env in jni.IsSameObject(env, s1, nil) == 1 }
            #expect(!mixedSame)

            // Two separate NewString calls — identity is JVM-implementation-dependent
            // (string interning varies between HotSpot and ART)
            _ = s2 // used to create a second distinct allocation
        }
    }

    // MARK: - Array operations

    @Test func testByteArrayRoundTrip() throws {
        try jniContext {
            let original: [UInt8] = [0, 1, 127, 128, 255, 0, 42]
            let jarray = original.withUnsafeBytes { buf in
                JNI.jni.newByteArray(buf.baseAddress, size: JavaInt(original.count))
            }
            let arr = try #require(jarray)

            let (ptr, len) = JNI.jni.getByteArrayElements(arr)
            #expect(Int(len) == original.count)

            let retrieved = (0..<Int(len)).map { UInt8(bitPattern: ptr![$0]) }
            JNI.jni.releaseByteArrayElements(arr, elements: ptr, mode: .unpin)
            #expect(retrieved == original)
        }
    }

    @Test func testEmptyByteArray() throws {
        try jniContext {
            let jarray = [UInt8]().withUnsafeBytes { buf in
                JNI.jni.newByteArray(buf.baseAddress, size: 0)
            }
            let arr = try #require(jarray)
            let (_, len) = JNI.jni.getByteArrayElements(arr)
            #expect(len == 0)
        }
    }

    // MARK: - Exception handling

    @Test func testJavaExceptionPropagation() throws {
        // Integer.parseInt with bad input should throw NumberFormatException
        try jniContext {
            let integerClass = try JClass(name: "java/lang/Integer", systemClass: true)
            let parseInt = try #require(integerClass.getStaticMethodID(name: "parseInt", sig: "(Ljava/lang/String;)I"))

            do {
                let _: Int32 = try integerClass.callStatic(method: parseInt, options: [.kotlincompat], args: [
                    "not_a_number".toJavaParameter(options: [])
                ])
                Issue.record("Expected NumberFormatException")
            } catch {
                // Verify we got a meaningful error, not a JVM crash
                let desc = String(describing: error)
                #expect(desc.contains("NumberFormat") || desc.contains("number") || desc.contains("not_a_number"),
                       "Exception should mention the parse failure, got: \(desc)")
            }
        }
    }

    @Test func testExceptionClearRecovers() throws {
        // After catching an exception, subsequent JNI calls should work normally
        try jniContext {
            let integerClass = try JClass(name: "java/lang/Integer", systemClass: true)
            let parseInt = try #require(integerClass.getStaticMethodID(name: "parseInt", sig: "(Ljava/lang/String;)I"))

            // Trigger and catch an exception
            do {
                let _: Int32 = try integerClass.callStatic(method: parseInt, options: [.kotlincompat], args: [
                    "bad".toJavaParameter(options: [])
                ])
            } catch {
                // Expected
            }

            // JNI should still be functional after the exception
            let result: Int32 = try integerClass.callStatic(method: parseInt, options: [], args: [
                "42".toJavaParameter(options: [])
            ])
            #expect(result == 42)
        }
    }

    // MARK: - Collections interop

    @Test func testHashMapOperations() throws {
        // HashMap behavior — important because Android's HashMap iteration order
        // can differ from OpenJDK's in practice
        try jniContext {
            let mapClass = try JClass(name: "java/util/HashMap", systemClass: true)
            let mapInit = try #require(mapClass.getMethodID(name: "<init>", sig: "()V"))
            let put = try #require(mapClass.getMethodID(name: "put", sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"))
            let get = try #require(mapClass.getMethodID(name: "get", sig: "(Ljava/lang/Object;)Ljava/lang/Object;"))
            let size = try #require(mapClass.getMethodID(name: "size", sig: "()I"))
            let containsKey = try #require(mapClass.getMethodID(name: "containsKey", sig: "(Ljava/lang/Object;)Z"))

            let map = try mapClass.create(ctor: mapInit, options: [], args: [])

            // Put entries
            let _: JavaObjectPointer? = try map.call(method: put, options: [], args: [
                "key1".toJavaParameter(options: []),
                "value1".toJavaParameter(options: []),
            ])
            let _: JavaObjectPointer? = try map.call(method: put, options: [], args: [
                "key2".toJavaParameter(options: []),
                "value2".toJavaParameter(options: []),
            ])

            let mapSize: Int32 = try map.call(method: size, options: [], args: [])
            #expect(mapSize == 2)

            // Get entry
            let val: String = try map.call(method: get, options: [], args: [
                "key1".toJavaParameter(options: []),
            ])
            #expect(val == "value1")

            // Missing key returns null
            let missing: String? = try map.call(method: get, options: [], args: [
                "nonexistent".toJavaParameter(options: []),
            ])
            #expect(missing == nil)

            // containsKey
            let has: Bool = try map.call(method: containsKey, options: [], args: [
                "key2".toJavaParameter(options: []),
            ])
            #expect(has == true)
        }
    }

    @Test func testArrayListGrowth() throws {
        // ArrayList — verifies object array creation and indexed access
        try jniContext {
            let listClass = try JClass(name: "java/util/ArrayList", systemClass: true)
            let listInit = try #require(listClass.getMethodID(name: "<init>", sig: "()V"))
            let add = try #require(listClass.getMethodID(name: "add", sig: "(Ljava/lang/Object;)Z"))
            let getAt = try #require(listClass.getMethodID(name: "get", sig: "(I)Ljava/lang/Object;"))
            let size = try #require(listClass.getMethodID(name: "size", sig: "()I"))

            let list = try listClass.create(ctor: listInit, options: [], args: [])

            // Add enough elements to trigger internal array resizing
            let count: Int32 = 50
            for i in 0..<count {
                let _: Bool = try list.call(method: add, options: [], args: [
                    "item-\(i)".toJavaParameter(options: []),
                ])
            }

            let listSize: Int32 = try list.call(method: size, options: [], args: [])
            #expect(listSize == count)

            // Verify first and last elements
            let first: String = try list.call(method: getAt, options: [], args: [JavaParameter(i: 0)])
            #expect(first == "item-0")

            let last: String = try list.call(method: getAt, options: [], args: [JavaParameter(i: count - 1)])
            #expect(last == "item-\(count - 1)")
        }
    }

    // MARK: - System properties (differ between Android and desktop JVMs)

    @Test func testSystemProperties() throws {
        try jniContext {
            let systemClass = try JClass(name: "java/lang/System", systemClass: true)
            let getProperty = try #require(systemClass.getStaticMethodID(name: "getProperty", sig: "(Ljava/lang/String;)Ljava/lang/String;"))

            // file.separator: "/" on all Unix-like JVMs including Android
            let fileSep: String = try systemClass.callStatic(method: getProperty, options: [], args: [
                "file.separator".toJavaParameter(options: []),
            ])
            #expect(fileSep == "/")

            // java.vm.name differs: "Dalvik" on Android, various on desktop
            let vmName: String? = try systemClass.callStatic(method: getProperty, options: [], args: [
                "java.vm.name".toJavaParameter(options: []),
            ])
            if isAndroid {
                #expect(vmName?.contains("Dalvik") == true || vmName?.contains("Art") == true,
                       "Expected Android VM name, got: \(vmName ?? "nil")")
            } else {
                #expect(vmName != nil, "Desktop JVM should report a VM name")
            }
        }
    }

    // MARK: - Threading and jniContext

    @Test func testJniContextFromBackgroundThread() async throws {
        // jniContext must attach/detach native threads — critical on Android where
        // native threads are not automatically attached to ART
        let result: Int32 = try await Task.detached {
            try jniContext {
                let integerClass = try JClass(name: "java/lang/Integer", systemClass: true)
                let parseInt = try #require(integerClass.getStaticMethodID(name: "parseInt", sig: "(Ljava/lang/String;)I"))
                let val: Int32 = try integerClass.callStatic(method: parseInt, options: [], args: [
                    "99".toJavaParameter(options: []),
                ])
                return val
            }
        }.value
        #expect(result == 99)
    }

    @Test func testConcurrentJniAccess() async throws {
        // Multiple concurrent tasks using jniContext — exercises thread attach/detach
        // and verifies no corruption under contention
        try await withThrowingTaskGroup(of: Int32.self) { group in
            for i: Int32 in 0..<10 {
                group.addTask {
                    try jniContext {
                        let integerClass = try JClass(name: "java/lang/Integer", systemClass: true)
                        let valueOf = try #require(integerClass.getStaticMethodID(name: "valueOf", sig: "(I)Ljava/lang/Integer;"))
                        let intValue = try #require(integerClass.getMethodID(name: "intValue", sig: "()I"))

                        let obj: JavaObjectPointer = try integerClass.callStatic(method: valueOf, options: [], args: [JavaParameter(i: i)])
                        let val: Int32 = try obj.call(method: intValue, options: [], args: [])
                        return val
                    }
                }
            }
            var results: Set<Int32> = []
            for try await val in group {
                results.insert(val)
            }
            #expect(results == Set(0..<10))
        }
    }

    // MARK: - Monitor / synchronization

    @Test func testMonitorEnterExit() throws {
        // JNI monitors map to Java synchronized blocks — ART monitors have
        // different internal implementations (thin locks vs fat locks)
        jniContext {
            let obj = "lock_object".toJavaObject(options: [])!
            let enterResult = JNI.jni.monitorEnter(obj: obj)
            #expect(enterResult == 0) // JNI_OK

            // Re-entrant lock should succeed (Java monitors are reentrant)
            let reenterResult = JNI.jni.monitorEnter(obj: obj)
            #expect(reenterResult == 0)

            let exitResult1 = JNI.jni.monitorExit(obj: obj)
            #expect(exitResult1 == 0)

            let exitResult2 = JNI.jni.monitorExit(obj: obj)
            #expect(exitResult2 == 0)
        }
    }

    // MARK: - JNI version and environment

    @Test func testJNIVersion() throws {
        jniContext {
            let version = JNI.jni.version
            // JNI 1.6 = 0x00010006
            #expect(version >= 0x00010006, "JNI version should be at least 1.6")
        }
    }

    // MARK: - Primitive wrapper boxing

    @Test func testBooleanBoxing() throws {
        try jniContext {
            let boolClass = try JClass(name: "java/lang/Boolean", systemClass: true)
            let valueOf = try #require(boolClass.getStaticMethodID(name: "valueOf", sig: "(Z)Ljava/lang/Boolean;"))
            let boolValue = try #require(boolClass.getMethodID(name: "booleanValue", sig: "()Z"))

            let trueObj: JavaObjectPointer = try boolClass.callStatic(method: valueOf, options: [], args: [JavaParameter(z: 1)])
            let trueVal: Bool = try trueObj.call(method: boolValue, options: [], args: [])
            #expect(trueVal == true)

            let falseObj: JavaObjectPointer = try boolClass.callStatic(method: valueOf, options: [], args: [JavaParameter(z: 0)])
            let falseVal: Bool = try falseObj.call(method: boolValue, options: [], args: [])
            #expect(falseVal == false)
        }
    }

    @Test func testFloatPrecision() throws {
        // Float (32-bit) precision — ART and HotSpot must produce identical IEEE 754 results
        try jniContext {
            let floatClass = try JClass(name: "java/lang/Float", systemClass: true)
            let floatInit = try #require(floatClass.getMethodID(name: "<init>", sig: "(F)V"))
            let floatValue = try #require(floatClass.getMethodID(name: "floatValue", sig: "()F"))
            let intBitsToFloat = try #require(floatClass.getStaticMethodID(name: "intBitsToFloat", sig: "(I)F"))

            // Smallest positive float
            let tinyObj = try floatClass.create(ctor: floatInit, options: [], args: [JavaParameter(f: Float.leastNonzeroMagnitude)])
            let tinyVal: Float = try tinyObj.call(method: floatValue, options: [], args: [])
            #expect(tinyVal == Float.leastNonzeroMagnitude)

            // Float from raw bits — exercises exact bit-level representation
            let piVal: Float = try floatClass.callStatic(method: intBitsToFloat, options: [], args: [
                JavaParameter(i: 0x40490FDB) // IEEE 754 representation of ~pi
            ])
            #expect(abs(piVal - Float.pi) < 1e-6)
        }
    }

    // MARK: - String interning (HotSpot vs ART divergence)

    @Test func testStringIntern() throws {
        // String.intern() behavior — HotSpot interns to a PermGen/Metaspace pool,
        // ART uses a different interning mechanism. Both must return the same
        // object for equal interned strings per the JLS.
        try jniContext {
            let stringClass = try JClass(name: "java/lang/String", systemClass: true)
            let intern = try #require(stringClass.getMethodID(name: "intern", sig: "()Ljava/lang/String;"))

            let s1 = "intern_test_xyz".toJavaObject(options: [])!
            let s2 = "intern_test_xyz".toJavaObject(options: [])!

            let interned1: JavaObjectPointer = try s1.call(method: intern, options: [], args: [])
            let interned2: JavaObjectPointer = try s2.call(method: intern, options: [], args: [])

            // Interned strings with same content must be the same object
            let same: Bool = JNI.jni.withEnv { jni, env in jni.IsSameObject(env, interned1, interned2) == 1 }
            #expect(same, "Interned strings with same content should be identical objects")
        }
    }

    // MARK: - Regex (Android uses ICU, desktop uses java.util.regex)

    @Test func testRegexEngine() throws {
        // Android's Pattern implementation uses ICU under the hood, which can have
        // subtle differences in Unicode category matching compared to OpenJDK
        try jniContext {
            let patternClass = try JClass(name: "java/util/regex/Pattern", systemClass: true)
            let compile = try #require(patternClass.getStaticMethodID(name: "compile", sig: "(Ljava/lang/String;)Ljava/util/regex/Pattern;"))
            let matcher = try #require(patternClass.getMethodID(name: "matcher", sig: "(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;"))

            let matcherClass = try JClass(name: "java/util/regex/Matcher", systemClass: true)
            let matches = try #require(matcherClass.getMethodID(name: "matches", sig: "()Z"))
            let find = try #require(matcherClass.getMethodID(name: "find", sig: "()Z"))

            // Basic pattern
            let pattern: JavaObjectPointer = try patternClass.callStatic(method: compile, options: [], args: [
                "\\d+".toJavaParameter(options: []),
            ])
            let m: JavaObjectPointer = try pattern.call(method: matcher, options: [], args: [
                ("12345" as String).toJavaParameter(options: []),
            ])
            let fullMatch: Bool = try m.call(method: matches, options: [], args: [])
            #expect(fullMatch)

            // Unicode letter matching — \p{L} should match across scripts
            let uniPattern: JavaObjectPointer = try patternClass.callStatic(method: compile, options: [], args: [
                "\\p{L}+".toJavaParameter(options: []),
            ])
            let uniMatcher: JavaObjectPointer = try uniPattern.call(method: matcher, options: [], args: [
                ("日本語".toJavaParameter(options: [])),
            ])
            let uniMatch: Bool = try uniMatcher.call(method: matches, options: [], args: [])
            #expect(uniMatch, "\\p{L} should match CJK characters on both ART and HotSpot")

            // Emoji — \p{Emoji} is supported on newer JVMs but may behave differently
            // Just test that find() works with a mixed string (non-crashing is the main assertion)
            let mixedPattern: JavaObjectPointer = try patternClass.callStatic(method: compile, options: [], args: [
                "[a-z]+".toJavaParameter(options: []),
            ])
            let mixedMatcher: JavaObjectPointer = try mixedPattern.call(method: matcher, options: [], args: [
                "🎵hello🎶".toJavaParameter(options: []),
            ])
            let found: Bool = try mixedMatcher.call(method: find, options: [], args: [])
            #expect(found, "Should find 'hello' in emoji-surrounded string")
        }
    }

    // MARK: - Charset encoding (Android defaults can differ)

    @Test func testCharsetDefaultEncoding() throws {
        // Android historically defaulted to UTF-8, while older desktop JVMs used
        // platform-specific encodings. Modern JDK 18+ also defaults to UTF-8.
        try jniContext {
            let charsetClass = try JClass(name: "java/nio/charset/Charset", systemClass: true)
            let defaultCharset = try #require(charsetClass.getStaticMethodID(name: "defaultCharset", sig: "()Ljava/nio/charset/Charset;"))
            let charsetName = try #require(charsetClass.getMethodID(name: "name", sig: "()Ljava/lang/String;"))

            let cs: JavaObjectPointer = try charsetClass.callStatic(method: defaultCharset, options: [], args: [])
            let name: String = try cs.call(method: charsetName, options: [], args: [])

            if isAndroid {
                #expect(name == "UTF-8", "Android should default to UTF-8")
            }
            // On desktop, just verify it returns a valid charset name
            #expect(!name.isEmpty)
        }
    }
}
