//
//  AriaWindowLayout.swift
//  MuseReaderiOS
//

import Observation
#if os(Android)
// Skip's Observation bridge, so Android's UI redraws when these properties change.
import SkipFuse
#endif
import Foundation
import UIKit

/// Whether Aria shows its phone or its iPad layout. On iOS the window's size decides, so an
/// iPad window narrower than an iPad mini (Split View, Slide Over, a small Stage Manager
/// window) gets the phone layout instead of a squeezed iPad one.
///
/// Full screen looks exactly as it did when the device alone decided: every iPhone gets the
/// phone layout, and every iPad's screen is at least `minimumTabletSide` on both sides.
///
/// Device behaviour that isn't layout (orientation lock, default zoom, Pencil annotations, the
/// chord keyboard's height) still checks `UIDevice` directly.
///
/// A shared instance rather than an environment value, like `DuoPoseMonitor`, because the
/// reader is a full-screen cover outside the library's hierarchy. `DuoHingeWatcher` reports
/// the window's size; views that read this redraw when the window resizes or rotates.
@MainActor
@Observable
final class AriaWindowLayout {
    static let shared = AriaWindowLayout()

    /// The shortest window side that gets the iPad layout: the iPad mini's (744 x 1133).
    static let minimumTabletSide: CGFloat = 744

    #if os(Android)
    /// Android: the screen, and tablets (600 dp and wider) get the iPad layout, as before.
    var windowSize: CGSize {
        UIScreen.main.bounds.size
    }

    var usesPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #else
    /// Starts at the screen's size, which is the window's in full screen, so the first frame
    /// is laid out as before.
    private(set) var windowSize = UIScreen.main.bounds.size

    var usesPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            || min(windowSize.width, windowSize.height) < Self.minimumTabletSide
    }

    func updateWindowSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != windowSize else {
            return
        }
        windowSize = size
    }
    #endif

    var isLandscape: Bool {
        windowSize.width > windowSize.height
    }
}
