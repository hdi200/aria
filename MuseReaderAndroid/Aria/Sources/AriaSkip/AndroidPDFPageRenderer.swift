// Draws score pages (PDF from the engine) into images on Android, for
// ScorePage.rasterizedImage(). iOS draws them with CGPDFDocument.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SkipFuse
import SwiftUI

enum AndroidPDFPageRenderer {
    /// `crop` is the part of the page to draw, in normalized page coordinates.
    nonisolated static func image(pdfData: Data, size: CGSize?, opaque: Bool = true,
                                  crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> UIImage? {
        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("pdf_handoff_begin")
        #endif
        #if os(Android) && ARIA_PHONE_AUDIT
        defer { AndroidInteractionTrace.point("pdf_handoff_end") }
        #endif

        let width = size.map { Int($0.width.rounded()) } ?? 0
        let height = size.map { Int($0.height.rounded()) } ?? 0
        do {
            let rasterizer = try AnyDynamicObject(className: "aria.skip.AriaPdfRasterizer")
            // Kotlin keeps the bitmap and passes back a key: no PNG encode and decode.

            #if os(Android) && ARIA_PHONE_AUDIT
            AndroidInteractionTrace.point("raster_jni_begin")
            #endif
            let key: String? = try rasterizer.bitmapKey(pdfData, width, height, opaque,
                                                        Double(crop.minX), Double(crop.minY), Double(crop.width), Double(crop.height))

        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("raster_jni_end")
        #endif

        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("image_handoff_begin")
        #endif
            #if os(Android) && ARIA_PHONE_AUDIT
            defer { AndroidInteractionTrace.point("image_handoff_end") }
            #endif
            return key.flatMap { UIImage(contentsOfFile: $0) }
        } catch {
            print("Aria PDF page rasterizing failed: \(error)")
            return nil
        }
    }
}
