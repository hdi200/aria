// Android stand-in for the Core Graphics, Core Video and UIKit drawing the video export
// uses (ScoreVideoExporter, ScoreVideoPianoPainter): bitmap contexts, images, paths,
// gradients, PDF pages, pixel buffers, fonts and text. Bitmaps live in Kotlin
// (AriaGraphics.kt); a context records its drawing as commands and sends them in batches.
//
// Behaves like Core Graphics where the shared code depends on it: a context's user space
// is y up from the bottom-left until UIKit's flip is applied (UIGraphicsImageRenderer does),
// draw(_:in:) puts an image's first row at the rect's maxY, and `data` exposes the
// pixels (gray, or BGRA premultiplied) for reading and writing.

import Foundation
import SkipFuse
import SwiftUI

public typealias CGPoint = SkipSwiftUI.CGPoint
public typealias CGSize = SkipSwiftUI.CGSize
public typealias CGAffineTransform = SkipSwiftUI.CGAffineTransform

// Core Foundation types appear in the shared code only as casts and nil allocators.
public typealias CFArray = [Any]
public typealias CFDictionary = [String: Any]
public typealias CFData = Data
public typealias CFString = String
public typealias CFAllocator = AnyObject
nonisolated(unsafe) public let kCFAllocatorDefault: CFAllocator? = nil

package enum AriaGraphicsBridge {
    nonisolated(unsafe) package static let object: AnyDynamicObject? = try? AnyDynamicObject(className: "aria.skip.AriaGraphics")

    package static func createBitmap(width: Int, height: Int) -> Int {
        (try? object?.createBitmap(width, height)) ?? 0
    }

    package static func release(_ id: Int) {
        try? object?.release(id) as Void?
    }

    package static func copy(_ id: Int) -> Int {
        (try? object?.copy(id)) ?? 0
    }

    package static func decode(_ data: Data) -> Int {
        (try? object?.decode(data)) ?? 0
    }

    package static func png(_ id: Int) -> Data? {
        try? object?.png(id)
    }

    package static func size(_ id: Int) -> (width: Int, height: Int) {
        let width: Int = (try? object?.width(id)) ?? 0
        let height: Int = (try? object?.height(id)) ?? 0
        return (width, height)
    }
}

// MARK: - Colors and color spaces

public final class CGColor: @unchecked Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var components: [CGFloat]? { [red, green, blue, alpha] }

    var command: String { "\(red) \(green) \(blue) \(alpha)" }
}

public extension UIColor {
    // Skip's UIColor leaves these out.
    static var black: UIColor { UIColor(red: 0, green: 0, blue: 0, alpha: 1) }
    static var white: UIColor { UIColor(red: 1, green: 1, blue: 1, alpha: 1) }
    static var clear: UIColor { UIColor(red: 0, green: 0, blue: 0, alpha: 0) }
    static var gray: UIColor { UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1) }
    static var darkGray: UIColor { UIColor(red: 1.0 / 3, green: 1.0 / 3, blue: 1.0 / 3, alpha: 1) }
    static var lightGray: UIColor { UIColor(red: 2.0 / 3, green: 2.0 / 3, blue: 2.0 / 3, alpha: 1) }

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }

    convenience init(white: CGFloat, alpha: CGFloat) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?,
                blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        red?.pointee = self.red
        green?.pointee = self.green
        blue?.pointee = self.blue
        alpha?.pointee = self.alpha
        return true
    }

    func setFill() {
        UIGraphicsGetCurrentContext()?.setFillColor(cgColor)
    }

    func setStroke() {
        UIGraphicsGetCurrentContext()?.setStrokeColor(cgColor)
    }
}

public final class CGColorSpace: @unchecked Sendable {
    public static let sRGB: CFString = "kCGColorSpaceSRGB"
    public static let genericGrayGamma2_2: CFString = "kCGColorSpaceGenericGrayGamma2_2"
    let isGray: Bool

    init(gray: Bool) {
        isGray = gray
    }

    public convenience init?(name: CFString) {
        self.init(gray: name.localizedCaseInsensitiveContains("gray"))
    }
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace(gray: false) }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(gray: true) }

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0
    case premultipliedLast = 1
    case premultipliedFirst = 2
    case last = 3
    case first = 4
    case noneSkipLast = 5
    case noneSkipFirst = 6
    case alphaOnly = 7
}

public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
}

public enum CGInterpolationQuality: Int32, Sendable {
    case `default` = 0
    case none = 1
    case low = 2
    case medium = 4
    case high = 3
}

public enum CGLineCap: Int32, Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 2)
}

// MARK: - Images, gradients and paths

/// A bitmap held by AriaGraphics.kt.
public final class CGImage: @unchecked Sendable {
    package let id: Int
    public let width: Int
    public let height: Int

    package init(id: Int, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }

    /// Decodes PNG or JPEG data.
    convenience init?(encoded data: Data) {
        let id = AriaGraphicsBridge.decode(data)
        guard id != 0 else { return nil }
        let size = AriaGraphicsBridge.size(id)
        self.init(id: id, width: size.width, height: size.height)
    }

    deinit {
        AriaGraphicsBridge.release(id)
    }

    package var pngData: Data? { AriaGraphicsBridge.png(id) }
}

public final class CGGradient: @unchecked Sendable {
    let stops: [(color: CGColor, location: CGFloat)]

    public init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: [CGFloat]?) {
        let colors = colors.compactMap { $0 as? CGColor }
        guard colors.count >= 1 else { return nil }
        let locations = locations ?? colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        stops = zip(colors, locations).map { ($0, $1) }
    }

    var command: String {
        "\(stops.count) " + stops.map { "\($0.color.command) \($0.location)" }.joined(separator: " ")
    }
}

public final class CGPath: @unchecked Sendable {
    let commands: [String]
    public let boundingBoxOfPath: CGRect

    init(commands: [String], bounds: CGRect) {
        self.commands = commands
        boundingBoxOfPath = bounds
    }
}

public struct UIRectCorner: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let topLeft = UIRectCorner(rawValue: 1)
    public static let topRight = UIRectCorner(rawValue: 2)
    public static let bottomLeft = UIRectCorner(rawValue: 4)
    public static let bottomRight = UIRectCorner(rawValue: 8)
    public static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

public final class UIBezierPath: @unchecked Sendable {
    public let cgPath: CGPath
    public var lineWidth: CGFloat = 1

    /// Corner names are UIKit's: top is minY.
    public init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        let radius = max(0, min(cornerRadii.width, rect.width / 2, rect.height / 2))
        func corner(_ name: UIRectCorner) -> CGFloat { corners.contains(name) ? radius : 0 }
        cgPath = CGPath(commands: ["pathRound \(rect.minX) \(rect.minY) \(rect.width) \(rect.height) \(corner(.topLeft)) \(corner(.topRight)) \(corner(.bottomRight)) \(corner(.bottomLeft))"],
                        bounds: rect)
    }

    public convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        self.init(roundedRect: rect, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: cornerRadius, height: cornerRadius))
    }

    public convenience init(rect: CGRect) {
        self.init(roundedRect: rect, cornerRadius: 0)
    }

    public init(ovalIn rect: CGRect) {
        cgPath = CGPath(commands: ["pathEllipse \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)"], bounds: rect)
    }

    public func fill() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.addPath(cgPath)
        context.fillPath()
    }

    public func stroke() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.addPath(cgPath)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - PDF pages

public final class CGDataProvider: @unchecked Sendable {
    let data: Data

    public init?(data: CFData) {
        guard !data.isEmpty else { return nil }
        self.data = data
    }
}

public enum CGPDFBox: Int32, Sendable {
    case mediaBox = 0
    case cropBox = 1
    case bleedBox = 2
    case trimBox = 3
    case artBox = 4
}

public final class CGPDFDocument: @unchecked Sendable {
    let id: Int

    public init?(_ provider: CGDataProvider) {
        let id: Int = (try? AriaGraphicsBridge.object?.openPdf(provider.data)) ?? 0
        guard id != 0 else { return nil }
        self.id = id
    }

    deinit {
        try? AriaGraphicsBridge.object?.closePdf(id) as Void?
    }

    /// Pages count from 1, as in Core Graphics.
    public func page(at pageNumber: Int) -> CGPDFPage? {
        let size: String = (try? AriaGraphicsBridge.object?.pdfPageSize(id, pageNumber - 1)) ?? ""
        let parts = size.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPDFPage(document: self, index: pageNumber - 1, size: CGSize(width: parts[0], height: parts[1]))
    }
}

public final class CGPDFPage: @unchecked Sendable {
    let document: CGPDFDocument
    let index: Int
    let size: CGSize

    init(document: CGPDFDocument, index: Int, size: CGSize) {
        self.document = document
        self.index = index
        self.size = size
    }

    public func getBoxRect(_ box: CGPDFBox) -> CGRect {
        CGRect(origin: .zero, size: size)
    }
}

// MARK: - Bitmap contexts

public final class CGContext: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public var interpolationQuality: CGInterpolationQuality = .default
    let contextID: Int
    let bitmapID: Int
    private let ownsBitmap: Bool
    private let isGray: Bool
    private let pixelBuffer: CVPixelBuffer?
    private var pending: [String] = []
    /// Images and pages the pending commands draw, kept until they are sent.
    private var pendingObjects: [AnyObject] = []
    private var exposed: UnsafeMutableRawPointer?

    /// `data` is nil (the context owns its pixels) or a pixel buffer's base address.
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int,
                 bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {
        guard width > 0, height > 0, let graphics = AriaGraphicsBridge.object else { return nil }
        let bitmapID: Int
        if let data {
            guard let buffer = CVPixelBuffer.registered(data) else { return nil }
            pixelBuffer = buffer
            bitmapID = buffer.bitmapID
            ownsBitmap = false
        } else {
            pixelBuffer = nil
            bitmapID = AriaGraphicsBridge.createBitmap(width: width, height: height)
            ownsBitmap = true
            guard bitmapID != 0 else { return nil }
        }
        let contextID: Int = (try? graphics.createContext(bitmapID)) ?? 0
        guard contextID != 0 else {
            if ownsBitmap { AriaGraphicsBridge.release(bitmapID) }
            return nil
        }
        self.bitmapID = bitmapID
        self.contextID = contextID
        self.width = width
        self.height = height
        isGray = space.isGray
        self.bytesPerRow = space.isGray ? width : width * 4
    }

    deinit {
        flush()
        try? AriaGraphicsBridge.object?.releaseContext(contextID) as Void?
        if ownsBitmap { AriaGraphicsBridge.release(bitmapID) }
        exposed?.deallocate()
    }

    /// The pixels, in this context's own memory: one gray byte per pixel, or BGRA
    /// premultiplied. Drawing keeps it current; writes reach the image at makeImage().
    public var data: UnsafeMutableRawPointer? {
        if exposed == nil {
            exposed = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * height, alignment: 16)
            flush()
            pull()
        }
        return exposed
    }

    private func pull() {
        guard let exposed, let bytes: Data = try? AriaGraphicsBridge.object?.readPixels(bitmapID, isGray) else { return }
        let count = min(bytes.count, bytesPerRow * height)
        bytes.copyBytes(to: exposed.assumingMemoryBound(to: UInt8.self), count: count)
    }

    private func push() {
        guard let exposed else { return }
        let bytes = Data(bytes: exposed, count: bytesPerRow * height)
        try? AriaGraphicsBridge.object?.writePixels(bitmapID, bytes, isGray) as Void?
    }

    private func state(_ command: String) {
        pending.append(command)
    }

    /// Drawing that changes pixels: when they are exposed, it happens now.
    private func draw(_ command: String, keeping object: AnyObject? = nil) {
        pending.append(command)
        if let object { pendingObjects.append(object) }
        if exposed != nil {
            push()
            flush()
            pull()
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        let commands = pending.joined(separator: "\n")
        pending.removeAll(keepingCapacity: true)
        try? AriaGraphicsBridge.object?.run(contextID, commands) as Void?
        pendingObjects.removeAll(keepingCapacity: true)
    }

    public func makeImage() -> CGImage? {
        flush()
        if exposed != nil { push() }
        let id = AriaGraphicsBridge.copy(bitmapID)
        guard id != 0 else { return nil }
        return CGImage(id: id, width: width, height: height)
    }

    // Graphics state

    public func saveGState() { state("save") }
    public func restoreGState() { state("restore") }
    public func translateBy(x: CGFloat, y: CGFloat) { state("ctm 1 0 0 1 \(x) \(y)") }
    public func scaleBy(x: CGFloat, y: CGFloat) { state("ctm \(x) 0 0 \(y) 0 0") }
    public func concatenate(_ transform: CGAffineTransform) {
        state("ctm \(transform.a) \(transform.b) \(transform.c) \(transform.d) \(transform.tx) \(transform.ty)")
    }
    public func setFillColor(_ color: CGColor) { state("fillColor \(color.command)") }
    public func setStrokeColor(_ color: CGColor) { state("strokeColor \(color.command)") }
    public func setLineWidth(_ width: CGFloat) { state("lineWidth \(width)") }
    public func setLineCap(_ cap: CGLineCap) { state("cap \(cap.rawValue)") }
    public func setAlpha(_ alpha: CGFloat) { state("alpha \(alpha)") }
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        if let color {
            state("shadow \(offset.width) \(offset.height) \(blur) \(color.command)")
        } else {
            state("shadow 0 0 -1 0 0 0 0")
        }
    }
    public func setShadow(offset: CGSize, blur: CGFloat) {
        setShadow(offset: offset, blur: blur, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1.0 / 3))
    }

    // Paths and clipping

    public func addPath(_ path: CGPath) {
        pending.append(contentsOf: path.commands)
    }
    public func addRect(_ rect: CGRect) { state("pathRect \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }
    public func addEllipse(in rect: CGRect) { state("pathEllipse \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }
    public func fillPath() { draw("fillPath") }
    public func strokePath() { draw("strokePath") }
    public func clip() { state("clipPath") }
    public func clip(to rect: CGRect) { state("clipRect \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }

    // Drawing

    public func fill(_ rect: CGRect) { draw("fillRect \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }
    public func fillEllipse(in rect: CGRect) { draw("fillEllipse \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }
    public func clear(_ rect: CGRect) { draw("clearRect \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)") }

    public func strokeLineSegments(between points: [CGPoint]) {
        guard points.count >= 2 else { return }
        draw("segments " + points.map { "\($0.x) \($0.y)" }.joined(separator: " "))
    }

    public func drawLinearGradient(_ gradient: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        draw("linear \(start.x) \(start.y) \(end.x) \(end.y) \(gradient.command)")
    }

    /// Gradients that start at their centre, as the shared code draws them.
    public func drawRadialGradient(_ gradient: CGGradient, startCenter: CGPoint, startRadius: CGFloat,
                                   endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {
        draw("radial \(endCenter.x) \(endCenter.y) \(endRadius) \(gradient.command)")
    }

    public func draw(_ image: CGImage, in rect: CGRect) {
        let smooth = interpolationQuality == .none ? 0 : 1
        draw("image \(image.id) \(rect.minX) \(rect.minY) \(rect.width) \(rect.height) \(smooth)", keeping: image)
    }

    /// UIKit drawing: the image upright in a flipped context (UIImage.draw(in:)).
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        draw("upright \(image.id) \(rect.minX) \(rect.minY) \(rect.width) \(rect.height)", keeping: image)
    }

    public func drawPDFPage(_ page: CGPDFPage) {
        draw("pdf \(page.document.id) \(page.index)", keeping: page)
    }

    public func beginTransparencyLayer(auxiliaryInfo: CFDictionary?) { state("beginLayer") }
    public func endTransparencyLayer() { draw("endLayer") }

    /// UIKit text drawing (NSAttributedString.draw) at a point in a flipped context.
    func drawText(_ text: String, font: UIFont, color: CGColor, at point: CGPoint, width: CGFloat,
                  mode: Int, alignment: Int) {
        if exposed != nil { push() }
        flush()
        try? AriaGraphicsBridge.object?.drawText(contextID, text, font.familyName, font.isBold, font.isItalic,
                                                  Double(font.pointSize), Double(color.red), Double(color.green),
                                                  Double(color.blue), Double(color.alpha), Double(point.x),
                                                  Double(point.y), Double(width), mode, alignment) as Void?
        if exposed != nil { pull() }
    }
}

// MARK: - UIKit drawing

private final class AriaGraphicsContextStack {
    var contexts: [CGContext] = []
}

private func ariaContextStack() -> AriaGraphicsContextStack {
    let key = "AriaGraphicsContextStack"
    if let stack = Thread.current.threadDictionary[key] as? AriaGraphicsContextStack { return stack }
    let stack = AriaGraphicsContextStack()
    Thread.current.threadDictionary[key] = stack
    return stack
}

public func UIGraphicsPushContext(_ context: CGContext) {
    ariaContextStack().contexts.append(context)
}

public func UIGraphicsPopContext() {
    _ = ariaContextStack().contexts.popLast()
}

public func UIGraphicsGetCurrentContext() -> CGContext? {
    ariaContextStack().contexts.last
}

public final class UIGraphicsImageRendererFormat: @unchecked Sendable {
    public enum Range: Int, Sendable {
        case unspecified = -1
        case automatic = 0
        case extended = 1
        case standard = 2
    }

    public var scale: CGFloat = 1
    public var opaque = false
    public var preferredRange: Range = .automatic

    public init() {}
}

public final class UIGraphicsImageRendererContext {
    public let cgContext: CGContext

    init(cgContext: CGContext) {
        self.cgContext = cgContext
    }
}

/// What UIGraphicsImageRenderer.image returns here: the shared code only takes its cgImage.
public final class UIGraphicsRenderedImage: @unchecked Sendable {
    public let cgImage: CGImage?
    public let size: CGSize

    init(cgImage: CGImage?, size: CGSize) {
        self.cgImage = cgImage
        self.size = size
    }
}

public final class UIGraphicsImageRenderer {
    let size: CGSize
    let format: UIGraphicsImageRendererFormat

    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {
        self.size = size
        self.format = format
    }

    public convenience init(size: CGSize) {
        self.init(size: size, format: UIGraphicsImageRendererFormat())
    }

    /// Draws at one pixel per point, in UIKit's top-left coordinates.
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIGraphicsRenderedImage {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return UIGraphicsRenderedImage(cgImage: nil, size: size) }
        if format.opaque {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        actions(UIGraphicsImageRendererContext(cgContext: context))
        UIGraphicsPopContext()
        return UIGraphicsRenderedImage(cgImage: context.makeImage(), size: size)
    }
}

/// The encoded bytes each UIImage was made from, so drawing decodes them directly
/// instead of re-encoding Skip's Compose image (a photo as PNG is tens of megabytes).
package enum AriaImageSources {
    private final class Entry {
        weak var image: UIImage?
        let data: Data
        init(image: UIImage, data: Data) {
            self.image = image
            self.data = data
        }
    }

    nonisolated(unsafe) private static var entries: [ObjectIdentifier: Entry] = [:]
    private static let lock = NSLock()

    package static func remember(_ data: Data, for image: UIImage) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { $0.value.image != nil }
        entries[ObjectIdentifier(image)] = Entry(image: image, data: data)
    }

    static func data(for image: UIImage) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[ObjectIdentifier(image)], entry.image === image else { return nil }
        return entry.data
    }
}

public extension UIImage {
    /// Through PNG: Skip's UIImage is a Compose image.
    convenience init(cgImage: CGImage) {
        let png = cgImage.pngData ?? Data()
        self.init(data: png, scale: 1)!
        AriaImageSources.remember(png, for: self)
    }

    var cgImage: CGImage? {
        (AriaImageSources.data(for: self) ?? pngData()).flatMap { CGImage(encoded: $0) }
    }

    func draw(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let image = cgImage else { return }
        context.drawUpright(image, in: rect)
    }

    func draw(at point: CGPoint) {
        draw(in: CGRect(origin: point, size: size))
    }
}

// MARK: - Fonts and text

public final class UIFontDescriptor: @unchecked Sendable {
    public struct SymbolicTraits: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let traitItalic = SymbolicTraits(rawValue: 1 << 0)
        public static let traitBold = SymbolicTraits(rawValue: 1 << 1)
    }

    let family: String
    public let symbolicTraits: SymbolicTraits

    init(family: String, symbolicTraits: SymbolicTraits) {
        self.family = family
        self.symbolicTraits = symbolicTraits
    }

    public func withSymbolicTraits(_ traits: SymbolicTraits) -> UIFontDescriptor? {
        UIFontDescriptor(family: family, symbolicTraits: traits)
    }
}

/// A family and style resolved to a Typeface in Kotlin (AriaFonts): the iOS app's bundled
/// fonts by their names, or the system's sans-serif, serif and monospace.
public final class UIFont: @unchecked Sendable {
    private struct Face {
        let family: String
        let bold: Bool
        let italic: Bool
    }

    public let familyName: String
    public let fontName: String
    public let pointSize: CGFloat
    let isBold: Bool
    let isItalic: Bool

    private static let systemFamilies = ["sans-serif", "serif", "monospace"]
    nonisolated(unsafe) private static var cachedFaces: [String: Face]?
    private static let lock = NSLock()

    private init(family: String, name: String, size: CGFloat, bold: Bool, italic: Bool) {
        familyName = family
        fontName = name
        pointSize = size
        isBold = bold
        isItalic = italic
    }

    public static var familyNames: [String] {
        let names: String = (try? AriaGraphicsBridge.object?.familyNames()) ?? ""
        return names.split(separator: "\n").map(String.init)
    }

    public static func fontNames(forFamilyName family: String) -> [String] {
        faces().filter { $0.value.family.caseInsensitiveCompare(family) == .orderedSame }.map(\.key).sorted()
    }

    /// Every face by name: bundled files by file name, system faces as "family", "family-Bold"...
    private static func faces() -> [String: Face] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedFaces { return cachedFaces }
        var faces: [String: Face] = [:]
        for family in familyNames {
            if systemFamilies.contains(family) {
                faces[family] = Face(family: family, bold: false, italic: false)
                faces[family + "-Bold"] = Face(family: family, bold: true, italic: false)
                faces[family + "-Italic"] = Face(family: family, bold: false, italic: true)
                faces[family + "-BoldItalic"] = Face(family: family, bold: true, italic: true)
                continue
            }
            let lines: String = (try? AriaGraphicsBridge.object?.faces(family)) ?? ""
            for line in lines.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 3 else { continue }
                faces[String(parts[0])] = Face(family: family, bold: parts[1] == "1", italic: parts[2] == "1")
            }
        }
        cachedFaces = faces
        return faces
    }

    /// Nil for a font Android doesn't have, as on iOS.
    public convenience init?(name: String, size: CGFloat) {
        guard let face = UIFont.faces().first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
        else { return nil }
        self.init(family: face.family, name: name, size: size, bold: face.bold, italic: face.italic)
    }

    public convenience init(descriptor: UIFontDescriptor, size: CGFloat) {
        let bold = descriptor.symbolicTraits.contains(.traitBold)
        let italic = descriptor.symbolicTraits.contains(.traitItalic)
        self.init(family: descriptor.family, name: descriptor.family, size: size, bold: bold, italic: italic)
    }

    public static func systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(family: "sans-serif", name: "sans-serif", size: size, bold: false, italic: false)
    }

    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(family: "sans-serif", name: "sans-serif-Bold", size: size, bold: true, italic: false)
    }

    public var fontDescriptor: UIFontDescriptor {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }
        return UIFontDescriptor(family: familyName, symbolicTraits: traits)
    }
}

public enum NSTextAlignment: Int, Sendable {
    case left = 0
    case center = 1
    case right = 2
    case justified = 3
    case natural = 4
}

public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping = 0
    case byCharWrapping = 1
    case byClipping = 2
    case byTruncatingHead = 3
    case byTruncatingTail = 4
    case byTruncatingMiddle = 5
}

open class NSParagraphStyle: NSObject, @unchecked Sendable {
    public var alignment: NSTextAlignment = .natural
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping

    public override init() {}
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1 << 0)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 1 << 1)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 1 << 3)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 1 << 5)
}

public final class NSStringDrawingContext {}

public extension NSAttributedString.Key {
    static let font = NSAttributedString.Key("NSFont")
    static let foregroundColor = NSAttributedString.Key("NSColor")
    static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
}

/// One style for the whole string, as the shared code uses them.
public extension NSAttributedString {
    private var drawingStyle: (font: UIFont, color: CGColor, paragraph: NSParagraphStyle?) {
        let attributes = length > 0 ? self.attributes(at: 0, effectiveRange: nil) : [:]
        let font = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: 12)
        let color = (attributes[.foregroundColor] as? UIColor)?.cgColor ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        return (font, color, attributes[.paragraphStyle] as? NSParagraphStyle)
    }

    private func measure(width: CGFloat, mode: Int) -> CGSize {
        let font = drawingStyle.font
        let result: String = (try? AriaGraphicsBridge.object?.measureText(string, font.familyName, font.isBold, font.isItalic,
                                                                           Double(font.pointSize), Double(width), mode)) ?? ""
        let parts = result.split(separator: " ").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : .zero
    }

    func size() -> CGSize {
        measure(width: 0, mode: 0)
    }

    func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) -> CGRect {
        let wraps = options.contains(.usesLineFragmentOrigin) && size.width.isFinite
        return CGRect(origin: .zero, size: measure(width: size.width, mode: wraps ? 1 : 0))
    }

    func draw(at point: CGPoint) {
        guard let context = UIGraphicsGetCurrentContext(), length > 0 else { return }
        let style = drawingStyle
        context.drawText(string, font: style.font, color: style.color, at: point, width: 0, mode: 0, alignment: 0)
    }

    func draw(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), length > 0 else { return }
        let style = drawingStyle
        let truncates = [.byTruncatingTail, .byTruncatingHead, .byTruncatingMiddle, .byClipping]
            .contains(style.paragraph?.lineBreakMode ?? .byWordWrapping)
        let alignment: Int
        switch style.paragraph?.alignment ?? .natural {
        case .center: alignment = 1
        case .right: alignment = 2
        default: alignment = 0
        }
        context.drawText(string, font: style.font, color: style.color, at: rect.origin, width: rect.width,
                         mode: truncates ? 2 : 1, alignment: alignment)
    }

    func draw(with rect: CGRect, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) {
        guard let graphics = UIGraphicsGetCurrentContext(), length > 0 else { return }
        let style = drawingStyle
        let wraps = options.contains(.usesLineFragmentOrigin)
        graphics.drawText(string, font: style.font, color: style.color, at: rect.origin, width: rect.width,
                          mode: wraps ? 1 : 0, alignment: 0)
    }
}

// MARK: - Core Video pixel buffers

public typealias CVReturn = Int32
public typealias OSType = UInt32
public let kCVReturnSuccess: CVReturn = 0
public let kCVReturnError: CVReturn = -6660
public let kCVPixelFormatType_32BGRA: OSType = 0x42475241
public let kCVPixelBufferPixelFormatTypeKey = "PixelFormatType"
public let kCVPixelBufferWidthKey = "Width"
public let kCVPixelBufferHeightKey = "Height"
public let kCVPixelBufferMetalCompatibilityKey = "MetalCompatibility"
public let kCVPixelBufferIOSurfacePropertiesKey = "IOSurfaceProperties"

public struct CVPixelBufferLockFlags: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let readOnly = CVPixelBufferLockFlags(rawValue: 1)
}

/// A frame: a bitmap in Kotlin. Its base address is a token that CGContext(data:)
/// recognizes, so drawing goes straight to the bitmap.
public final class CVPixelBuffer: @unchecked Sendable {
    private final class Entry {
        weak var buffer: CVPixelBuffer?
        init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
    }

    nonisolated(unsafe) private static var registry: [UnsafeMutableRawPointer: Entry] = [:]
    private static let lock = NSLock()

    package let bitmapID: Int
    public let width: Int
    public let height: Int
    let token: UnsafeMutableRawPointer
    private let pool: CVPixelBufferPool?

    init?(width: Int, height: Int, pool: CVPixelBufferPool?) {
        let bitmapID = pool?.takeBitmap() ?? AriaGraphicsBridge.createBitmap(width: width, height: height)
        guard bitmapID != 0 else { return nil }
        self.bitmapID = bitmapID
        self.width = width
        self.height = height
        self.pool = pool
        token = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        Self.lock.lock()
        Self.registry[token] = Entry(self)
        Self.lock.unlock()
    }

    deinit {
        Self.lock.lock()
        Self.registry[token] = nil
        Self.lock.unlock()
        token.deallocate()
        if let pool {
            pool.recycle(bitmapID)
        } else {
            AriaGraphicsBridge.release(bitmapID)
        }
    }

    static func registered(_ address: UnsafeMutableRawPointer) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return registry[address]?.buffer
    }
}

public final class CVPixelBufferPool: @unchecked Sendable {
    let width: Int
    let height: Int
    private var free: [Int] = []
    private let lock = NSLock()

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    deinit {
        free.forEach(AriaGraphicsBridge.release)
    }

    func takeBitmap() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return free.popLast()
    }

    func recycle(_ bitmapID: Int) {
        lock.lock()
        defer { lock.unlock() }
        free.append(bitmapID)
    }
}

@discardableResult
public func CVPixelBufferCreate(_ allocator: CFAllocator?, _ width: Int, _ height: Int, _ pixelFormatType: OSType,
                                _ pixelBufferAttributes: CFDictionary?,
                                _ pixelBufferOut: UnsafeMutablePointer<CVPixelBuffer?>) -> CVReturn {
    pixelBufferOut.pointee = CVPixelBuffer(width: width, height: height, pool: nil)
    return pixelBufferOut.pointee == nil ? kCVReturnError : kCVReturnSuccess
}

@discardableResult
public func CVPixelBufferPoolCreatePixelBuffer(_ allocator: CFAllocator?, _ pixelBufferPool: CVPixelBufferPool,
                                               _ pixelBufferOut: UnsafeMutablePointer<CVPixelBuffer?>) -> CVReturn {
    pixelBufferOut.pointee = CVPixelBuffer(width: pixelBufferPool.width, height: pixelBufferPool.height, pool: pixelBufferPool)
    return pixelBufferOut.pointee == nil ? kCVReturnError : kCVReturnSuccess
}

@discardableResult
public func CVPixelBufferLockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ lockFlags: CVPixelBufferLockFlags) -> CVReturn {
    kCVReturnSuccess
}

@discardableResult
public func CVPixelBufferUnlockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ unlockFlags: CVPixelBufferLockFlags) -> CVReturn {
    kCVReturnSuccess
}

public func CVPixelBufferGetBaseAddress(_ pixelBuffer: CVPixelBuffer) -> UnsafeMutableRawPointer? {
    pixelBuffer.token
}

public func CVPixelBufferGetBytesPerRow(_ pixelBuffer: CVPixelBuffer) -> Int {
    pixelBuffer.width * 4
}

public func CVPixelBufferGetWidth(_ pixelBuffer: CVPixelBuffer) -> Int {
    pixelBuffer.width
}

public func CVPixelBufferGetHeight(_ pixelBuffer: CVPixelBuffer) -> Int {
    pixelBuffer.height
}

/// Swift's ObjC autorelease pools; nothing to drain here.
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
