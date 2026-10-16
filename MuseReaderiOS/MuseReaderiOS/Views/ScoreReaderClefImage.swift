//
//  ScoreReaderClefImage.swift
//  MuseReaderiOS
//
//  Clef glyphs from the notation font, drawn into template images.
//

import SwiftUI
import UIKit

enum ScoreReaderClefImage {
    private static var cache: [String: UIImage] = [:]

    static func image(for symbol: String) -> UIImage {
        if let cachedImage = cache[symbol] {
            return cachedImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let canvasSize = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { _ in
            let font = UIFont(name: MusicNotationFont.postScriptName, size: 52)
                ?? UIFont.systemFont(ofSize: 52, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let attributedSymbol = NSAttributedString(string: symbol, attributes: attributes)
            let bounds = attributedSymbol.boundingRect(
                with: CGSize(width: canvasSize.width * 2, height: canvasSize.height * 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let drawRect = CGRect(
                x: (canvasSize.width - bounds.width) / 2 - bounds.minX,
                y: (canvasSize.height - bounds.height) / 2 - bounds.minY,
                width: bounds.width,
                height: bounds.height
            )
            attributedSymbol.draw(in: drawRect)
        }.withRenderingMode(.alwaysTemplate)

        cache[symbol] = image
        return image
    }
}
