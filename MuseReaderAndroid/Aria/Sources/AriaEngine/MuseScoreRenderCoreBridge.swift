// Android's MuseScoreRenderCoreBridge (iOS: MuseReaderiOS/MuseReaderiOS/Bridge).

@_implementationOnly import AriaRenderCoreCxx
@_implementationOnly import CxxStdlib
import Foundation

// Android only: the iOS app has its own Objective-C++ bridge.

open class MuseScoreRenderCoreBridge: NSObject, @unchecked Sendable {
    public override init() {}

    /// Starts the engine. iOS creates Qt's application on the main thread, whose run loop
    /// then serves it; Android gives Qt its own thread with Qt's event loop.
    open class func initializeRenderRuntimeIfNeeded() {
        aria.startEngine()
    }

    open func openSession(at url: URL) throws -> MSRRenderSession {
        aria.startEngine()
        var message = std.string()
        guard let session = aria.openSession(std.string(url.path), &message) else {
            let text = makeString(message)
            throw bridgeError(.renderCoreFailure, text.isEmpty ? "The MuseScore render core failed to open this score." : text)
        }
        return MSRRenderSession(session: OpaquePointer(session),
                                totalPageCount: Int(session.pointee.totalPageCount()),
                                supportsPlayback: session.pointee.supportsPlayback(),
                                supportsEditing: session.pointee.supportsEditing())
    }

    open func renderDocument(at url: URL, dpi: Int) throws -> MSRRenderedDocument {
        let session = try openSession(at: url)
        var pages: [MSRRenderedPage] = []
        for pageIndex in 0..<session.totalPageCount {
            pages.append(try session.renderPage(index: pageIndex, dpi: dpi))
        }
        return MSRRenderedDocument(totalPageCount: session.totalPageCount, pages: pages)
    }
}

/// MuseScore Studio's default reverb (the "Muse Reverb" aux channel). Feed it the
/// reverb send in playback order; it replaces the samples with the wet signal.
open class MSRPlaybackReverb: NSObject, @unchecked Sendable {
    // An msr::render::PlaybackReverb, owned (see aria::makeReverb).
    private let reverb: UnsafeMutableRawPointer

    public init(sampleRate: Double) {
        reverb = aria.makeReverb(sampleRate)
    }

    deinit {
        aria.destroyReverb(reverb)
    }

    open func processInterleavedStereo(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        aria.processReverb(reverb, samples, Int32(frameCount))
    }

    open func reset() {
        aria.resetReverb(reverb)
    }
}

