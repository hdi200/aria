// swift-tools-version: 6.2
// This is a Skip (https://skip.dev) package.
import Foundation
import PackageDescription

// The shared render core's Android build (scripts/build-render-core.sh, build-engine.sh),
// next to MuseReaderAndroid/ in the repository. Found from this file's path, which Skip
// also builds from a copy inside .build, so look for the MuseReaderAndroid folder.
let manifestPath = #filePath
let repoRoot = manifestPath.range(of: "/MuseReaderAndroid/").map { String(manifestPath[..<$0.lowerBound]) }
    ?? URL(fileURLWithPath: manifestPath).deletingLastPathComponent().appendingPathComponent("../..").standardized.path
let engineLibraryDir = repoRoot + "/build-aria-android-arm64/jniLibs/arm64-v8a"
// ARIA PATCH: exact pinned Skip UI/Fuse UI/JNI sources with local lifecycle fixes.
// Root path dependencies override transitive URLs; see Vendor/*/ARIA_PATCHES.md.
// ARIA PATCH: the separate TEST build selects guarded probes in an ignored copy.
// The ordinary dependency and pinned framework version stay unchanged.
let patchedSkipUI = repoRoot + (Context.environment["ARIA_PHONE_AUDIT"] == "1"
    ? "/MuseReaderAndroid/release-local/focused-ui-vendor/skip-ui"
    : "/MuseReaderAndroid/Aria/Vendor/skip-ui")
// Keep conditional settings separate: a long chain of array '+' expressions
// exceeds SwiftPM's manifest type-check budget when another audit flag is added.
var ariaAuditSettings: [SwiftSetting] = ["ARIA_PERF_DIAGNOSTICS", "ARIA_VIDEO_AUDIT", "ARIA_EDIT_AUDIT", "ARIA_PHONE_AUDIT"]
    .filter { Context.environment[$0] == "1" }.map { .define($0) }
if Context.environment["ARIA_VIDEO_AUDIT"] == "1", Context.environment["ARIA_VIDEO_MAIN_BASELINE"] == "1" {
    ariaAuditSettings.append(.define("ARIA_VIDEO_MAIN_BASELINE"))
}

let package = Package(
    name: "Aria",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AriaSkip", type: .dynamic, targets: ["AriaSkip"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.16"),
        .package(path: repoRoot + "/MuseReaderAndroid/Aria/Vendor/skip-fuse-ui"),
        .package(path: repoRoot + "/MuseReaderAndroid/Aria/Vendor/swift-jni"),
        .package(path: patchedSkipUI)
    ],
    targets: [
        .target(name: "AriaSkip", dependencies: [
            "AriaEngine",
            .product(name: "SwiftJNI", package: "swift-jni"),
            // Android stand-ins for Apple modules the shared iOS files import.
            .target(name: "UIKit", condition: .when(platforms: [.android])),
            .target(name: "CryptoKit", condition: .when(platforms: [.android])),
            .target(name: "UniformTypeIdentifiers", condition: .when(platforms: [.android])),
            .target(name: "Accelerate", condition: .when(platforms: [.android])),
            .target(name: "AVFoundation", condition: .when(platforms: [.android])),
            .target(name: "AudioToolbox", condition: .when(platforms: [.android])),
            .target(name: "StoreKit", condition: .when(platforms: [.android])),
            .target(name: "CoreImage", condition: .when(platforms: [.android])),
            .target(name: "CoreMedia", condition: .when(platforms: [.android])),
            .target(name: "Metal", condition: .when(platforms: [.android])),
            .target(name: "AVKit", condition: .when(platforms: [.android])),
            .target(name: "ImageIO", condition: .when(platforms: [.android])),
            .target(name: "PhotosUI", condition: .when(platforms: [.android])),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui")
        ], exclude: Context.environment["ARIA_PHONE_AUDIT"] == "1" ? [] : ["AndroidPhoneAudit.swift"],
        resources: [.process("Resources")],
        // The iOS app target's Swift settings (Aria.xcodeproj), so shared files build the
        // same way: Swift 5, MainActor by default, Approachable Concurrency.
        swiftSettings: ariaAuditSettings + [
            .swiftLanguageMode(.v5),
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("DisableOutwardActorInference"),
            .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableUpcomingFeature("InferSendableFromCaptures"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            // iOS also enables MemberImportVisibility; SwiftPM's generated resource
            // accessor doesn't build with it, and iOS enforces it for the shared files.
        ],
        plugins: [.plugin(name: "skipstone", package: "skip")]),

        // Android's MuseScoreRenderCoreBridge: Swift over the C++ render core.
        .target(
            name: "AriaEngine",
            dependencies: ["AriaRenderCoreCxx"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                // With a stable interface, modules importing AriaEngine don't load its
                // internal C++ imports, so they build without C++ interop.
                .unsafeFlags(["-enable-library-evolution"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(engineLibraryDir)", "-laria_engine"], .when(platforms: [.android])),
                // The iOS app links the render core itself; this package only runs on Android.
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"], .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .target(name: "AriaRenderCoreCxx"),

        // Android only (see the AriaSkip dependency conditions); Sources/AndroidShims/README.md.
        .target(name: "UIKit", dependencies: [.product(name: "SkipFuseUI", package: "skip-fuse-ui")], path: "Sources/AndroidShims/UIKit"),
        .target(name: "CryptoKit", path: "Sources/AndroidShims/CryptoKit"),
        .target(name: "UniformTypeIdentifiers", path: "Sources/AndroidShims/UniformTypeIdentifiers"),
        .target(name: "Accelerate", path: "Sources/AndroidShims/Accelerate"),
        .target(name: "AVFoundation", dependencies: [
            "AriaEngine",
            .target(name: "UIKit", condition: .when(platforms: [.android])),
            .target(name: "CoreMedia", condition: .when(platforms: [.android])),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui")
        ], path: "Sources/AndroidShims/AVFoundation"),
        .target(name: "CoreImage", dependencies: [
            .target(name: "UIKit", condition: .when(platforms: [.android])),
            .target(name: "Metal", condition: .when(platforms: [.android]))
        ], path: "Sources/AndroidShims/CoreImage"),
        .target(name: "CoreMedia", dependencies: [.target(name: "UIKit", condition: .when(platforms: [.android]))],
                path: "Sources/AndroidShims/CoreMedia"),
        .target(name: "Metal", path: "Sources/AndroidShims/Metal"),
        .target(name: "AVKit", dependencies: [.target(name: "AVFoundation", condition: .when(platforms: [.android]))],
                path: "Sources/AndroidShims/AVKit"),
        .target(name: "ImageIO", dependencies: [
            .target(name: "UIKit", condition: .when(platforms: [.android])),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui")
        ], path: "Sources/AndroidShims/ImageIO"),
        .target(name: "PhotosUI", dependencies: [.product(name: "SkipFuseUI", package: "skip-fuse-ui")],
                path: "Sources/AndroidShims/PhotosUI"),
        .target(name: "AudioToolbox", path: "Sources/AndroidShims/AudioToolbox"),
        .target(name: "StoreKit", dependencies: [.product(name: "SkipFuseUI", package: "skip-fuse-ui")], path: "Sources/AndroidShims/StoreKit"),
    ],
    cxxLanguageStandard: .cxx17
)
