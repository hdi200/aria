// swift-tools-version: 6.1
import PackageDescription

let jniDependency: Target.Dependency
var swiftSettings: [SwiftSetting]

let useSwiftJavaJNICore = Context.environment["SWIFT_JAVA_JNI_CORE"] ?? "0" == "1"

if useSwiftJavaJNICore {
    // use swift-java-jni-core
    jniDependency = .product(name: "SwiftJavaJNICore", package: "swift-java-jni-core")
    swiftSettings = [.define("SWIFT_JAVA_JNI_CORE")]

} else {
    jniDependency = .target(name: "CJNI")
    swiftSettings = []
}

// ARIA PATCH: opt-in release lifetime counters; absent from upload builds.
if Context.environment["ARIA_PERF_DIAGNOSTICS"] == "1" {
    swiftSettings.append(.define("ARIA_PERF_DIAGNOSTICS"))
}

let package = Package(
    name: "swift-jni",
    products: [
        .library(name: "SwiftJNI", type: .dynamic, targets: ["SwiftJNI"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "CJNI"),
        .target(name: "SwiftJNI", dependencies: [
            jniDependency,
        ], swiftSettings: swiftSettings),
        .testTarget(name: "SwiftJNITests", dependencies: [
            "SwiftJNI"
        ], swiftSettings: swiftSettings),
    ]
)

if useSwiftJavaJNICore {
    package.dependencies += [
        .package(url: "https://github.com/swiftlang/swift-java-jni-core.git", from: "0.5.1"),
    ]
}
