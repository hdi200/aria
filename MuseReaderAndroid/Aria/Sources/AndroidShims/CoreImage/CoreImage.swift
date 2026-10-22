// Android stand-in for the Core Image the video export uses (ScoreVideoPianoPainter):
// images as recipes of crops, transforms, blurs and compositing, drawn by Kotlin
// (AriaImageRecipe in AriaGraphics.kt) when a context renders them. Core Image
// coordinates are y up, as on iOS.
#if os(Android)
@_exported import Foundation
import Metal
import UIKit

// Foundation has its own geometry types; the shared code uses Skip's (the UIKit shim's).
public typealias CGFloat = UIKit.CGFloat
public typealias CGRect = UIKit.CGRect
public typealias CGAffineTransform = UIKit.CGAffineTransform

public struct CIImageOption: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let colorSpace = CIImageOption(rawValue: "kCIImageColorSpace")
}

public struct CIContextOption: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let workingColorSpace = CIContextOption(rawValue: "kCIContextWorkingColorSpace")
    public static let outputColorSpace = CIContextOption(rawValue: "kCIContextOutputColorSpace")
    public static let cacheIntermediates = CIContextOption(rawValue: "kCIContextCacheIntermediates")
}

public struct CIFormat: Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let BGRA8 = CIFormat(rawValue: 1)
    public static let RGBA8 = CIFormat(rawValue: 2)
}

public let kCIInputBackgroundImageKey = "inputBackgroundImage"
public let kCIInputImageKey = "inputImage"

public final class CIColor: @unchecked Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public convenience init(color: UIColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    public static let clear = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
}

public final class CIVector: @unchecked Sendable {
    let values: [CGFloat]

    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) {
        values = [x, y, z, w]
    }
}

public final class CIImage: @unchecked Sendable {
    fileprivate indirect enum Recipe {
        case image(CGImage)
        case color(CIColor)
        case crop(CGRect, Recipe)
        case transform(CGAffineTransform, Recipe)
        case alpha(CGFloat, Recipe)
        case over(Recipe, Recipe)
        case add(Recipe, Recipe)
        case blur(CGFloat, Recipe)
        case clamp(Recipe)
    }

    fileprivate let recipe: Recipe
    public let extent: CGRect

    fileprivate init(_ recipe: Recipe, extent: CGRect) {
        self.recipe = recipe
        self.extent = extent
    }

    public convenience init(cgImage: CGImage, options: [CIImageOption: Any]? = nil) {
        self.init(.image(cgImage), extent: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    public convenience init(color: CIColor) {
        self.init(.color(color), extent: .infinite)
    }

    public func cropped(to rect: CGRect) -> CIImage {
        CIImage(.crop(rect, recipe), extent: extent.intersection(rect))
    }

    public func transformed(by transform: CGAffineTransform) -> CIImage {
        CIImage(.transform(transform, recipe), extent: extent.isInfinite ? extent : extent.applying(transform))
    }

    public func composited(over background: CIImage) -> CIImage {
        CIImage(.over(recipe, background.recipe), extent: extent.union(background.extent))
    }

    public func applyingGaussianBlur(sigma: Double) -> CIImage {
        CIImage(.blur(CGFloat(sigma), recipe), extent: extent.isInfinite ? extent : extent.insetBy(dx: -3 * sigma, dy: -3 * sigma))
    }

    public func clampedToExtent() -> CIImage {
        CIImage(.clamp(recipe), extent: .infinite)
    }

    /// The filters the shared code uses: CIColorMatrix scaling alpha (inputAVector), and
    /// CIAdditionCompositing.
    public func applyingFilter(_ filterName: String, parameters: [String: Any]) -> CIImage {
        switch filterName {
        case "CIColorMatrix":
            let amount = (parameters["inputAVector"] as? CIVector)?.values[3] ?? 1
            return CIImage(.alpha(amount, recipe), extent: extent)
        case "CIAdditionCompositing":
            guard let background = parameters[kCIInputBackgroundImageKey] as? CIImage else { return self }
            return CIImage(.add(recipe, background.recipe), extent: extent.union(background.extent))
        default:
            return self
        }
    }

    /// The recipe as AriaImageRecipe reads it, and the images it draws.
    var encoded: (text: String, images: [CGImage]) {
        var parts: [String] = []
        var images: [CGImage] = []
        func write(_ recipe: Recipe) {
            switch recipe {
            case .image(let image):
                images.append(image)
                parts.append("I \(image.id) \(image.width) \(image.height)")
            case .color(let color):
                parts.append("C \(color.red) \(color.green) \(color.blue) \(color.alpha)")
            case .crop(let rect, let child):
                parts.append("K \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)")
                write(child)
            case .transform(let t, let child):
                parts.append("T \(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty)")
                write(child)
            case .alpha(let amount, let child):
                parts.append("A \(amount)")
                write(child)
            case .over(let top, let bottom):
                parts.append("O")
                write(top)
                write(bottom)
            case .add(let top, let bottom):
                parts.append("D")
                write(top)
                write(bottom)
            case .blur(let sigma, let child):
                parts.append("B \(sigma)")
                write(child)
            case .clamp(let child):
                parts.append("E")
                write(child)
            }
        }
        write(recipe)
        return (parts.joined(separator: " "), images)
    }
}

public final class CIContext: @unchecked Sendable {
    public init(mtlDevice device: any MTLDevice, options: [CIContextOption: Any]? = nil) {}

    public init(options: [CIContextOption: Any]? = nil) {}

    /// Replaces the buffer's pixels with the image's, from (0, 0) at the bottom-left.
    public func render(_ image: CIImage, to buffer: CVPixelBuffer, bounds: CGRect, colorSpace: CGColorSpace?) {
        let encoded = image.encoded
        try? AriaGraphicsBridge.object?.ciRender(buffer.bitmapID, encoded.text) as Void?
        withExtendedLifetime(encoded.images) {}
    }

    public func createCGImage(_ image: CIImage, from rect: CGRect, format: CIFormat, colorSpace: CGColorSpace?) -> CGImage? {
        let width = Int(rect.width.rounded())
        let height = Int(rect.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let encoded = image.encoded
        let id: Int = (try? AriaGraphicsBridge.object?.ciCreate(encoded.text, Double(rect.minX), Double(rect.minY), width, height)) ?? 0
        withExtendedLifetime(encoded.images) {}
        guard id != 0 else { return nil }
        return CGImage(id: id, width: width, height: height)
    }

    public func createCGImage(_ image: CIImage, from rect: CGRect) -> CGImage? {
        createCGImage(image, from: rect, format: .BGRA8, colorSpace: nil)
    }
}
#endif
