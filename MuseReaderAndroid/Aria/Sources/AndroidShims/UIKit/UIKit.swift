// Android stand-in for UIKit: Skip's SwiftUI provides UIImage, UIColor, UIApplication,
// UIPasteboard; the rest of what shared iOS code uses is added here.

@_exported import Foundation
@_exported import SwiftUI
import SkipFuse

// Skip's SwiftUI geometry types, which the shared views use (see AndroidPlatformTypes.swift).
public typealias CGFloat = SkipSwiftUI.CGFloat
public typealias CGRect = SkipSwiftUI.CGRect

public typealias UIBackgroundTaskIdentifier = Int

public extension UIBackgroundTaskIdentifier {
    static var invalid: UIBackgroundTaskIdentifier { 0 }
}

public extension UIApplication {
    // iOS finishes work after the app moves to the background (Aria uses it to finish
    // autosaves). Android gives a backgrounded app time without asking, so there is no task
    // to begin; the expiration handler is never called.
    func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        1
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}

// MARK: - Device and screen (AriaDevice.kt)


nonisolated(unsafe) private let ariaDevice: AnyDynamicObject? = try? AnyDynamicObject(className: "aria.skip.AriaDevice")

public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1
    case phone = 0
    case pad = 1
}

public final class UIDevice: @unchecked Sendable {
    public static let current = UIDevice()

    /// Tablets (smallest width 600 dp or more) are `.pad`, as Android's own layouts decide.
    public let userInterfaceIdiom: UIUserInterfaceIdiom = {
        let isTablet: Bool? = try? ariaDevice?.isTablet()
        return isTablet == true ? .pad : .phone
    }()
}

public final class UIScreen: @unchecked Sendable {
    public static let main = UIScreen()

    /// The display in points (dp), like iOS.
    public var bounds: CGRect {
        let width: Double = (try? ariaDevice?.screenWidth()) ?? 0
        let height: Double = (try? ariaDevice?.screenHeight()) ?? 0
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    public var scale: CGFloat {
        let density: Double = (try? ariaDevice?.scale()) ?? 1
        return CGFloat(density)
    }
}

public struct UIEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

// MARK: - Haptics

@MainActor
public final class UISelectionFeedbackGenerator {
    public init() {}
    public func prepare() {}
    public func selectionChanged() {
        try? ariaDevice?.haptic(0) as Void?
    }
}

@MainActor
public final class UIImpactFeedbackGenerator {
    public enum FeedbackStyle: Int, Sendable {
        case light, medium, heavy, soft, rigid
    }

    private let style: FeedbackStyle

    public init(style: FeedbackStyle = .medium) {
        self.style = style
    }

    public func prepare() {}

    public func impactOccurred() {
        try? ariaDevice?.haptic(style == .heavy || style == .rigid ? 2 : 1) as Void?
    }
}

// MARK: - System colors

/// iOS's semantic colors, at their light-mode values (Aria always uses light mode).
public extension UIColor {
    private static func rgb(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
    }

    static var secondarySystemBackground: UIColor { rgb(242, 242, 247) }
    static var tertiarySystemBackground: UIColor { rgb(255, 255, 255) }
    static var systemGroupedBackground: UIColor { rgb(242, 242, 247) }
    static var secondarySystemGroupedBackground: UIColor { rgb(255, 255, 255) }
    static var tertiarySystemGroupedBackground: UIColor { rgb(242, 242, 247) }
    static var systemFill: UIColor { rgb(120, 120, 128, 0.2) }
    static var secondarySystemFill: UIColor { rgb(120, 120, 128, 0.16) }
    static var tertiarySystemFill: UIColor { rgb(118, 118, 128, 0.12) }
    static var quaternarySystemFill: UIColor { rgb(116, 116, 128, 0.08) }
    static var label: UIColor { rgb(0, 0, 0) }
    static var secondaryLabel: UIColor { rgb(60, 60, 67, 0.6) }
    static var tertiaryLabel: UIColor { rgb(60, 60, 67, 0.3) }
    static var quaternaryLabel: UIColor { rgb(60, 60, 67, 0.18) }
    static var separator: UIColor { rgb(60, 60, 67, 0.29) }
    static var opaqueSeparator: UIColor { rgb(198, 198, 200) }
    static var systemGray: UIColor { rgb(142, 142, 147) }
    static var systemGray2: UIColor { rgb(174, 174, 178) }
    static var systemGray3: UIColor { rgb(199, 199, 204) }
    static var systemGray4: UIColor { rgb(209, 209, 214) }
    static var systemGray5: UIColor { rgb(229, 229, 234) }
    static var systemGray6: UIColor { rgb(242, 242, 247) }
}

public extension Color {
    init(uiColor: UIColor) {
        self.init(uiColor)
    }
}

// MARK: - Orientation

public struct UIInterfaceOrientationMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let portrait = UIInterfaceOrientationMask(rawValue: 1 << 1)
    public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 1 << 2)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 1 << 3)
    public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 1 << 4)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .portraitUpsideDown, .landscape]
    public static let allButUpsideDown: UIInterfaceOrientationMask = [.portrait, .landscape]
}

/// Requests an orientation for the activity: what the iOS app delegate's
/// supportedInterfaceOrientations does (Aria locks phones to portrait while editing).
public func ariaRequestOrientations(_ orientations: UIInterfaceOrientationMask) {
    let kind: Int
    if orientations == .portrait {
        kind = 1
    } else if orientations.isSubset(of: .landscape) {
        kind = 2
    } else {
        kind = 0
    }
    try? ariaDevice?.setOrientation(kind) as Void?
}

// MARK: - SwiftUI helpers for the app module

public extension View {
    /// Skip's plain button style. The app module calls this from its own
    /// `buttonStyle(_:)` for custom styles, where `buttonStyle(.plain)` would call itself.
    func ariaSkipPlainButtonStyle() -> some View {
        buttonStyle(.plain)
    }

    /// Skip's presentationDetents, for the app module's own version (which picks one).
    func ariaSkipPresentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        presentationDetents(detents)
    }
}
