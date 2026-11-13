import XCTest

final class ListenUITests:XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 90 }
    func testLibraryPlayerAndSettings() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        let book=app.cells.containing(.staticText,identifier:"Sample recording").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:30));book.tap()
        let start=app.buttons["startListening"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        let play=app.buttons["playerPlayPause"];XCTAssertTrue(play.waitForExistence(timeout:15))
        app.buttons["addBookmark"].tap();XCTAssertTrue(app.staticTexts["bookmarkSaved"].waitForExistence(timeout:5))
        let playerShot = XCTAttachment(screenshot: app.screenshot()); playerShot.name = "Player"; playerShot.lifetime = .keepAlways; add(playerShot)
        play.tap();app.buttons["closePlayer"].tap()
        XCTAssertTrue(app.buttons["startListening"].waitForExistence(timeout:10))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Player flow";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testSettings() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Library & iCloud"].waitForExistence(timeout:10))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Settings";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testLibraryScreenshot() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        XCTAssertTrue(app.staticTexts["Sample recording"].firstMatch.waitForExistence(timeout:30))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Library";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testServerConnectionForm() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        app.buttons["Servers"].firstMatch.tap()
        let addServer = app.buttons["addServer"]; XCTAssertTrue(addServer.waitForExistence(timeout: 10)); addServer.tap()
        XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Use an API token"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Servers"; shot.lifetime = .keepAlways; add(shot)
    }

}
