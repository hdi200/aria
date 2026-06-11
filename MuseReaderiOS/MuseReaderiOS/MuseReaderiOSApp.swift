//
//  MuseReaderiOSApp.swift
//  MuseReaderiOS
//
//  Created by Jack Gruber on 4/13/26.
//

import SwiftUI
import UIKit

@main
struct MuseReaderiOSApp: App {
    init() {
        MusicNotationFont.registerBundledFonts()
        UIView.appearance().overrideUserInterfaceStyle = .light
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environment(\.colorScheme, .light)
        }
    }
}
