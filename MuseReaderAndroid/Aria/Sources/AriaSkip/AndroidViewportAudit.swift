// Small counters for the matched local viewport/raster experiment only.
#if ARIA_EDIT_AUDIT
import Foundation
import SwiftUI

@MainActor
enum AndroidViewportAudit {
    private final class ImageRecord {
        weak var image: UIImage?
        let bytes: Int
        init(_ image: UIImage) {
            self.image = image
            bytes = Int(image.size.width * image.size.height) * 4
        }
    }
    private static var images: [ImageRecord] = []
    private static var requests = 0
    private static var publications = 0

    static func request() { requests += 1 }
    static func published() { publications += 1 }
    static func page(_ image: UIImage, scale: CGFloat) {
        images.removeAll { $0.image == nil }
        images.append(ImageRecord(image))
        print("ARIA_PAGE_RASTER width=\(Int(image.size.width)) height=\(Int(image.size.height)) bytes=\(images.last!.bytes) scale=\(scale) liveSwiftImages=\(images.count) liveSwiftBytes=\(images.reduce(0) { $0 + $1.bytes })")
    }
    static func reportSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            images.removeAll { $0.image == nil }
            print("ARIA_VIEWPORT requests=\(requests) publications=\(publications) liveSwiftImages=\(images.count) liveSwiftBytes=\(images.reduce(0) { $0 + $1.bytes })")
        }
    }
}
#endif
