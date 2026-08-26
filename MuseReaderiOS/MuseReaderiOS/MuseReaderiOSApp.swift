//
//  MuseReaderiOSApp.swift
//  MuseReaderiOS
//
//  Created by Jack Gruber on 4/13/26.
//

import SwiftUI
import UIKit

final class MuseReaderAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedInterfaceOrientations: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedInterfaceOrientations
    }

    @MainActor
    static func updateSupportedInterfaceOrientations(_ orientations: UIInterfaceOrientationMask) {
        supportedInterfaceOrientations = orientations

        let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { scene -> UIWindowScene? in
            guard scene.activationState == .foregroundActive else {
                return nil
            }
            return scene as? UIWindowScene
        }

        for windowScene in foregroundScenes {
            windowScene.windows
                .first(where: \.isKeyWindow)?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()

            let preferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: orientations
            )
            windowScene.requestGeometryUpdate(preferences)
        }
    }
}

@main
struct MuseReaderiOSApp: App {
    @UIApplicationDelegateAdaptor(MuseReaderAppDelegate.self) private var appDelegate

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
