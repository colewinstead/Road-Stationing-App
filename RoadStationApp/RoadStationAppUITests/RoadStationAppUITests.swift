import XCTest

final class RoadStationAppUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func pageUp(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.88))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.35)))
    }
    @MainActor
    private func fullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && element.isHittable && element.frame.minY > 110 && element.frame.maxY < app.frame.height - 70
    }
    @MainActor
    private func sample(_ name: String, alignment: String, in app: XCUIApplication) {
        let button = app.buttons["sample-\(name)"]
        for _ in 0..<6 where !fullyVisible(button, in: app) { pageUp(app) }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        let row = app.buttons["alignment-\(alignment)"]
        for _ in 0..<4 where !fullyVisible(row, in: app) { app.swipeDown() }
        for _ in 0..<4 where !fullyVisible(row, in: app) { pageUp(app) }
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.otherElements["engineering-canvas"].waitForExistence(timeout: 10))
    }
    @MainActor
    private func set(_ id: String, _ value: String, in app: XCUIApplication) {
        let field = app.textFields[id]
        for _ in 0..<5 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let previous = field.value as? String ?? ""
        if !previous.isEmpty, previous != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count)) }
        field.typeText(value)
        if app.buttons["Done"].isHittable { app.buttons["Done"].tap() }
    }
    @MainActor
    private func attachment(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor
    func testCanvasAndManualForwardInverse() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("tangent-only", alignment: "TANGENT", in: app)
        let canvas = app.otherElements["engineering-canvas"]
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        attachment("tap-inspection", app: app)
        let initialY = canvas.frame.minY
        canvas.swipeUp()
        XCTAssertEqual(canvas.frame.minY, initialY, accuracy: 2, "Canvas pan must not scroll the page")
        canvas.swipeLeft(); canvas.pinch(withScale: 1.4, velocity: 2)
        app.buttons["Zoom in"].tap(); app.buttons["fit-canvas"].tap()
        app.segmentedControls["workspace-tabs"].buttons["Entry"].tap()
        set("easting-entry", "1050", in: app); set("northing-entry", "1995", in: app)
        app.buttons["calculate-forward"].tap()
        let station = app.staticTexts["result-station"]
        XCTAssertTrue(station.waitForExistence(timeout: 10))
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertTrue(app.staticTexts["result-offset"].label.contains("RT"))
        set("station-entry", "100+75.00", in: app); set("offset-entry", "5", in: app)
        app.segmentedControls["side-picker"].buttons["LT"].tap()
        app.buttons["calculate-inverse"].tap()
        XCTAssertTrue(app.staticTexts["Calculated coordinate"].waitForExistence(timeout: 10))
        let easting = app.descendants(matching: .any)["inverse-easting"]
        for _ in 0..<4 where !easting.isHittable { app.swipeUp() }
        XCTAssertEqual(easting.value as? String, "1075.000000")
        XCTAssertEqual(app.descendants(matching: .any)["inverse-northing"].value as? String, "2005.000000")
        app.swipeDown(); attachment("manual-entry", app: app)
    }

    @MainActor
    func testStationEquationRequiresExplicitBranch() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("station-equations", alignment: "EQUATIONS", in: app)
        app.segmentedControls["workspace-tabs"].buttons["Entry"].tap()
        set("station-entry", "103+50", in: app)
        app.buttons["calculate-inverse"].tap()
        XCTAssertTrue(app.staticTexts["query-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["query-error"].label.contains("ambiguous"))
        let branch = app.buttons["branch-2"]
        for _ in 0..<3 where !branch.isHittable { app.swipeUp() }
        XCTAssertTrue(branch.exists); attachment("equation-branch-choice", app: app); branch.tap()
        XCTAssertTrue(app.staticTexts["Calculated coordinate"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["query-error"].exists)
    }

    @MainActor
    func testSyntheticSpiralAndLargeCoordinateDrawing() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("spiral-curve-spiral", alignment: "LSCSL", in: app)
        app.segmentedControls["workspace-tabs"].buttons["Info"].tap()
        let spirals = app.descendants(matching: .any)["spiral-count"]
        for _ in 0..<4 where !spirals.isHittable { pageUp(app) }
        XCTAssertEqual(spirals.value as? String, "2")
        app.swipeDown(); app.buttons["fit-canvas"].tap(); attachment("spiral-workspace", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        sample("sr82_synthetic", alignment: "SR 82", in: app)
        app.otherElements["engineering-canvas"].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        attachment("projected-coordinate-workspace", app: app)
    }

    @MainActor
    private func pickFile(_ name: String, app: XCUIApplication) {
        let importButton = app.buttons["import-landxml"]
        for _ in 0..<5 where !fullyVisible(importButton, in: app) { app.swipeDown() }
        importButton.tap()
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 30)); browse.tap()
        func cell(_ label: String) -> XCUIElement {
            app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        }
        // Files remembers the last browsed location between presentations.
        // Navigate actual picker cells; app titles must never match a folder.
        let file = cell(name)
        for _ in 0..<6 {
            if file.waitForExistence(timeout: 3) { break }
            let folder = cell("RoadStation")
            let local = cell("On My iPhone")
            let back = app.buttons["DOC.navBarButton.backInHistory"]
            if folder.exists, folder.isHittable { folder.tap() }
            else if local.exists, local.isHittable { local.tap() }
            else if back.exists, back.isEnabled { back.tap() }
            else { browse.tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
    }

    @MainActor
    func testFilesPickerImportsBothExtensionsAndShowsErrors() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // The runner stages these synthetic files in shared Documents. This
        // exercises the actual system picker and security-scoped import path.
        pickFile("import-check", app: app)
        XCTAssertTrue(app.buttons["alignment-TANGENT"].waitForExistence(timeout: 10))
        attachment("imported-landxml-project", app: app)
        pickFile("import-xml", app: app)
        XCTAssertTrue(app.buttons["alignment-TANGENT"].waitForExistence(timeout: 10))
        pickFile("malformed", app: app)
        XCTAssertTrue(app.staticTexts["import-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["alignment-TANGENT"].exists)
        attachment("import-error", app: app)
    }

    @MainActor
    func testMultipleAlignmentSelection() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("multiple-alignments", alignment: "NORTH", in: app)
        app.otherElements["engineering-canvas"].coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["result-offset"].label.contains("RT"))
    }
}
