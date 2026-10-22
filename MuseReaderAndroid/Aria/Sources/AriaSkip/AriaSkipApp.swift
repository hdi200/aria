import Foundation
import SkipFuse
import SwiftUI

/// A logger for the AriaSkip module.
let logger: Logger = Logger(subsystem: "com.hdi200.ariascore", category: "AriaSkip")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct AriaSkipRootView : View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        // The iOS app's root view (ContentView.swift), set up as MuseReaderiOSApp does.
        Group {
            #if os(Android) && ARIA_PHONE_AUDIT
            AndroidPhoneAuditRootView()
            #else
            ContentView()
            #endif
        }
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
            #if os(Android)
            // The iOS views give text fields their own padding and height (iOS's plain
            // field has none); Compose's fields add 16 dp, which clipped the text.
            .textFieldContentPadding(top: 4, leading: 8, bottom: 4, trailing: 8)
            #endif
            .task {
                #if os(Android)
                // Start Qt and the engine early, off the main thread: the first score opens
                // sooner, and Swift's print output reaches the Android log from here on.
                Task.detached(priority: .utility) {
                    aria_startEngineInBackground()
                    #if ARIA_PERF_DIAGNOSTICS
                    await AndroidPerformanceDiagnostics.start()
                    #endif
                }
                #endif
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class AriaSkipAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = AriaSkipAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
