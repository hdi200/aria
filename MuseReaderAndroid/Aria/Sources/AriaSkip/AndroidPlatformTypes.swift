// Android versions of platform types the shared iOS code uses.

#if os(Android)
import Dispatch
import Foundation
import SwiftUI

// Skip's SwiftUI has its own CGFloat/CGPoint/CGSize/CGRect, distinct from Foundation's on
// Android. Shared code must use the same ones as the views; module-level names take
// precedence over imported ones.
typealias CGFloat = SkipSwiftUI.CGFloat
typealias CGPoint = SkipSwiftUI.CGPoint
typealias CGSize = SkipSwiftUI.CGSize
typealias CGRect = SkipSwiftUI.CGRect

/// iOS 17's DispatchSerialQueue: a serial queue that is also an actor executor
/// (RenderCoreWorkGate, LiveScoreRenderSession). Android's Dispatch doesn't have it.
nonisolated final class DispatchSerialQueue: SerialExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label)
    }

    func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) {
        queue.setSpecific(key: key, value: value)
    }

    func sync<T>(execute work: () throws -> T) rethrows -> T {
        try queue.sync(execute: work)
    }

    func async(execute work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async {
            unownedJob.runSynchronously(on: executor)
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
/// Apple's file coordination (iCloud/Files providers). Android apps get their own copy of a
/// picked file, so there is nothing to coordinate: the accessor runs on the same URL.
nonisolated final class NSFileCoordinator {
    struct ReadingOptions: OptionSet, Sendable {
        let rawValue: UInt
    }

    struct WritingOptions: OptionSet, Sendable {
        let rawValue: UInt
        static let forReplacing = WritingOptions(rawValue: 1 << 3)
    }

    init() {}

    func coordinate(readingItemAt url: URL,
                    options: ReadingOptions = [],
                    error: UnsafeMutablePointer<NSError?>?,
                    byAccessor reader: (URL) -> Void) {
        reader(url)
    }

    func coordinate(writingItemAt url: URL,
                    options: WritingOptions = [],
                    error: UnsafeMutablePointer<NSError?>?,
                    byAccessor writer: (URL) -> Void) {
        writer(url)
    }
}

/// Security-scoped URLs and bookmarks are Apple sandbox features. Android files the app can
/// reach need no scope; bookmarks (only kept for scores opened before the managed library)
/// can't be resolved.
extension URL {
    struct BookmarkResolutionOptions: OptionSet, Sendable {
        let rawValue: UInt
    }

    func startAccessingSecurityScopedResource() -> Bool {
        false
    }

    func stopAccessingSecurityScopedResource() {}

    init(resolvingBookmarkData data: Data,
         options: BookmarkResolutionOptions = [],
         relativeTo url: URL? = nil,
         bookmarkDataIsStale isStale: inout Bool) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }
}
#endif

#if os(Android)
extension UIImage {
    /// Skip's init(data:scale:) has a default scale, so iOS code's `UIImage.init(data:)`
    /// function references don't find it.
    convenience init?(data: Data) {
        self.init(data: data, scale: 1)
        AriaImageSources.remember(data, for: self)
    }
}
#endif

#if os(Android)
extension CGSize {
    /// CoreGraphics has integer initializers; Skip's CGSize only takes CGFloat.
    init(width: Int, height: Int) {
        self.init(width: CGFloat(width), height: CGFloat(height))
    }
}
#endif

#if os(Android)
/// Darwin's math has Float overloads; Android's only takes Double.
func log10(_ value: Float) -> Float {
    Float(Foundation.log10(Double(value)))
}

/// AVFoundation's aspect-fit rectangle.
func AVMakeRect(aspectRatio: CGSize, insideRect boundingRect: CGRect) -> CGRect {
    guard aspectRatio.width > 0, aspectRatio.height > 0 else { return boundingRect }
    let scale = min(boundingRect.width / aspectRatio.width, boundingRect.height / aspectRatio.height)
    let size = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
    return CGRect(x: boundingRect.midX - size.width / 2, y: boundingRect.midY - size.height / 2,
                  width: size.width, height: size.height)
}
#endif
