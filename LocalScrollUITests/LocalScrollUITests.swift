//
//  LocalScrollUITests.swift
//  LocalScrollUITests
//
//  Created by Yiren Wang on 6/2/26.
//

import XCTest

final class LocalScrollUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    // MARK: - Acceptance-doc UI coverage (LocalScroll_iOS_Acceptance_Test.docx)

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    /// S-01 (launch / three tabs) + S-02 control presence (Photos / Files / presets / Caption).
    @MainActor
    func testAcceptanceS01ExtractControlsPresent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Extract"].waitForExistence(timeout: 15), "Extract tab missing")
        XCTAssertTrue(app.tabBars.buttons["History"].exists, "History tab missing")
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists, "Settings tab missing")

        XCTAssertTrue(app.buttons["Photos"].exists, "Photos button missing")
        XCTAssertTrue(app.buttons["Files"].exists, "Files button missing")

        let seg = app.segmentedControls.firstMatch
        XCTAssertTrue(seg.buttons["Fast"].exists, "Fast preset missing")
        XCTAssertTrue(seg.buttons["Smart"].exists, "Smart preset missing")
        XCTAssertTrue(seg.buttons["Precise"].exists, "Precise preset missing")

        XCTAssertTrue(app.switches["Caption"].exists, "Caption toggle missing")
        XCTAssertTrue(app.staticTexts["No Videos Queued"].exists, "Empty-state missing")

        attach(app, "S01_extract_tab")
    }

    /// History tab loads (F-30) + Settings tab exposes every documented option (F-39..F-44).
    @MainActor
    func testAcceptanceHistoryAndSettingsTabs() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 15))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "History nav title missing")
        attach(app, "F30_history_tab")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings nav title missing")
        XCTAssertTrue(app.staticTexts["Appearance"].exists, "Appearance row missing")          // F-39/F-40
        XCTAssertTrue(app.staticTexts["OCR Language"].exists, "OCR Language row missing")       // F-41
        XCTAssertTrue(app.staticTexts["Generate Summary"].exists, "Summary row missing")        // F-44
        XCTAssertTrue(app.switches["Cache Original Videos"].exists, "Cache toggle missing")     // F-42
        XCTAssertTrue(app.staticTexts["Manage Cached Videos"].exists, "Cache manager missing")  // F-43
        attach(app, "F39_settings_tab")
    }

    /// F-39: switching Appearance to Dark persists across a relaunch.
    @MainActor
    func testAcceptanceF39DarkModePersists() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()

        // In a SwiftUI Form the picker row is a button/cell; the label static-text
        // itself is not hittable, so tap the enclosing cell to open the menu.
        let appearanceRow = app.cells.containing(.staticText, identifier: "Appearance").firstMatch
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5), "Appearance row missing")
        appearanceRow.tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5), "Dark option missing from Appearance menu")
        dark.tap()
        attach(app, "F39_dark_selected")

        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        // The persisted choice is shown on the Appearance row's value.
        XCTAssertTrue(app.staticTexts["Dark"].waitForExistence(timeout: 5), "Dark mode did not persist")
        attach(app, "F39_dark_persisted")
    }

    /// S-02..S-05 best-effort: pick a video from the seeded Photos library, process with
    /// the Fast preset, then confirm a History record appears. The system photo picker is
    /// out-of-process and version-sensitive, so picker interaction is defensive.
    @MainActor
    func testAcceptanceS02toS05ProcessFromPhotos() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 15))

        // Fast preset keeps the simulator-CPU OCR run short.
        app.segmentedControls.firstMatch.buttons["Fast"].tap()

        app.buttons["Photos"].tap()

        // The PHPicker runs out-of-process; its asset grid is exposed as cells (preferred)
        // or bare images depending on the iOS version. Try the most specific first.
        let assetCell = app.collectionViews.cells.firstMatch
        let assetImage = app.images.element(boundBy: 0)
        let asset: XCUIElement
        if assetCell.waitForExistence(timeout: 15) {
            asset = assetCell
        } else if assetImage.waitForExistence(timeout: 5) {
            asset = assetImage
        } else {
            throw XCTSkip("System photo picker did not expose any assets in this environment.")
        }
        asset.tap()

        // PHPicker confirm button is "Add" (navbar) — falls back to "Done"/auto-dismiss.
        for label in ["Add", "Done"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 3) && button.isHittable {
                button.tap()
                break
            }
        }

        // S-02: confirm we returned to the app (the Photos button is hittable again, i.e.
        // the picker dismissed) AND a real queue row replaced the empty state. The headless
        // PHPicker is version-/permission-sensitive (limited-library mode, orientation); if
        // the selection did not commit, SKIP rather than fail — the import→process→history
        // chain is independently covered by EndToEndComparisonTests + the unit suite.
        let photosButton = app.buttons["Photos"]
        let backInApp = photosButton.waitForExistence(timeout: 10) && photosButton.isHittable
        let hasQueueRow = backInApp
            && !app.staticTexts["No Videos Queued"].exists
            && app.cells.firstMatch.exists
        guard hasQueueRow else {
            attach(app, "S02_picker_not_committed")
            throw XCTSkip("Headless PHPicker selection did not commit in this simulator; "
                + "verify S-02..S-05 on a device or via interactive control. Extraction "
                + "itself is covered by EndToEndComparisonTests + the unit suite.")
        }
        attach(app, "S02_queued")

        // S-03: wait for completion — the row's status becomes "<N> lines".
        let done = NSPredicate(format: "label CONTAINS[c] 'line'")
        let statusLabel = app.staticTexts.containing(done).firstMatch
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 180), "Processing did not finish")
        attach(app, "S03_done")

        // S-04: the result shows up in History.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10), "No History record")
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 10), "Copy button missing in detail")
        attach(app, "S04_history_detail")

        // S-05: Copy is actionable.
        app.buttons["Copy"].tap()
    }
}
