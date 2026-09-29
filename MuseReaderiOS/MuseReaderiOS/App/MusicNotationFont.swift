//
//  MusicNotationFont.swift
//  MuseReaderiOS
//
//

import CoreText
import Foundation
import SwiftUI

enum MusicNotationFont {
    static let postScriptName = "BravuraText"
    static let bundledFileName = "BravuraText"

    static func registerBundledFonts() {
        let otfNames = [
            bundledFileName,
            "Edwin-Roman", "Edwin-Bold", "Edwin-Italic", "Edwin-BdIta",
            "MuseJazzText", "GootvilleText", "LelandText", "MScoreText",
            "FinaleBroadwayText", "FinaleMaestroText-Regular",
            "PetalumaScript", "PetalumaText"
        ]
        let ttfNames = ["FreeSerif", "FreeSerifBold", "FreeSerifItalic", "FreeSerifBoldItalic"]
        for (name, ext) in otfNames.map({ ($0, "otf") }) + ttfNames.map({ ($0, "ttf") }) {
            guard let fontURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            else {
                continue
            }
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    static func font(size: CGFloat) -> Font {
        .custom(postScriptName, size: size)
    }
}
