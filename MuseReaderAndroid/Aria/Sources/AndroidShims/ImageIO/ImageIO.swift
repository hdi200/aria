// Android stand-in for the ImageIO the video export sheet uses: checking that a chosen
// photo decodes, and downsampled thumbnails (decoded by AriaGraphics.kt, EXIF rotation
// applied).
#if os(Android)
@_exported import Foundation
import SkipFuse
import UIKit

public let kCGImageSourceCreateThumbnailFromImageAlways = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceCreateThumbnailWithTransform = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceThumbnailMaxPixelSize = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageSourceShouldCacheImmediately = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceShouldCache = "kCGImageSourceShouldCache"

public final class CGImageSource: @unchecked Sendable {
    let data: Data
    let count: Int

    init(data: Data, count: Int) {
        self.data = data
        self.count = count
    }
}

/// Nil unless the data is an image Android can decode.
public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? {
    let decodes: Bool = (try? AriaGraphicsBridge.object?.canDecode(data)) ?? false
    return decodes ? CGImageSource(data: data, count: 1) : nil
}

public func CGImageSourceGetCount(_ source: CGImageSource) -> Int {
    source.count
}

public func CGImageSourceCreateThumbnailAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard index == 0 else { return nil }
    let maximum = options?[kCGImageSourceThumbnailMaxPixelSize] as? Int ?? 0
    let id: Int = (try? AriaGraphicsBridge.object?.decodeThumbnail(source.data, maximum)) ?? 0
    guard id != 0 else { return nil }
    let size = AriaGraphicsBridge.size(id)
    return CGImage(id: id, width: size.width, height: size.height)
}
#endif
