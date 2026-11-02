//
//  LayoutScreenshotUITests.swift
//  MuseReaderiOSUITests
//
//  Walks the main screens in portrait and landscape and saves a screenshot of each, so two
//  builds can be compared pixel for pixel. Not part of the app's test suite; run it alone:
//
//  TEST_RUNNER_LAYOUT_SHOTS_DIR=<folder> xcodebuild test-without-building ... \
//      -only-testing:AriaUITests/LayoutScreenshotUITests
//
//  The library needs Brahms' Wiegenlied (promo/aria-promo/ipad-setup/Scores).
//

import XCTest

final class LayoutScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LAYOUT_SHOTS_DIR"], "set TEST_RUNNER_LAYOUT_SHOTS_DIR")
        outputDirectory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
        hold(4)
    }

    @MainActor
    func testLayoutScreens() throws {
        for (name, orientation) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
            XCUIDevice.shared.orientation = orientation
            hold(2)
            dismissPrompts()
            shot("1-library-\(name)")

            openScore()
            hold(6)
            shot("2-reader-\(name)")

            if tapIfPresent(app.buttons["Parts"]) {
                hold(1.5)
                shot("3-parts-\(name)")
                closePanel(app.buttons["Parts"])
            }

            if tapIfPresent(app.buttons["Share Score"]) {
                hold(2)
                shot("4-export-\(name)")
                closePanel(app.buttons["Share Score"])
            }

            if tapIfPresent(app.buttons["Mixer"]) {
                hold(2)
                shot("5-mixer-\(name)")
                if !tapIfPresent(app.buttons["Close mixer"]) {
                    closePanel(app.buttons["Mixer"])
                }
                hold(1)
            }

            if tapIfPresent(app.buttons["Edit score"]) {
                hold(5)
                shot("6-edit-\(name)")
                _ = tapIfPresent(app.buttons["Done editing"])
                hold(3)
            }

            _ = tapIfPresent(app.buttons["Back"])
            hold(3)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Helpers

    private func openScore() {
        dismissPrompts()
        // The card shows the file name until the score's own title has been read.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Wiegenlied' OR label CONTAINS 'Op.49'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), dump("no Wiegenlied card"))
        card.tap()
        XCTAssertTrue(app.buttons["Parts"].waitForExistence(timeout: 60), dump("score did not open"))
    }

    /// The panels close from their own button; if one covers it, a tap at the window's top
    /// corner (outside every panel) closes it instead.
    private func closePanel(_ button: XCUIElement) {
        if button.isHittable {
            button.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        }
        hold(1.5)
    }

    /// Clears first-run overlays: the App Store rating prompt, the feature tour, What's New.
    private func dismissPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<6 {
            let candidates = [app.buttons["Not Now"], springboard.buttons["Not Now"],
                              app.buttons["Got it"], app.buttons["Next"], app.buttons["Continue"]]
            guard let visible = candidates.first(where: { $0.exists && $0.isHittable }) else { return }
            visible.tap()
            hold(1)
        }
    }

    @discardableResult
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5), element.isHittable else {
            print("LAYOUT-SHOTS missing \(element)")
            return false
        }
        element.tap()
        return true
    }

    private func shot(_ name: String) {
        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        } catch {
            XCTFail("could not save \(name): \(error)")
        }
    }

    private func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func dump(_ message: String) -> String {
        print("LAYOUT-HIERARCHY-BEGIN\n\(app.debugDescription)\nLAYOUT-HIERARCHY-END")
        return message
    }
}
