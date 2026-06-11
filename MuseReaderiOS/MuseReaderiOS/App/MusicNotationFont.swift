//
//  MusicNotationFont.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/5/26.
//

import CoreText
import Foundation
import SwiftUI

enum MusicNotationFont {
    static let postScriptName = "BravuraText"
    static let bundledFileName = "BravuraText"

    static func registerBundledFonts() {
        guard let fontURL = Bundle.main.url(forResource: bundledFileName, withExtension: "otf", subdirectory: "Resources/Fonts")
            ?? Bundle.main.url(forResource: bundledFileName, withExtension: "otf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: bundledFileName, withExtension: "otf")
        else {
            return
        }

        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    static func font(size: CGFloat) -> Font {
        .custom(postScriptName, size: size)
    }
}
