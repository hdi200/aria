import XCTest

/// Opt-in touch regression on a separate Fingering Placement QA score. Choose
/// coordinates from the inspection capture, in points, for the current device/pose.
final class FingeringPlacementUITests: XCTestCase {
    @MainActor
    func testFingeringEndOfNotesStaysResponsive() throws {
        let env = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: try XCTUnwrap(env["FINGERING_SHOTS_DIR"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fingering Endpoint Regression'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        card.tap()
        XCTAssertTrue(app.buttons["Edit score"].waitForExistence(timeout: 60))
        app.buttons["Edit score"].tap()
        Thread.sleep(forTimeInterval: 2)
        func shot(_ name: String) throws {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: output.appendingPathComponent(name + ".png"))
        }
        try shot("endpoint-01-editor")
        guard let x = env["FINGERING_X"].flatMap(Double.init),
              let y = env["FINGERING_Y"].flatMap(Double.init) else { return }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        app.buttons["Text"].tap()
        let fingering = app.buttons["Fingering"].firstMatch
        if !fingering.isHittable {
            app.scrollViews.containing(.button, identifier: "Fingering").firstMatch.swipeLeft()
        }
        fingering.tap()
        for digit in [1, 2, 3, 5, 4] {
            let key = app.buttons["Fingering \(digit)"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: key)
            guard XCTWaiter.wait(for: [ready], timeout: 8) == .completed else {
                try shot("endpoint-failed-disabled")
                XCTFail("Fingering controls stayed disabled before \(digit)")
                return
            }
            key.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Fingering 5"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        try shot("endpoint-02-last-note-responsive")
        // Leave the deck and undo all five test commands before finishing.
        app.buttons["Text"].firstMatch.tap()
        app.buttons["Select"].tap()
        for _ in 0..<5 {
            XCTAssertTrue(app.buttons["Undo"].isEnabled)
            app.buttons["Undo"].tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        try shot("endpoint-03-undone")
    }

    @MainActor
    func testFingeringPlacement() throws {
        let env = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: try XCTUnwrap(env["FINGERING_SHOTS_DIR"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fingering Placement QA'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.buttons["Edit score"].waitForExistence(timeout: 60))
        app.buttons["Edit score"].tap()
        Thread.sleep(forTimeInterval: 2)
        func shot(_ name: String) throws {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: output.appendingPathComponent(name + ".png"))
        }
        try shot("01-editor")
        guard let x = env["FINGERING_X"].flatMap(Double.init),
              let y = env["FINGERING_Y"].flatMap(Double.init) else { return }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x, dy: y))
        start.tap()
        Thread.sleep(forTimeInterval: 1)
        try shot("02-selected")
        // A note also has Undo and accepts a drag. Require the fingering's
        // text action strip so this cannot silently turn into a pitch-drag test.
        guard app.buttons["Edit"].exists else {
            XCTFail("Coordinate did not select the fingering; inspect 02-selected")
            return
        }
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(undo.isEnabled, "Fixture must start with no pending edits")
        start.press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: x + 12, dy: y - 12)))
        Thread.sleep(forTimeInterval: 2)
        try shot("03-moved")
        XCTAssertTrue(undo.isEnabled, "Fingering touch drag must reach the engine")
        if undo.isEnabled { undo.tap() }
        Thread.sleep(forTimeInterval: 3)
        try shot("04-undone")
        XCTAssertFalse(undo.isEnabled, "One Undo must restore the initial score")
        // Leave the fixture open; the owner can try the installed build.
    }
}
