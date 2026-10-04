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
    private func revealImportedAlignment(_ name: String, app: XCUIApplication) {
        let row = app.buttons["alignment-\(name)"]
        // The explicit CRS controls add height to the project page. List rows
        // are created lazily, so reveal the alignment before asserting import.
        for _ in 0..<6 where !fullyVisible(row, in: app) { pageUp(app) }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
    }

    @MainActor
    func testFilesPickerImportsBothExtensionsAndShowsErrors() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // The runner stages these synthetic files in shared Documents. This
        // exercises the actual system picker and security-scoped import path.
        pickFile("import-check", app: app)
        revealImportedAlignment("TANGENT", app: app)
        attachment("imported-landxml-project", app: app)
        pickFile("import-xml", app: app)
        revealImportedAlignment("TANGENT", app: app)
        pickFile("malformed", app: app)
        XCTAssertTrue(app.staticTexts["import-error"].waitForExistence(timeout: 10))
        revealImportedAlignment("TANGENT", app: app)
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
    @MainActor
    func testCRSPickerSearchRecommendationConfirmationAndManualFallback() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("tangent-only", alignment: "TANGENT", in: app)
        let open = app.buttons["open-field-position"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let picker = app.buttons["open-crs-picker"]
        for _ in 0..<6 where !picker.isHittable { pageUp(app) }
        picker.tap()
        XCTAssertTrue(app.segmentedControls["crs-picker-tabs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Choose CRS"].exists)
        XCTAssertFalse(app.staticTexts["confirmed-crs"].exists)
        let inject = app.buttons["inject-crs-recommendation"]
        for _ in 0..<4 where !inject.isHittable { pageUp(app) }
        inject.tap()
        let recommended = app.buttons["crs-row-6510"]
        // A one-shot capture stays useful after the live stationing age limit.
        let status = app.staticTexts["crs-recommendation-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let statusFrame = status.frame
        let retentionDeadline = Date().timeIntervalSince1970 + 6
        let retained = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Date().timeIntervalSince1970 > retentionDeadline
        }, object: nil)
        wait(for: [retained], timeout: 10)
        XCTAssertTrue(status.label.contains("one-time location"))
        XCTAssertEqual(status.frame, statusFrame)
        XCTAssertTrue(app.staticTexts["crs-location-accuracy"].label.contains("±"))
        attachment("phase2b1-one-shot-retained", app: app)
        // Rank begins below the stable location explanation.
        for _ in 0..<3 where !recommended.isHittable { app.swipeDown() }
        XCTAssertTrue(recommended.waitForExistence(timeout: 5)); recommended.tap()
        XCTAssertTrue(app.staticTexts["crs-confirmation-code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["crs-confirmation-code"].label, "EPSG:6510")
        attachment("phase2b1-crs-confirmation", app: app)
        let recommendedUse = app.buttons["use-catalog-crs"]
        for _ in 0..<5 where !recommendedUse.isHittable { pageUp(app) }
        recommendedUse.tap()
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["confirmed-crs"].label.contains("EPSG:6510"))
        app.buttons["open-crs-picker"].tap()
        app.segmentedControls["crs-picker-tabs"].buttons["Search"].tap()
        set("crs-search", "Mississippi West", in: app)
        XCTAssertEqual(app.textFields["crs-search"].value as? String, "Mississippi West")
        expectation(for: NSPredicate(format: "label ==[c] %@", "9 results"), evaluatedWith: app.staticTexts["crs-search-count"])
        waitForExpectations(timeout: 10)
        attachment("phase2b1-crs-search", app: app)
        let found = app.buttons["crs-row-6510"]
        for _ in 0..<8 where !found.isHittable { pageUp(app) }
        XCTAssertTrue(found.waitForExistence(timeout: 10)); found.tap()
        XCTAssertEqual(app.staticTexts["crs-confirmation-code"].label, "EPSG:6510")
        let use = app.buttons["use-catalog-crs"]
        for _ in 0..<5 where !use.isHittable { pageUp(app) }
        use.tap()
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["confirmed-crs"].label.contains("EPSG:6510"))
        attachment("phase2b1-crs-selected", app: app)
        app.buttons["open-crs-picker"].tap()
        app.buttons["open-manual-epsg"].tap()
        set("epsg-entry", "3857", in: app); app.buttons["select-epsg"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "EPSG:3857"), evaluatedWith: app.staticTexts["confirmed-crs"])
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testFieldPositionExplicitCRSAndDebugPipeline() throws {
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("tangent-only", alignment: "TANGENT", in: app)
        let open = app.buttons["open-field-position"]
        for _ in 0..<4 where !open.isHittable { app.swipeDown() }
        open.tap()
        let start = app.buttons["start-location"]
        for _ in 0..<4 where !start.isHittable { pageUp(app) }
        XCTAssertFalse(start.isEnabled)
        let picker = app.buttons["open-crs-picker"]
        for _ in 0..<6 where !picker.isHittable { pageUp(app) }
        picker.tap()
        app.buttons["open-manual-epsg"].tap()
        set("epsg-entry", "999999", in: app)
        app.buttons["select-epsg"].tap()
        let status = app.staticTexts["manual-epsg-status"]
        let unavailable = NSPredicate(format: "label CONTAINS %@", "CRS unavailable")
        expectation(for: unavailable, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        set("epsg-entry", "3857", in: app)
        app.buttons["select-epsg"].tap()
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        // Independent inverse spherical Mercator formula (R=6378137m),
        // E=1050,N=1995 US survey feet. No RoadStation inverse supplies this fix.
        set("injected-latitude", "0.005462450563693558", in: app)
        set("injected-longitude", "0.0028749739852440867", in: app)
        set("injected-accuracy", "4", in: app)
        app.buttons["inject-location"].tap()
        let station = app.staticTexts["live-station"]
        for _ in 0..<10 where !station.isHittable { app.swipeDown() }
        XCTAssertTrue(station.waitForExistence(timeout: 10))
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertTrue(app.staticTexts["live-offset"].label.contains("5.0 ft RT"))
        XCTAssertTrue(app.staticTexts["location-source"].label.contains("DEBUG injected"))
        XCTAssertTrue(app.staticTexts["live-accuracy"].label.contains("13.1 ft"))
        let card = app.otherElements["field-result-card"]
        let freshFrame = card.frame
        attachment("phase2b-field-position", app: app)
        let liveStatus = app.staticTexts["live-status"]
        expectation(for: NSPredicate(format: "label == %@", "Stale — last known position"), evaluatedWith: liveStatus)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertTrue(app.staticTexts["live-offset"].label.contains("5.0 ft RT"))
        XCTAssertTrue(app.staticTexts["live-accuracy"].label.contains("13.1 ft"))
        XCTAssertEqual(card.frame.height, freshFrame.height, accuracy: 1)
        XCTAssertEqual(card.frame.minY, freshFrame.minY, accuracy: 1)
        attachment("phase2b-stale-last-known-position", app: app)
        let inject = app.buttons["inject-location"]
        for _ in 0..<6 where !inject.isHittable { pageUp(app) }
        inject.tap()
        expectation(for: NSPredicate(format: "label == %@", "Location ready."), evaluatedWith: liveStatus)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertEqual(card.frame.height, freshFrame.height, accuracy: 1)
        XCTAssertEqual(card.frame.minY, freshFrame.minY, accuracy: 1)
        for _ in 0..<5 where !app.buttons["stop-location"].isHittable { pageUp(app) }
        app.buttons["stop-location"].tap()
        XCTAssertFalse(station.exists)
    }

}
