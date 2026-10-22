// Android's MusicNotationFont (App/MusicNotationFont.swift on iOS registers the bundled
// fonts with CoreText). Android loads BravuraText from res/font/bravuratext.otf, which
// Skip finds by name, so nothing needs registering. Not limited to Android: the Skip
// project's own iOS build uses it in place of the held-back iOS file.

import SwiftUI

enum MusicNotationFont {
    static let postScriptName = "BravuraText"
    static let bundledFileName = "BravuraText"

    static func registerBundledFonts() {}

    static func font(size: CGFloat) -> Font {
        .custom(postScriptName, size: size)
    }
}

import SkipFuse

/// iOS: Views/ScoreReaderClefImage.swift (UIKit text drawing). The glyph is drawn by
/// Android's canvas with the notation font (AriaGlyphs.kt).
enum ScoreReaderClefImage {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
    /// A transparent pixel, for when the glyph can't be drawn.
    private static let blank = UIImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!)!

    static func image(for symbol: String) -> UIImage {
        if let cached = cache[symbol] {
            return cached
        }
        let scale = UIScreen.main.scale
        let png: Data? = try? AnyDynamicObject(className: "aria.skip.AriaGlyphs").png(symbol, Double(52 * scale), Int(96 * scale))
        guard let image = png.flatMap({ UIImage(data: $0) }) else {
            return blank
        }
        cache[symbol] = image
        return image
    }
}

/// The palettes' ♭ ♮ ♯ on Android: the system font's fallback drew them at different sizes
/// and heights. Drawn in the music font, each moved so its outline is centred in the line
/// (Bravura's flat sits higher than its natural and sharp), so a row of them lines up.
struct AndroidAccidentalGlyph: View {
    let symbol: String
    let size: CGFloat

    /// How far down each glyph moves, in ems, to centre its outline (BravuraText metrics).
    private static let centeringOffsets: [String: CGFloat] = ["♭": 0.15, "♮": 0.05, "♯": 0.055]

    static func isAccidental(_ symbol: String) -> Bool {
        centeringOffsets[symbol] != nil
    }

    var body: some View {
        Text(symbol)
            .font(MusicNotationFont.font(size: size))
            .fixedSize()
            .offset(y: (Self.centeringOffsets[symbol] ?? 0) * size)
    }
}
