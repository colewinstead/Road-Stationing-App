import XCTest

final class RoadStationAppUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReleaseStoreReadiness() throws {
        #if DEBUG
        throw XCTSkip("Run this smoke scenario with configuration Release.")
        #else
        executionTimeAllowance = 420
        let app = XCUIApplication(); app.launch(); app.activate()
        XCTAssertTrue(app.buttons["help-and-about"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Synthetic developer samples"].exists)
        app.buttons["help-and-about"].tap()
        XCTAssertTrue(app.staticTexts["app-version"].waitForExistence(timeout: 10))
        XCTAssertNotNil(app.staticTexts["app-version"].label.range(of: #"^Version 1\.0 \([0-9]+\)$"#, options: .regularExpression))
        attachment("release-help", app: app)
        for id in ["help-privacy", "help-support", "help-email", "help-acknowledgments"] {
            let link = app.descendants(matching: .any)[id].firstMatch
            for _ in 0..<8 where !link.isHittable { pageUp(app) }
            XCTAssertTrue(link.isHittable, "Missing Release help link: \(id)")
        }
        app.descendants(matching: .any)["help-acknowledgments"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "The MIT License")).firstMatch.waitForExistence(timeout: 5))
        attachment("release-acknowledgments", app: app)
        app.buttons["close-help"].tap()
        pickFile("roadstation-example", app: app)
        revealImportedAlignment("Example alignment", app: app)
        let confirm = app.buttons["confirm-imported-crs"]
        for _ in 0..<7 where !confirm.isHittable { app.swipeDown() }
        confirm.tap()
        let crs = app.staticTexts["confirmed-crs"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "EPSG:6507"), evaluatedWith: crs)
        waitForExpectations(timeout: 20)
        attachment("release-crs", app: app)
        let row = app.buttons["alignment-Example alignment"]
        for _ in 0..<7 where !row.isHittable { pageUp(app) }
        row.tap()
        app.segmentedControls["workspace-tabs"].buttons["Entry"].tap()
        set("easting-entry", "986377.5959036754", in: app)
        set("northing-entry", "1453406.9250950934", in: app)
        app.buttons["calculate-forward"].tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["result-station"].label, "STA 100+50.00")
        XCTAssertEqual(app.staticTexts["result-offset"].label, "5.000 ft RT")
        app.segmentedControls["workspace-tabs"].buttons["Inspect"].tap()
        attachment("release-inspection", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let savedName = "Example roadway \(UUID().uuidString.prefix(8))"
        let rename = app.buttons["rename-project"]
        for _ in 0..<10 where !rename.isHittable { pageUp(app) }
        rename.tap(); set("rename-project-name", savedName, in: app)
        app.buttons["save-project-name"].tap()
        XCTAssertTrue(app.navigationBars[savedName].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.activate()
        let saved = app.buttons["saved-project-\(savedName)"]
        for _ in 0..<10 where !saved.isHittable { pageUp(app) }
        XCTAssertTrue(saved.waitForExistence(timeout: 20))
        attachment("release-projects", app: app); saved.tap()
        for _ in 0..<7 where !app.staticTexts["confirmed-crs"].isHittable { pageUp(app) }
        XCTAssertTrue(app.staticTexts["confirmed-crs"].label.contains("EPSG:6507"))
        for _ in 0..<8 where !app.buttons["project-field-position"].isHittable { app.swipeDown() }
        app.buttons["project-field-position"].tap()
        let allowLocation = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allowLocation.waitForExistence(timeout: 3) { allowLocation.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["field-map"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["inject-location"].exists)
        XCTAssertFalse(app.textFields["injected-latitude"].exists)
        attachment("release-field-position", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let delete = app.buttons["delete-project"]
        for _ in 0..<10 where !delete.isHittable { pageUp(app) }
        delete.tap(); app.alerts["Delete Project?"].buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["RoadStation"].waitForExistence(timeout: 15))
        XCTAssertFalse(saved.exists)
        #endif
    }

    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ROADSTATION_TEST_STORAGE"] = UUID().uuidString
        return app
    }
    @MainActor
    private func pageUp(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.88))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.35)))
    }
    @MainActor
    private func fullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, frame.minY > 110, frame.maxY < app.frame.height - 70 else { return false }
        return element.isHittable
    }
    @MainActor
    private func waitForStableFrame(_ element: XCUIElement) {
        var previous: CGRect?
        expectation(for: NSPredicate { _, _ in
            let frame = element.frame
            defer { previous = frame }
            return !frame.isEmpty && frame == previous
        }, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
    @MainActor
    private func sample(_ name: String, alignment: String, in app: XCUIApplication) {
        for _ in 0..<3 where !app.navigationBars["RoadStation"].exists {
            if app.navigationBars.buttons.firstMatch.isHittable { app.navigationBars.buttons.firstMatch.tap() }
        }
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
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        let previous = field.value as? String ?? ""
        if !previous.isEmpty, previous != field.placeholderValue {
            if id != "rename-project-name" {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            } else {
            // A tap can place the caret inside the existing name.
            field.press(forDuration: 1.2)
            let selectAll = app.buttons["Select All"].firstMatch
            if selectAll.waitForExistence(timeout: 3) { selectAll.tap() }
            else if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "Could not clear \(id)")
            }
        }
        field.typeText(value)
        if app.buttons["Done"].isHittable { app.buttons["Done"].tap() }
    }
    @MainActor
    private func revealFieldSetup(_ app: XCUIApplication) {
        guard app.navigationBars["Field Position"].waitForExistence(timeout: 10), !app.staticTexts["confirmed-crs"].exists else { return }
        let panel = app.buttons["field-details-toggle"]
        if panel.value as? String == "Collapsed" {
            panel.tap()
            expectation(for: NSPredicate(format: "value == %@", "Expanded"), evaluatedWith: panel)
            waitForExpectations(timeout: 10)
        }
        if app.buttons["open-crs-picker"].exists { return }
        let disclosure = app.staticTexts["Coordinate system & setup"]
        for _ in 0..<5 where !disclosure.isHittable { pageUp(app) }
        disclosure.tap()
    }
    @MainActor
    private func revealDebugLocation(_ app: XCUIApplication) {
        let panel = app.buttons["field-details-toggle"]
        if panel.value as? String == "Collapsed" { panel.tap() }
        let disclosure = app.staticTexts["DEBUG location injection"]
        for _ in 0..<6 where !disclosure.isHittable { pageUp(app) }
        disclosure.tap()
    }
    @MainActor
    private func attachment(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor
    func testProjectFieldAndInspectionActionsNavigateIndependently() throws {
        let app = makeApp(); app.launch(); app.activate()
        sample("tangent-only", alignment: "TANGENT", in: app)
        app.navigationBars.buttons.firstMatch.tap()
        let field = app.buttons["project-field-position"]
        for _ in 0..<6 where !field.isHittable { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        XCTAssertTrue(app.navigationBars["Field Position"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["engineering-canvas"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Field Position"].exists)
        app.buttons["continue-alignment"].tap()
        XCTAssertTrue(app.otherElements["engineering-canvas"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Field Position"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        attachment("project-independent-actions", app: app)
    }

    @MainActor
    func testCanvasAndManualForwardInverse() throws {
        let app = makeApp(); app.launch(); app.activate()
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
        let app = makeApp(); app.launch(); app.activate()
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
        let app = makeApp(); app.launch(); app.activate()
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
        for _ in 0..<5 where !importButton.isHittable { app.swipeDown() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: importButton)
        waitForExpectations(timeout: 30)
        importButton.tap()
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 60)); browse.tap()
        func cell(_ label: String) -> XCUIElement {
            app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        }
        // Files remembers the last browsed location between presentations.
        // Navigate actual picker cells; app titles must never match a folder.
        let file = cell(name)
        for _ in 0..<6 {
            if file.waitForExistence(timeout: 3), file.isHittable { break }
            let folder = cell("RoadStation")
            let local = cell("On My iPhone")
            let back = app.buttons["DOC.navBarButton.backInHistory"]
            if folder.waitForExistence(timeout: 3), folder.isHittable { folder.tap() }
            else if local.waitForExistence(timeout: 3), local.isHittable { local.tap() }
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
        let app = makeApp(); app.launch(); app.activate()
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
        let app = makeApp(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("multiple-alignments", alignment: "NORTH", in: app)
        app.otherElements["engineering-canvas"].coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["result-offset"].label.contains("RT"))
    }
    @MainActor
    func testCRSPickerSearchRecommendationConfirmationAndManualFallback() throws {
        let app = makeApp(); app.launch(); app.activate()
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
        revealFieldSetup(app)
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
        revealFieldSetup(app)
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["confirmed-crs"].label.contains("EPSG:6510"))
        attachment("phase2b1-crs-selected", app: app)
        app.buttons["open-crs-picker"].tap()
        app.buttons["open-manual-epsg"].tap()
        set("epsg-entry", "3857", in: app); app.buttons["select-epsg"].tap()
        revealFieldSetup(app)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "EPSG:3857"), evaluatedWith: app.staticTexts["confirmed-crs"])
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testFieldPositionExplicitCRSAndDebugPipeline() throws {
        let app = makeApp(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sample("tangent-only", alignment: "TANGENT", in: app)
        let open = app.buttons["open-field-position"]
        for _ in 0..<4 where !open.isHittable { app.swipeDown() }
        open.tap()
        XCTAssertFalse(app.buttons["start-location"].exists)
        XCTAssertFalse(app.buttons["stop-location"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["field-safety-status"].label.contains("CRS required"))
        let picker = app.buttons["open-crs-picker"]
        for _ in 0..<6 where !picker.isHittable { pageUp(app) }
        picker.tap()
        let manual = app.buttons["open-manual-epsg"]
        for _ in 0..<6 where !manual.isHittable { pageUp(app) }
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); manual.tap()
        set("epsg-entry", "999999", in: app)
        app.buttons["select-epsg"].tap()
        let status = app.staticTexts["manual-epsg-status"]
        let unavailable = NSPredicate(format: "label CONTAINS %@", "CRS unavailable")
        expectation(for: unavailable, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        set("epsg-entry", "3857", in: app)
        app.buttons["select-epsg"].tap()
        revealFieldSetup(app)
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        // Independent inverse spherical Mercator formula (R=6378137m),
        // E=1050,N=1995 US survey feet. No RoadStation inverse supplies this fix.
        // No Start action: explicit CRS confirmation enables location automatically.
        let liveStatus = app.descendants(matching: .any)["field-safety-status"]
        expectation(for: NSPredicate(format: "value == %@", "active"), evaluatedWith: app.staticTexts["location-source"])
        waitForExpectations(timeout: 10)
        revealDebugLocation(app)
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
        XCTAssertTrue(app.descendants(matching: .any)["field-map"].waitForExistence(timeout: 20))
        let cameraActions = app.buttons["field-camera-actions"]
        XCTAssertEqual(cameraActions.value as? String, "Satellite")
        cameraActions.tap()
        app.buttons["Street Map"].tap()
        XCTAssertEqual(cameraActions.value as? String, "Street Map")
        attachment("phase2c-street-map", app: app)
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: On")
        cameraActions.tap()
        app.buttons["Satellite"].tap()
        XCTAssertEqual(cameraActions.value as? String, "Satellite")
        attachment("phase2c-satellite", app: app)
        cameraActions.tap()
        app.buttons["Engineering View"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["field-map"].exists)
        attachment("phase2c-engineering-fallback", app: app)
        XCTAssertEqual(station.label, "STA 100+50.00")
        app.buttons["field-camera-actions"].tap()
        app.buttons["Show Map"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["field-map"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["field-camera-actions"].value as? String, "Satellite")
        attachment("phase2b-field-position", app: app)
        let canvas = app.otherElements["field-alignment-canvas"]
        XCTAssertTrue(canvas.exists)
        let freshCanvasFrame = canvas.frame
        let freshStationFrame = station.frame
        let readout = app.descendants(matching: .any)["field-result-card"]
        let freshReadoutFrame = readout.frame
        XCTAssertLessThanOrEqual(readout.frame.maxY - app.staticTexts["location-source"].frame.maxY, 32, "The card must hug its remaining content")
        XCTAssertFalse(app.staticTexts["live-age"].exists, "No ticking fix-age counter")
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.65))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.45, dy: 0.65)))
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: Paused")
        XCTAssertEqual(app.staticTexts["location-source"].value as? String, "active", "Browsing must keep the field session active")
        app.buttons["field-recenter"].tap()
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: Paused")
        app.buttons["field-follow"].tap()
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: On")
        app.buttons["field-details-toggle"].tap()
        expectation(for: NSPredicate(format: "value == %@", "Expanded"), evaluatedWith: app.buttons["field-details-toggle"])
        waitForExpectations(timeout: 5)
        waitForStableFrame(canvas)
        XCTAssertEqual(app.staticTexts["location-source"].value as? String, "active", "Details must keep the field session active")
        attachment("phase2c-field-details-expanded", app: app)
        app.buttons["field-details-toggle"].tap()
        expectation(for: NSPredicate(format: "value == %@", "Collapsed"), evaluatedWith: app.buttons["field-details-toggle"])
        waitForExpectations(timeout: 5)
        waitForStableFrame(canvas)
        for id in ["live-station", "live-offset", "live-accuracy", "location-source"] {
            XCTAssertTrue(fullyVisible(app.staticTexts[id], in: app), "Primary field reading must be visible without scrolling: \(id)")
        }
        XCTAssertTrue(app.buttons["field-details-toggle"].label.contains("TANGENT"))
        XCTAssertTrue(app.buttons["field-details-toggle"].isHittable)
        XCTAssertFalse(app.staticTexts["Easting"].exists)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Stale — last known position"), evaluatedWith: liveStatus)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertTrue(app.staticTexts["live-offset"].label.contains("5.0 ft RT"))
        XCTAssertTrue(app.staticTexts["live-accuracy"].label.contains("13.1 ft"))
        XCTAssertTrue((canvas.value as? String)?.contains("Last known position") == true)
        XCTAssertEqual(canvas.frame.height, freshCanvasFrame.height, accuracy: 1, "Staleness must not resize the canvas")
        XCTAssertEqual(station.frame.minY, freshStationFrame.minY, accuracy: 1)
        XCTAssertEqual(readout.frame.height, freshReadoutFrame.height, accuracy: 1)
        let safety = app.descendants(matching: .any)["field-safety-status"]
        XCTAssertTrue(safety.label.contains("Stale"))
        app.buttons["field-details-toggle"].tap()
        waitForStableFrame(canvas)
        XCTAssertTrue(fullyVisible(safety, in: app), "Safety status must stay visible when details expand")
        app.buttons["field-details-toggle"].tap()
        attachment("phase2b-stale-last-known-position", app: app)
        revealDebugLocation(app)
        let inject = app.buttons["inject-location"]
        for _ in 0..<6 where !inject.isHittable { pageUp(app) }
        inject.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Current fix"), evaluatedWith: liveStatus)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(station.label, "STA 100+50.00")
        app.buttons["field-details-toggle"].tap()
        XCTAssertEqual(app.buttons["field-details-toggle"].value as? String, "Expanded")
        waitForStableFrame(canvas)
        let expandedCanvasFrame = canvas.frame
        let expandedStationFrame = station.frame
        let expandedReadoutFrame = readout.frame
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Stale — last known position"), evaluatedWith: liveStatus)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(canvas.frame.height, expandedCanvasFrame.height, accuracy: 1, "Staleness must not resize the expanded canvas")
        XCTAssertEqual(station.frame.minY, expandedStationFrame.minY, accuracy: 1)
        XCTAssertEqual(readout.frame.height, expandedReadoutFrame.height, accuracy: 1)
        // Background stops/clears the synthetic fix. Foreground restarts device location.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.navigationBars["Field Position"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["location-source"].label.contains("DEBUG injected"))
        expectation(for: NSPredicate(format: "value == %@", "active"), evaluatedWith: app.staticTexts["location-source"])
        waitForExpectations(timeout: 10)
        // Exiting and re-entering starts a new location visit, never reviving the debug fix.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["open-field-position"].tap()
        XCTAssertTrue(app.navigationBars["Field Position"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["location-source"].label.contains("DEBUG injected"))
        expectation(for: NSPredicate(format: "value == %@", "active"), evaluatedWith: app.staticTexts["location-source"])
        waitForExpectations(timeout: 10)
        attachment("field-auto-resumed", app: app)
    }

    @MainActor
    func testMapSyntheticGeographicAlignment() throws {
        let app = makeApp(); app.launch(); app.activate()
        sample("sr82_synthetic", alignment: "SR 82", in: app)
        let open = app.buttons["open-field-position"]
        for _ in 0..<5 where !open.isHittable { app.swipeDown() }
        open.tap()
        app.buttons["confirm-imported-crs"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["field-map"].waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Alignment overlay ready"),
                    evaluatedWith: app.descendants(matching: .any)["field-alignment-canvas"])
        waitForExpectations(timeout: 20)
        // Only the independently declared synthetic EPSG is used; imagery is not an accuracy reference.
        attachment("phase2c-synthetic-geographic-alignment", app: app)
        app.buttons["field-camera-actions"].tap()
        app.buttons["Street Map"].tap()
        attachment("phase2c-synthetic-street-alignment", app: app)
        app.buttons["field-camera-actions"].tap()
        app.buttons["Fit Alignment"].tap()
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: Paused")
        app.navigationBars.buttons.firstMatch.tap()
        let inspection = app.descendants(matching: .any)["inspection-map"]
        XCTAssertTrue(inspection.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Alignment overlay ready"), evaluatedWith: inspection)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.staticTexts["Tangent"].exists)
        XCTAssertTrue(app.staticTexts["Curve"].exists)
        XCTAssertTrue(app.staticTexts["Spiral"].exists)
        inspection.coordinate(withNormalizedOffset: .init(dx: 0.45, dy: 0.55)).tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        let station = app.staticTexts["result-station"].label
        attachment("phase2c-inspection-satellite-query", app: app)
        app.buttons["inspection-map-actions"].tap()
        app.buttons["Street Map"].tap()
        XCTAssertEqual(app.buttons["inspection-map-actions"].value as? String, "Street Map")
        attachment("phase2c-inspection-street-query", app: app)
        app.buttons["inspection-map-actions"].tap()
        app.buttons["Engineering View"].tap()
        XCTAssertTrue(app.otherElements["engineering-canvas"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["result-station"].label, station)
        app.buttons["Show Map"].tap()
        XCTAssertTrue(inspection.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["result-station"].label, station)
        app.segmentedControls["workspace-tabs"].buttons["Entry"].tap()
        // Independent point: 50 ft along the fixture's first eastward tangent, 5 ft south (RT).
        set("easting-entry", "986377.5959036754", in: app)
        set("northing-entry", "1453406.9250950934", in: app)
        let calculate = app.buttons["calculate-forward"]
        for _ in 0..<4 where !calculate.isHittable { pageUp(app) }
        calculate.tap()
        XCTAssertTrue(app.staticTexts["result-station"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["result-station"].label, "STA 100+50.00")
        XCTAssertEqual(app.staticTexts["result-offset"].label, "5.000 ft RT")
        for _ in 0..<6 where !app.buttons["inspection-map-actions"].isHittable { app.swipeDown() }
        attachment("phase2c-inspection-manual-query", app: app)
    }

    @MainActor
    func testFieldCloseZoomSurvivesRecenterAndFollow() throws {
        let app = makeApp(); app.launch(); app.activate()
        sample("tangent-only", alignment: "TANGENT", in: app)
        app.buttons["open-field-position"].tap()
        app.buttons["open-crs-picker"].tap()
        app.segmentedControls["crs-picker-tabs"].buttons["Search"].tap()
        let manual = app.buttons["open-manual-epsg"]
        for _ in 0..<12 where !manual.isHittable { pageUp(app) }
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); manual.tap()
        set("epsg-entry", "3857", in: app); app.buttons["select-epsg"].tap()
        revealDebugLocation(app)
        set("injected-latitude", "0.005462450563693558", in: app)
        set("injected-longitude", "0.0028749739852440867", in: app)
        set("injected-accuracy", "4", in: app)
        let inject = app.buttons["inject-location"]
        for _ in 0..<5 where !inject.isHittable { pageUp(app) }
        inject.tap()
        let canvas = app.descendants(matching: .any)["field-alignment-canvas"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Nearest point shown"), evaluatedWith: canvas)
        waitForExpectations(timeout: 20)
        waitForStableFrame(app.buttons["field-details-toggle"])
        func width() -> Double {
            let summary = canvas.value as? String ?? ""
            guard let suffix = summary.components(separatedBy: "Map width ").last,
                  let value = Double(suffix.components(separatedBy: " ").first ?? "") else {
                XCTFail("Map must expose its visible scale: \(summary)"); return .infinity
            }
            return value
        }
        for _ in 0..<10 {
            app.buttons["field-camera-actions"].tap(); app.buttons["Zoom in"].tap()
        }
        let buttonZoomWidth = width()
        XCTAssertLessThan(buttonZoomWidth, 10, "Button zoom must reach a close native view")
        app.descendants(matching: .any)["field-map"].pinch(withScale: 2, velocity: 1)
        let closeWidth = width()
        XCTAssertLessThan(closeWidth, buttonZoomWidth * 0.9, "Pinch must continue zooming beyond the former limit")
        XCTAssertLessThan(closeWidth, 10, "Native camera must allow a view narrower than ten meters")
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: Paused")
        app.buttons["field-recenter"].tap()
        XCTAssertEqual(width(), closeWidth, accuracy: max(0.1, closeWidth * 0.05))
        app.buttons["field-follow"].tap()
        revealDebugLocation(app)
        for _ in 0..<5 where !inject.isHittable { pageUp(app) }
        inject.tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Nearest point shown"), evaluatedWith: canvas)
        waitForExpectations(timeout: 20)
        waitForStableFrame(app.buttons["field-details-toggle"])
        XCTAssertEqual(app.buttons["field-follow"].label, "Follow: On")
        XCTAssertEqual(width(), closeWidth, accuracy: max(0.1, closeWidth * 0.05))
        XCTAssertEqual(app.staticTexts["live-station"].label, "STA 100+50.00")
        attachment("phase2c-close-zoom-preserved", app: app)
    }

    @MainActor
    func testFieldPositionLargeTextReadout() throws {
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.activate()
        sample("tangent-only", alignment: "TANGENT", in: app)
        app.buttons["open-field-position"].tap()
        app.buttons["open-crs-picker"].tap()
        app.segmentedControls["crs-picker-tabs"].buttons["Search"].tap()
        let manual = app.buttons["open-manual-epsg"]
        for _ in 0..<12 where !manual.isHittable { pageUp(app) }
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); manual.tap()
        set("epsg-entry", "3857", in: app); app.buttons["select-epsg"].tap()
        XCTAssertTrue(app.navigationBars["Field Position"].waitForExistence(timeout: 20))
        revealDebugLocation(app)
        set("injected-latitude", "0.005462450563693558", in: app)
        set("injected-longitude", "0.0028749739852440867", in: app)
        set("injected-accuracy", "40", in: app)
        let inject = app.buttons["inject-location"]
        for _ in 0..<5 where !inject.isHittable { pageUp(app) }
        inject.tap()
        let station = app.staticTexts["live-station"]
        XCTAssertTrue(station.waitForExistence(timeout: 10))
        XCTAssertEqual(station.label, "STA 100+50.00")
        XCTAssertGreaterThan(station.frame.height, 60, "Station must follow the accessibility text size")
        XCTAssertLessThanOrEqual(station.frame.maxX, app.frame.width)
        attachment("field-accessibility-reading", app: app)
        let status = app.descendants(matching: .any)["field-safety-status"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Stale — last known position"), evaluatedWith: status)
        waitForExpectations(timeout: 12)
        XCTAssertGreaterThan(status.frame.height, 30, "Large warnings must wrap without a fixed-height cap")
        let safety = app.descendants(matching: .any)["field-safety-status"]
        XCTAssertTrue(safety.label.contains("Stale")); XCTAssertTrue(safety.label.contains("Poor GPS accuracy"))
        XCTAssertTrue(fullyVisible(safety, in: app))
        XCTAssertGreaterThanOrEqual(safety.frame.minY, app.descendants(matching: .any)["field-result-card"].frame.maxY, "Warnings must not cover the reading")
        attachment("field-accessibility-stale", app: app)
        safety.swipeUp()
        attachment("field-accessibility-warning-scrolled", app: app)
    }

    @MainActor
    func testSavedProjectImportColdStartCRSAlignmentRenameAndDelete() throws {
        executionTimeAllowance = 420 // Multiple cold launches and the real system Files UI.
        let app = makeApp(); app.launch(); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        pickFile("import-multi", app: app)
        revealImportedAlignment("NORTH", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["project-alignment-count"].exists)
        app.buttons["alignment-NORTH"].tap()
        XCTAssertTrue(app.otherElements["engineering-canvas"].waitForExistence(timeout: 10))
        let field = app.buttons["open-field-position"]
        for _ in 0..<5 where !field.isHittable { app.swipeDown() }
        field.tap()
        let choose = app.buttons["open-crs-picker"]
        for _ in 0..<5 where !choose.isHittable { pageUp(app) }
        choose.tap()
        let manual = app.buttons["open-manual-epsg"]
        for _ in 0..<5 where !manual.isHittable { pageUp(app) }
        manual.tap(); set("epsg-entry", "3857", in: app); app.buttons["select-epsg"].tap()
        revealFieldSetup(app)
        XCTAssertTrue(app.staticTexts["confirmed-crs"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["confirmed-crs"].label.contains("EPSG:3857"))
        // Wait for the actual persistence summary, not a sleep before termination.
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.descendants(matching: .any)["restored-alignment"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.descendants(matching: .any)["restored-alignment"].waitForExistence(timeout: 10))
        for _ in 0..<6 where !app.staticTexts["project-save-status"].isHittable { app.swipeDown() }
        expectation(for: NSPredicate(format: "label == %@", "Project saved"), evaluatedWith: app.staticTexts["project-save-status"])
        waitForExpectations(timeout: 10)
        attachment("phase2b2-selected-project", app: app)
        app.terminate(); app.launch(); app.activate()
        let saved = app.buttons["saved-project-import-multi"]
        XCTAssertTrue(saved.waitForExistence(timeout: 20)); saved.tap()
        let count = app.descendants(matching: .any)["project-alignment-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10)); XCTAssertTrue(count.label.contains("2") || count.value as? String == "2")
        let restored = app.descendants(matching: .any)["restored-alignment"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10)); XCTAssertTrue(restored.label.contains("NORTH") || (restored.value as? String)?.contains("NORTH") == true)
        let confirmed = app.staticTexts["confirmed-crs"]
        for _ in 0..<5 where !confirmed.isHittable { pageUp(app) }
        XCTAssertTrue(confirmed.label.contains("EPSG:3857"))
        attachment("phase2b2-cold-start-restored", app: app)
        let rename = app.buttons["rename-project"]
        for _ in 0..<7 where !rename.isHittable { pageUp(app) }
        rename.tap()
        XCTAssertTrue(app.navigationBars["Rename Project"].waitForExistence(timeout: 5))
        set("rename-project-name", "Saved Road Test", in: app)
        app.buttons["save-project-name"].tap()
        XCTAssertTrue(app.navigationBars["Saved Road Test"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.activate()
        let renamed = app.buttons["saved-project-Saved Road Test"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 20)); renamed.tap()
        let delete = app.buttons["delete-project"]
        for _ in 0..<8 where !delete.isHittable { pageUp(app) }
        delete.tap(); XCTAssertTrue(app.alerts["Delete Project?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.alerts["Delete Project?"].exists)
        delete.tap(); app.alerts["Delete Project?"].buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["RoadStation"].waitForExistence(timeout: 20))
        XCTAssertFalse(renamed.exists)
        app.terminate(); app.launch(); app.activate()
        XCTAssertTrue(app.navigationBars["RoadStation"].waitForExistence(timeout: 20))
        XCTAssertFalse(renamed.exists)
        attachment("phase2b2-deleted-project", app: app)
    }

}
